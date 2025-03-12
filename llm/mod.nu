use harness.nu *

export def call [
  ids?
  --with-tools
  --respond (-r)
  --json (-j)
] {
  let content = if $in == null { input "Enter prompt: " } else { }
  let ids = if $respond { $ids | append (.head llm.response).id } else { $ids }
  let meta = {with_tools: $with_tools} | if $ids != null { insert continues $ids } else { $in } | if $json { insert mime_type "application/json" } else { $in }
  let req = $content | .append llm.call --meta $meta
  follow-response $req
}

export def init-store [] {
  let key = if $in == null {
    let capture = input -s "Enter anthropic key (sk-...): "
    print ""
    $capture
  } else { }

  $key | .append ANTHROPIC_API_KEY

  const base = (path self) | path dirname
  let snippets = [chat-chain.nu xs-command.nu] | each {|x| $base | path join $x }
  cat ...$snippets | .append llm.define | get id
}
