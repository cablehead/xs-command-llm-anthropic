export def stream-response [call_id: string] {
  generate {|frame cont = false|
    if $frame.meta?.frame_id? != $call_id { return {next: true} }
    match $frame {
      {topic: "llm.recv"} => {
        out: (
          .cas $frame.hash | from json | each {|chunk|
            match $chunk.type {
              "message_start" => $"($chunk | get message.model) ($chunk | get message.usage | to yaml | lines | str join ' ')\n"
              "content_block_start" => (
                match $chunk.content_block.type {
                  "text" => $"text: "
                  "tool_use" => $"tool-use: "
                  _ => ( error make {msg: $"TODO: ($chunk)"})
                }
              )
              "content_block_delta" => (
                match $chunk.delta.type {
                  "text_delta" => $chunk.delta.text
                  "input_json_delta" => $chunk.delta.partial_json
                  _ => ( error make {msg: $"TODO: ($chunk)"})
                }
              )
              "content_block_stop" => "\n"
              "message_delta" => null
              "message_stop" => null
              "ping" => null
              _ => $"\n($chunk.type)\n"
            }
          }
        )
        next: true
      }
      {topic: "llm.response"} => {out: ($frame | insert "response" (.cas $frame.hash | from json))}
      _ => {next: true}
    }
  } | compact
}

export def .llm [ --with-tools] {
  let frame = .append llm.call --meta {with_tools: $with_tools}
  print ($frame | ept)
  .cat --last-id $frame.id -f | stream-response $frame.id
}
