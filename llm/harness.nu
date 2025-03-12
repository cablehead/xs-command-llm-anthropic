use chat-chain.nu *

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
                "text" => $"Text:\n"
                "tool_use" => $"Tool-Use::($chunk.content_block.name)\n"
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
            "content_block_stop" => "\n\n"
            "message_delta" => null
            "message_stop" => null
            "ping" => null
            _ => $"\n($chunk.type)\n"
          }
        } | if $in != null { print -n $in }
        {next: true}
      }

      {topic: "llm.response"} => {
        return {out: $frame}
      }

      _ => {next: true}
    }
  } | first
}

export def process-response [frame: record --yes (-y)] {
  match $frame.meta.message.stop_reason {
    "tool_use" => {
      let todo = .cas $frame.hash | from json | where type == "tool_use"
      print "Execute the following tool use:\n"
      print ($todo | select name input | table -e)
      if not $yes {
        if (["yes" "no"] | input list) != "yes" { return {} }
      }
      let result = $todo | each { run-tool }
      print ($result | table -e)

      let req = $result | to json -r | .append llm.call --meta {continues: [$frame.id], with_tools: true, mime_type: "application/json"}
      follow-response $req
    }
    "end_turn" => null
    _ => ( error make {msg: $"TODO: ($frame | table -e)"})
  }
}

export def follow-response [req: record] {
  let response = .cat --last-id $req.id -f | stream-response $req.id
  process-response $response
}

def str_replace_editor [] {
  select input | update input.path { str replace -r '^/repo' (pwd) } | to json -r | anthropic-text-editor | from json
}

export def run-tool [] {
  let tool = $in

  let resp = (
    match $tool.name {
      "str_replace_editor" => ($tool | str_replace_editor)
      "bash" => {
        if ("resp" | path exists) {
          {content: (cat resp)}
        } else {
          {content: (bash -c ($tool.input.command | str replace -r '^/repo' (pwd)) o+e>| complete | get stdout)}
        }
      }
    }
  )

  {
    type: "tool_result"
    tool_use_id: $tool.id
  } | merge $resp
}
