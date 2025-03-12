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
  let frame = $content | .append llm.call --meta $meta
  let response = .cat --last-id $frame.id -f | stream-response $frame.id
  process-response $response
}
