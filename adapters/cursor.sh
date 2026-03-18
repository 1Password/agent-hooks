# Cursor IDE adapter.
#
# Cursor input payload (beforeShellExecution):
#   {"command": "...", "workspace_roots": ["..."], "cwd": "...",
#    "cursor_version": "1.x.y", "hook_event_name": "beforeShellExecution", ...}
#
# Cursor output:
#   Allow: {"permission": "allow"}            exit 0
#   Deny:  {"permission": "deny", "agent_message": "..."}  exit 0

[[ -n "${_ADAPTER_CURSOR_LOADED:-}" ]] && return 0
_ADAPTER_CURSOR_LOADED=1

_ADAPTER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_ADAPTER_DIR}/_lib.sh"

normalize_input() {
    local raw_payload="$1"

    local cwd command workspace_roots workspace_roots_json
    cwd=$(extract_json_string "$raw_payload" "cwd")
    command=$(extract_json_string "$raw_payload" "command")
    workspace_roots=$(parse_json_workspace_roots "$raw_payload")
    workspace_roots_json=$(paths_to_json_array "$workspace_roots")

    build_canonical_input \
        "cursor" \
        "before_shell_execution" \
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
        local escaped_message
        escaped_message=$(escape_json_string "$message")
        echo "{\"permission\": \"deny\", \"agent_message\": \"${escaped_message}\"}"
    else
        echo "{\"permission\": \"allow\"}"
    fi

    return 0
}
