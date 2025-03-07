export def stream-response [call_id: string] {
  generate {|frame cont = false|
    if $frame.meta?.frame_id? != $call_id { return {next: true} }
    match $frame {
      {topic: "llm.recv"} => {
        .cas $frame.hash | from json | each {|chunk|
          match $chunk.type {
            "message_start" => null
            "content_block_start" => (
              match $chunk.content_block.type {
                "text" => $"text: "
                "tool_use" => $"tool-use::($chunk.content_block.name) "
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
        } | if $in != null { print -n $in }
        {next: true}
      }

      {topic: "llm.response"} => {
        print ($frame | select topic meta.message.model meta.message.usage meta.message.stop_reason | table -e)
        match $frame.meta.message.stop_reason {
          "tool_use" => {
            print "Execute the following tool use:"
            print (.cas $frame.hash | from json | where type == "tool_use" | select name input | table -e)
            if (["yes" "no"] | input list) != "yes" { return {} }
            print "let's go"
          }

          "end_turn" => null

          _ => ( error make {msg: $"TODO: ($frame | table -e)"})
        }
        return {}
      }

      _ => {next: true}
    }
  }
}

export def .llm [
  ids?
  --with-tools
  --respond (-r)
] {
  let content = $in
  let ids = if $respond { $ids | append (.head llm.response).id } else { $ids }
  let meta = {with_tools: $with_tools} | if $ids != null { insert continues $ids } else { $in }
  let frame = $content | .append llm.call --meta $meta
  print ($frame | ept)
  .cat --last-id $frame.id -f | stream-response $frame.id
}
