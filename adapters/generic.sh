# Generic fallback adapter for unknown IDEs.
# Implements: normalize_input, emit_output
#
# Selected when detect_client() returns "unknown".
# Uses best-effort extraction: tries workspace_roots, falls back to cwd.
# Output: exit 0 for allow, exit 1 + stderr for deny.

[[ -n "${_ADAPTER_GENERIC_LOADED:-}" ]] && return 0
_ADAPTER_GENERIC_LOADED=1

_ADAPTER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_ADAPTER_DIR}/_lib.sh"

normalize_input() {
    local raw_payload="$1"

    local cwd command workspace_roots workspace_roots_json
    cwd=$(extract_json_string "$raw_payload" "cwd")
    command=$(extract_json_string "$raw_payload" "command")

    # Try workspace_roots array first, fall back to cwd
    workspace_roots=$(parse_json_workspace_roots "$raw_payload")
    if [[ -z "$workspace_roots" ]] && [[ -n "$cwd" ]]; then
        workspace_roots="$cwd"
    fi
    workspace_roots_json=$(paths_to_json_array "$workspace_roots")

    build_canonical_input \
        "unknown" \
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
        echo "$message" >&2
        return 1
    fi

    return 0
}
