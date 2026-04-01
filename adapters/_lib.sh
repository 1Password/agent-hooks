# Shared adapter utilities for agent-hooks.
# Source this file; it defines functions only and has no side effects.
#
# Each adapter must implement two functions:
#   normalize_input "$raw_payload"  — print canonical JSON to stdout
#   emit_output "$canonical_output" — print IDE-native response, set exit code
#
# Client detection is centralized in detect_client() below.

[[ -n "${_ADAPTERS_LIB_LOADED:-}" ]] && return 0
_ADAPTERS_LIB_LOADED=1

_ADAPTERS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_ADAPTERS_DIR}/../lib/json.sh"

# Detect which agentic client invoked the hook.
# Uses env vars and payload fields in most-specific-first order to avoid
# ambiguity (e.g. Cursor sets CLAUDE_PROJECT_DIR as a compatibility alias).
#
# Signals per client (from official docs):
#   Cursor:         CURSOR_VERSION env var; `cursor_version` payload field
#   Windsurf:       `agent_action_name` payload field (Cascade hooks)
#   GitHub Copilot: `hook_event_name` payload field (after Cursor and
#                   Windsurf are ruled out)
#
#
# Usage: detected=$(detect_client "$raw_payload")
detect_client() {
    local raw_payload="$1"

    # 1. Cursor — CURSOR_VERSION is always set by Cursor and never by others.
    #    cursor_version is present in every Cursor hook payload.
    if [[ -n "${CURSOR_VERSION:-}" ]] || json_has_key "$raw_payload" "cursor_version"; then
        echo "cursor"
        return 0
    fi

    # 2. Claude Code — CLAUDE_PROJECT_DIR env var is set by Claude Code.
    #    Cursor also sets it as a compatibility alias, but Cursor is already
    #    ruled out above. `permission_mode` payload field is unique to Claude Code.
    if [[ -n "${CLAUDE_PROJECT_DIR:-}" ]] || json_has_key "$raw_payload" "permission_mode"; then
        echo "claude-code"
        return 0
    fi

    # 3. Windsurf (Cascade) — every hook payload includes `agent_action_name`.
    #    Checked before Copilot so we do not confuse
    #    Cascade with other clients that may add `hook_event_name` later.
    if json_has_key "$raw_payload" "agent_action_name"; then
        echo "windsurf"
        return 0
    fi

    # 3. GitHub Copilot (VS Code) — shares `hook_event_name` with Cursor.
    #    By this point Cursor and Windsurf are already ruled out, so the presence of
    #    hook_event_name means Copilot.
    if json_has_key "$raw_payload" "hook_event_name"; then
        echo "github-copilot"
        return 0
    fi

    echo "unknown"
    return 0
}

# Build canonical JSON from extracted fields.
# Embeds raw_payload as a nested JSON object.
# Usage: build_canonical_input "$ide" "$event" "$type" "$workspace_roots_json_array" "$cwd" "$command" "$tool_name" "$raw_payload"
build_canonical_input() {
    local client="$1"
    local event="$2"
    local type="$3"
    local workspace_roots_json_array="$4"
    local cwd="$5"
    local command="$6"
    local tool_name="$7"
    local raw_payload="$8"

    local escaped_client escaped_event escaped_type
    escaped_client=$(escape_json_string "$client")
    escaped_event=$(escape_json_string "$event")
    escaped_type=$(escape_json_string "$type")

    local escaped_cwd escaped_command escaped_tool_name
    escaped_cwd=$(escape_json_string "$cwd")
    escaped_command=$(escape_json_string "$command")
    escaped_tool_name=$(escape_json_string "$tool_name")

    local trimmed_payload
    trimmed_payload=$(printf '%s' "$raw_payload" | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
    if [[ -z "$trimmed_payload" ]] || [[ "${trimmed_payload:0:1}" != "{" ]] || [[ "${trimmed_payload: -1}" != "}" ]]; then
        trimmed_payload="{}"
    fi

    # Multi-line output so that line-by-line JSON parsers (parse_json_workspace_roots)
    # can match top-level fields without colliding with keys inside raw_payload.
    cat <<CANONICAL_EOF
{
"client": "${escaped_client}",
"event": "${escaped_event}",
"type": "${escaped_type}",
"workspace_roots": ${workspace_roots_json_array},
"cwd": "${escaped_cwd}",
"command": "${escaped_command}",
"tool_name": "${escaped_tool_name}",
"raw_payload": ${trimmed_payload}
}
CANONICAL_EOF
}

# Convert a newline-separated list of paths into a JSON array string.
# Usage: paths_to_json_array "$paths_newline_separated"
# Output: ["/path/a","/path/b"]
paths_to_json_array() {
    local paths="$1"
    if [[ -z "$paths" ]]; then
        echo "[]"
        return 0
    fi

    local result="["
    local first=true
    while IFS= read -r p || [[ -n "$p" ]]; do
        [[ -z "$p" ]] && continue
        local escaped
        escaped=$(escape_json_string "$p")
        if [[ "$first" == "true" ]]; then
            result="${result}\"${escaped}\""
            first=false
        else
            result="${result},\"${escaped}\""
        fi
    done <<< "$paths"
    result="${result}]"

    echo "$result"
}

# Extract decision from canonical output JSON.
# Usage: get_decision "$canonical_output"
get_decision() {
    extract_json_string "$1" "decision"
}

# Extract message from canonical output JSON.
# Usage: get_message "$canonical_output"
get_message() {
    extract_json_string "$1" "message"
}
