# Claude Code adapter.
#
# Claude Code input payload (PreToolUse / Bash):
#   {"hook_event_name": "PreToolUse", "tool_name": "Bash",
#    "tool_input": {"command": "...", "working_directory": "..."},
#    "cwd": "...", "permission_mode": "..."}
#
# Claude Code also sets the CLAUDE_PROJECT_DIR env var.
#
# Claude Code output:
#   Allow: (empty stdout)     exit 0
#   Deny:  message to stderr  exit 2

[[ -n "${_ADAPTER_CLAUDE_CODE_LOADED:-}" ]] && return 0
_ADAPTER_CLAUDE_CODE_LOADED=1

_ADAPTER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_ADAPTER_DIR}/_lib.sh"

normalize_input() {
    local raw_payload="$1"

    local cwd command tool_name workspace_roots_json
    cwd=$(extract_json_string "$raw_payload" "cwd")
    tool_name=$(extract_json_string "$raw_payload" "tool_name")
    command=$(extract_json_string "$raw_payload" "command")

    # Claude Code provides CLAUDE_PROJECT_DIR as the workspace root.
    local project_dir="${CLAUDE_PROJECT_DIR:-}"

    # Use cwd as fallback if CLAUDE_PROJECT_DIR is not set.
    if [[ -z "$project_dir" ]]; then
        project_dir="$cwd"
    fi

    workspace_roots_json=$(paths_to_json_array "$project_dir")

    build_canonical_input \
        "claude-code" \
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
        echo "$message" >&2
        return 2
    fi

    return 0
}
