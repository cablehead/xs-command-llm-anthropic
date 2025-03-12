# To get started:
#   1. overlay use -p ./llm
#   2. $env.ANTHROPIC_API_KEY | llm init-store
#   3. "hola" | llm call
#
# See README.md for more detailed examples and usage patterns.

use harness.nu *

# Sends a prompt to the LLM and retrieves the response
#
# Examples:
#   "Tell me about quantum computing" | llm call
#   "what's does the repo do?" | llm call --with-tools
#   "Continue our discussion" | llm call --respond
export def call [
  ids?: list<string> # Previous message IDs to continue a conversation
  --with-tools # Enable Claude to use tools (bash and text editor)
  --respond (-r) # Continue from the last response
  --json (-j) # Treat input as JSON formatted content
]: string -> record {
  let content = if $in == null { input "Enter prompt: " } else { }
  let ids = if $respond { $ids | append (.head llm.response).id } else { $ids }
  let meta = {with_tools: $with_tools} | if $ids != null { insert continues $ids } else { $in } | if $json { insert mime_type "application/json" } else { $in }
  let req = $content | .append llm.call --meta $meta
  follow-response $req
}

# This is required before using any other llm commands. It stores your
# Anthropic API key and registers the llm.call command in the cross.stream
# store.
#
# Examples:
#   $env.ANTHROPIC_API_KEY | llm init-store
#
# Note: If the API key is invalid, subsequent calls will fail with
# authentication errors. Use a valid Anthropic API key.
#
# Returns: The ID of the registered command definition
export def init-store []: string -> string {
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
