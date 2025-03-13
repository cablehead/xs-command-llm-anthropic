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
    # anthropic only supports a single system message as a top level attribute
    let messages = $in
    let system_messages = $messages | where role == "system"
    let messages = $messages | where role != "system"

    let data = {
      model: $model
      max_tokens: 8192
      stream: true
      messages: $messages
      tools: ($tools | default [])
    } | conditional-pipe ($system_messages | is-not-empty) {
      insert "system" ($system_messages | get content | flatten)
    }

    let headers = {
      "x-api-key": $env.ANTHROPIC_API_KEY
      "anthropic-version": "2023-06-01"
    } | conditional-pipe ($data | get tools | is-not-empty) {
      insert "anthropic-beta" "computer-use-2024-10-22"
    }

    # try {

    (
      http post
      --content-type application/json
      -H $headers
      https://api.anthropic.com/v1/messages
      $data
    )

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

const computer_tools = {
  "claude-3-5-sonnet-20241022" : [
  {type: "text_editor_20241022" name: "str_replace_editor"}
  {type: "bash_20241022" name: "bash"}
]

  "claude-3-7-sonnet-20250219" : [
  {type: "text_editor_20250124" name: "str_replace_editor"}
  {type: "bash_20250124" name: "bash"}
]
}

def .call [ids --with-tools] {
  let model = "claude-3-7-sonnet-20250219"
  id-to-messages $ids | if ($in | is-empty) { error make {msg: "No messages found"} } else {
    reject id
    | do (thecall) $model (if $with_tools { $computer_tools | get $model })
    | lines
    | each {|line| $line | split row -n 2 "data: " | get 1? }
    | each {|x| $x | from json }
  }
}

{
  return_options: {
    ttl: "ephemeral"
  }

  run: {|frame|
    $env.ANTHROPIC_API_KEY = .head ANTHROPIC_API_KEY | .cas $in.hash
    let with_tools = ($frame | get meta?.with_tools? | default false)
    .call $frame.id --with-tools=($with_tools) | tee {
      theagg | do {
        let x = $in
        $x | get message.content | to json -r | .append llm.response --meta (
          $x | reject message.content | insert continues $frame.id
        )
      }
    }
  }
}
