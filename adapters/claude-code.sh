# Claude Code adapter.
#
# Claude Code input payload (PreToolUse / Bash):
#   {"hook_event_name": "PreToolUse", "tool_name": "Bash",
#    "tool_input": {"command": "...", "working_directory": "..."},
#    "cwd": "...", "permission_mode": "..."}
#
# Claude Code input payload (PreToolUse / non-Bash file tools — Read, Edit,
# MultiEdit; NotebookEdit uses "notebook_path" instead of "file_path"):
#   {"hook_event_name": "PreToolUse", "tool_name": "Read",
#    "tool_input": {"file_path": "..."},
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

    local cwd tool_name workspace_roots_json
    cwd=$(extract_json_string "$raw_payload" "cwd")
    tool_name=$(extract_json_string "$raw_payload" "tool_name")

    # Claude Code provides CLAUDE_PROJECT_DIR as the workspace root.
    local project_dir="${CLAUDE_PROJECT_DIR:-}"

    # Use cwd as fallback if CLAUDE_PROJECT_DIR is not set.
    if [[ -z "$project_dir" ]]; then
        project_dir="$cwd"
    fi

    workspace_roots_json=$(paths_to_json_array "$project_dir")

    local event type command file_path
    case "$tool_name" in
        Read|Edit|MultiEdit|NotebookEdit)
            # Non-Bash file tools: the target path lives at tool_input.file_path
            # for Read/Edit/MultiEdit, and tool_input.notebook_path for NotebookEdit.
            file_path=$(extract_json_string "$raw_payload" "file_path")
            if [[ -z "$file_path" ]]; then
                file_path=$(extract_json_string "$raw_payload" "notebook_path")
            fi
            command=""
            event="before_file_read"
            type="file_read"
            ;;
        *)
            # Bash (and any other/unrecognized tool_name): preserve the original
            # behavior of extracting a shell command.
            command=$(extract_json_string "$raw_payload" "command")
            file_path=""
            event="before_shell_execution"
            type="command"
            ;;
    esac

    build_canonical_input \
        "claude-code" \
        "$event" \
        "$type" \
        "$workspace_roots_json" \
        "$cwd" \
        "$command" \
        "$tool_name" \
        "$raw_payload" \
        "$file_path"
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
