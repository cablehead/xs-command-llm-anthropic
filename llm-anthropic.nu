export def stream-response [] {
  generate {|frame cont = false|
    match $frame {
      {topic: "llm.recv"} => {out: "llm.recv" next: true}
      {topic: "llm.response"} => {out: "llm.response"}
      _ => {next: true}
    }
  }
}

export def .llm [ --with-tools] {
  let frame = .append llm.call --meta {with_tools: $with_tools}
  print ($frame | ept)
  .cat --last-id $frame.id -f | stream-response | ept
}
