def conditional-pipe [
  condition: bool
  action: closure
] {
  if $condition { do $action } else { $in }
}

# aggregation
def content-block-delta [current_block event] {
  match $event.delta.type {
    "text_delta" => ($current_block | update text { $in | append $event.delta.text })
    "input_json_delta" => ($current_block | upsert partial_json { $in | default [] | append $event.delta.partial_json })
    _ => ( error make {msg: $"TBD: ($event)"})
  }
}

def content-block-finish [content_block] {
  match $content_block.type {
    "text" => ($content_block | update text { str join })
    "tool_use" => ($content_block | update input {|x| $x.partial_json | str join | from json } | reject partial_json?)
    _ => { error make {msg: $"TBD: ($content_block)"} }
  }
}

def theagg [] {
  collect {|events|
    mut response = {
      role: "assistant"
      mime_type: "application/json"
    }
    for event in $events {
      match $event.type {
        "message_start" => ($response.message = $event.message)
        "content_block_start" => ($response.current_block = $event.content_block)
        "content_block_delta" => ($response.current_block = content-block-delta $response.current_block $event)
        "content_block_stop" => ($response.message.content =  $response.message.content | append (content-block-finish $response.current_block))
        "message_delta" => ($response = ($response | merge deep {message: ($event.delta | insert usage $event.usage)}))
        "message_stop" => ($response = ($response | reject current_block))
        "ping" => (continue)
        _ => (
          error make {msg: $"\n\n($response | table -e)\n\n($event | table -e)"}
        )
      }
    }

    $response
  }
}
###### end aggregation

def thecall [] {
  {|model: string, tools?: list|
    let data = {
      model: $model
      max_tokens: 8192
      stream: true
      # TODO: anthropic only supports a single system message as a top level attribute
      messages: ($in | update role {|x| if $x.role == "system" { "user" } else { $x.role } })
      tools: ($tools | default [])
    }

    let headers = {
      "x-api-key": $env.ANTHROPIC_API_KEY
      "anthropic-version": "2023-06-01"
    } | conditional-pipe ($data | get tools | is-not-empty) {
      insert "anthropic-beta" "computer-use-2024-10-22"
    }

    (
      http post
      --content-type application/json
      -H $headers
      https://api.anthropic.com/v1/messages
      $data
    )

    # try {
    # } catch {|err|
    # let response = (
    # http post
    # --content-type application/json
    # -f -e
    # -H $headers
    # https://api.anthropic.com/v1/messages
    # $data | table -e | to text
    # )
    # error make {msg: $response}
    # }
  }
}

def frame-to-message [frame: record] {
  let meta = $frame | get meta? | default {}
  let role = $meta | default "user" role | get role

  let content = if ($frame | get hash? | is-not-empty) { .cas $frame.hash }
  if ($content | is-empty) { return }

  let content = (
    if ($meta.type? == "document" and $meta.content_type? != null) {
      [
        {
          "type": "document"
          "cache_control": {"type": "ephemeral"}
          "source": {
            "type": "base64"
            "media_type": $meta.content_type
            "data": ($content | encode base64)
          }
        }
      ]
    } else if (($meta | get mime_type?) == "application/json") {
      $content | from json
    } else {
      $content
    }
  )

  {
    id: $frame.id
    role: $role
    content: $content
  }
}

def traverse-thread [id: string] {
  generate {|state|
    if ($state.stack | is-empty) { return {out: $state.chain} }
    let next = $state.stack | first
    let frame = .get $next
    {
      next: {
        stack: ($state.stack | skip 1 | append ($frame.meta?.continues? | default []))
        chain: ($state.chain | prepend $frame.id)
      }
    }
  } {stack: [$id] chain: []} | last
}

def id-to-messages [ids] {
  mut messages = []
  mut stack = [] | append $ids

  while not ($stack | is-empty) {
    let current_id = $stack | first
    let frame = .get $current_id
    $messages = ($messages | prepend (frame-to-message $frame))

    $stack = ($stack | skip 1)

    let next_id = $frame | get meta?.continues?
    match ($next_id | describe -d | get type) {
      "string" => { $stack = ($stack | append $next_id) }
      "list" => { $stack = ($stack | append $next_id) }
      "nothing" => { }
      _ => ( error make {msg: "TBD"})
    }
  }

  $messages
}

const computer_tools = [
  {type: "text_editor_20241022" name: "str_replace_editor"}
  {type: "bash_20241022" name: "bash"}
]

def .call [ids --with-tools] {
  id-to-messages $ids | if ($in | is-empty) { error make {msg: "No messages found"} } else {
    reject id
    | do (thecall) "claude-3-7-sonnet-20250219" (if $with_tools { $computer_tools })
    | lines
    | each {|line| $line | split row -n 2 "data: " | get 1? }
    | each {|x| $x | from json }
  }
}

{
  return_options: {
    ttl: "ephemeral"
  }

  process: {|frame|
    $env.ANTHROPIC_API_KEY = .head ANTHROPIC_API_KEY | .cas $in.hash
    .call $frame.id | tee {
      theagg | do {
        let x = $in
        $x | get message.content | to json -r | .append llm.response --meta (
          $x | reject message.content | insert continues $frame.id
        )
      }
    }
  }
}
