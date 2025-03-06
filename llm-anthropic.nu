export def stream-response [call_id: string] {
  generate {|frame cont = false|
    if $frame.meta?.frame_id? != $call_id { return {next: true} }
    match $frame {
      {topic: "llm.recv"} => {
        out: (
          .cas $frame.hash | from json | each {|chunk|
            match $chunk.type {
              "message_start" => $"($call_id) response-start ($chunk | get message.model) ($chunk | get message.usage | to yaml | lines | str join ' ')\n"
              "content_block_start" => (
                match $chunk.content_block.type {
                  "text" => $"($call_id) text:"
                  "tool_use" => $"($call_id) tool_use:"
                  _ => (make error {msg: $"TODO: ($chunk)"})
                }
              )
              "content_block_stop" => "\n"
              "ping" => null
              _ => $"\n($chunk.type)\n"
            }
          }
        )
        next: true
      }
      {topic: "llm.response"} => {out: (.cas $frame.hash)}
      _ => {next: true}
    }
  } | compact
}

export def .llm [ --with-tools] {
  let frame = .append llm.call --meta {with_tools: $with_tools}
  print ($frame | ept)
  .cat --last-id $frame.id -f | stream-response $frame.id
}
