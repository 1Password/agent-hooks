# Windsurf Cascade adapter (pre_run_command and other Cascade hook events).
#
# Windsurf input (pre_run_command):
#   {"agent_action_name": "pre_run_command",
#    "tool_info": {"command_line": "...", "cwd": "/path"}, ...}
#
# Windsurf output (pre-hooks):
#   Allow: exit 0
#   Deny:  message on stderr, exit 2 (blocking error)

[[ -n "${_ADAPTER_WINDSURF_LOADED:-}" ]] && return 0
_ADAPTER_WINDSURF_LOADED=1

_ADAPTER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_ADAPTER_DIR}/_lib.sh"

normalize_input() {
    local raw_payload="$1"

    local cwd command workspace_roots workspace_roots_json agent_action
    cwd=$(extract_json_string "$raw_payload" "cwd")
    command=$(extract_json_string "$raw_payload" "command_line")
    agent_action=$(extract_json_string "$raw_payload" "agent_action_name")

    # Cascade does not send workspace_roots - use cwd as the single root.
    workspace_roots=$(parse_json_workspace_roots "$raw_payload")
    if [[ -z "$workspace_roots" ]] && [[ -n "$cwd" ]]; then
        workspace_roots="$cwd"
    fi
    workspace_roots_json=$(paths_to_json_array "$workspace_roots")

    # Map shell-related events to the same canonical event as other adapters.
    local canonical_event="before_shell_execution"
    if [[ "$agent_action" != "pre_run_command" ]]; then
        canonical_event=$(printf '%s' "$agent_action" | tr '-' '_')
    fi

    build_canonical_input \
        "windsurf" \
        "$canonical_event" \
        "command" \
        "$workspace_roots_json" \
        "$cwd" \
        "$command" \
        "" \
        "$raw_payload"
}

emit_output() {
    local canonical_output="$1"

    local decision message
    decision=$(get_decision "$canonical_output")
    message=$(get_message "$canonical_output")

    if [[ "$decision" == "deny" ]]; then
        echo "$message" >&2
        return 2
    fi

    return 0
}
