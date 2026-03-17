# Shared JSON utilities for agent-hooks.
# Source this file; it defines functions only and has no side effects.
#
# Pure-bash JSON helpers that avoid a hard dependency on jq.

[[ -n "${_LIB_JSON_LOADED:-}" ]] && return 0
_LIB_JSON_LOADED=1

_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_LIB_DIR}/logging.sh"

# Escape JSON string value (returns escaped string without quotes)
escape_json_string() {
    local str="$1"
    str="${str//\\/\\\\}"
    str="${str//\"/\\\"}"
    str="${str//$'\n'/\\n}"
    str="${str//$'\r'/\\r}"
    str="${str//$'\t'/\\t}"
    printf '%s\n' "$str"
}

# Extract the first JSON string field that matches the provided key.
# This is a lightweight helper to avoid adding dependencies like jq.
# Handles escaped characters inside JSON string values (e.g. \", \\).
# Usage: val=$(extract_json_string "$json" "field_name")
extract_json_string() {
    local json="$1"
    local key="$2"
    local value

    # ([^"\\]|\\.)* matches JSON string contents including escaped quotes (\")
    # and escaped backslashes (\\). [^"\\] matches any char except " and \,
    # while \\. matches a backslash followed by any character.
    # printf is used instead of echo to avoid backslash interpretation on macOS.
    value=$(
        printf '%s\n' "$json" | grep -oE "\"${key}\"[[:space:]]*:[[:space:]]*\"([^\"\\\\]|\\\\.)*\"" \
            | head -n 1 \
            | sed -E "s/.*\"${key}\"[[:space:]]*:[[:space:]]*\"(([^\"\\\\]|\\\\.)*)\".*/\1/" || true
    )

    # Unescape JSON string sequences so callers see the decoded value.
    if [[ -n "$value" ]]; then
        value="${value//\\\"/\"}"
        value="${value//\\\\/\\}"
    fi

    printf '%s\n' "$value"
    return 0
}

# Parse JSON input and extract workspace_roots array.
# Returns workspace root paths, one per line.
# Usage: parse_json_workspace_roots "$json"
parse_json_workspace_roots() {
    local json_input="$1"
    if [[ -z "$json_input" ]]; then
        json_input=$(cat)
    fi

    local in_array=false
    local array_lines=""

    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" =~ \"workspace_roots\"[[:space:]]*:[[:space:]]*\[ ]]; then
            in_array=true
            array_lines="${line#*\[}"
            if [[ "$array_lines" =~ \] ]]; then
                array_lines="${array_lines%\]*}"
                break
            fi
        elif [[ "$in_array" == "true" ]]; then
            if [[ "$line" =~ \] ]]; then
                array_lines="${array_lines} ${line%\]*}"
                break
            else
                array_lines="${array_lines} ${line}"
            fi
        fi
    done <<< "$json_input"

    local result=""
    while [[ "$array_lines" =~ \"([^\"]+)\" ]]; do
        [[ -n "${BASH_REMATCH[1]}" ]] && result="${result:+${result}$'\n'}${BASH_REMATCH[1]}"
        array_lines="${array_lines#*"${BASH_REMATCH[0]}"}"
    done
    [[ -n "$result" ]] && echo "$result" || true

    return 0
}

# Check whether a key exists anywhere in a JSON object.
# Usage: json_has_key "$json" "field_name" && echo "exists"
json_has_key() {
    local json="$1"
    local key="$2"
    printf '%s\n' "$json" | grep -qE "\"${key}\"[[:space:]]*:"
}
