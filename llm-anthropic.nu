export def stream-response [call_id: string] {
  generate {|frame cont = false|
    if $frame.meta?.frame_id? != $call_id { return {next: true} }
    match $frame {
      {topic: "llm.recv"} => {
        out: (.cas $frame.hash)
        next: true
      }
      {topic: "llm.response"} => {out: (.cas $frame.hash)}
      _ => {next: true}
    }
  }
}

export def .llm [ --with-tools] {
  let frame = .append llm.call --meta {with_tools: $with_tools}
  print ($frame | ept)
  .cat --last-id $frame.id -f | stream-response $frame.id
}
