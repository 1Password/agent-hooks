# GitHub Copilot (VS Code) adapter.
#
# Copilot input payload:
#   {"hook_event_name": "PreToolUse", "tool_name": "run_in_terminal", "cwd": "..."}
#
# Copilot output:
#   Allow: {"continue": true}                              exit 0
#   Deny:  {"continue": false, "stopReason": "..."}        exit 0
#
# Note: Copilot uses exit 0 for BOTH allow and deny. The decision is in the JSON.

[[ -n "${_ADAPTER_COPILOT_LOADED:-}" ]] && return 0
_ADAPTER_COPILOT_LOADED=1

_ADAPTER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_ADAPTER_DIR}/_lib.sh"

client_detect() {
    local raw_payload="$1"
    # Copilot sends hook_event_name + tool_name, but so does Claude Code.
    # Claude Code is distinguished by the CLAUDE_PROJECT_DIR env var,
    # so Copilot is: has both fields AND no CLAUDE_PROJECT_DIR.
    if [[ -n "${CLAUDE_PROJECT_DIR:-}" ]]; then
        echo "no"
        return 0
    fi

    if json_has_key "$raw_payload" "hook_event_name" && \
       json_has_key "$raw_payload" "tool_name"; then
        echo "yes"
    else
        echo "no"
    fi
}

normalize_input() {
    local raw_payload="$1"

    local cwd tool_name command workspace_roots_json
    cwd=$(extract_json_string "$raw_payload" "cwd")
    tool_name=$(extract_json_string "$raw_payload" "tool_name")
    command=$(extract_json_string "$raw_payload" "command")

    # Copilot provides cwd as the single workspace root
    workspace_roots_json=$(paths_to_json_array "$cwd")

    build_canonical_input \
        "github-copilot" \
        "before_shell_execution" \
        "command" \
        "$workspace_roots_json" \
        "$cwd" \
        "$command" \
        "$tool_name" \
        "$raw_payload"
}

emit_output() {
    local canonical_output="$1"

    local decision message
    decision=$(get_decision "$canonical_output")
    message=$(get_message "$canonical_output")

    if [[ "$decision" == "deny" ]]; then
        local escaped_message
        escaped_message=$(escape_json_string "$message")
        echo "{\"continue\": false, \"stopReason\": \"${escaped_message}\"}"
    else
        echo "{\"continue\": true}"
    fi

    return 0
}
