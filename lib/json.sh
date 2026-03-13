# Shared JSON utilities for ide-hooks.
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
    str=$(echo "$str" | sed 's/\\/\\\\/g')
    str=$(echo "$str" | sed 's/"/\\"/g')
    str=$(echo "$str" | sed 's/\n/\\n/g')
    str=$(echo "$str" | sed 's/\r/\\r/g')
    str=$(echo "$str" | sed 's/\t/\\t/g')
    echo "$str"
}

# Extract the first JSON string field that matches the provided key.
# This is a lightweight helper to avoid adding dependencies like jq.
# Usage: val=$(extract_json_string "$json" "field_name")
extract_json_string() {
    local json="$1"
    local key="$2"
    local value

    value=$(
        echo "$json" | grep -oE "\"${key}\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" \
            | head -n 1 \
            | sed -E "s/.*\"${key}\"[[:space:]]*:[[:space:]]*\"([^\"]*)\".*/\1/" || true
    )

    echo "$value"
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
        if echo "$line" | grep -qE '"workspace_roots"[[:space:]]*:[[:space:]]*\['; then
            in_array=true
            array_lines="${line#*\[}"
            if echo "$array_lines" | grep -qE '\]'; then
                array_lines="${array_lines%\]*}"
                break
            fi
        elif [[ "$in_array" == "true" ]]; then
            if echo "$line" | grep -qE '\]'; then
                array_lines="${array_lines} ${line%\]*}"
                break
            else
                array_lines="${array_lines} ${line}"
            fi
        fi
    done <<< "$json_input"

    echo "$array_lines" | grep -oE '"[^"]+"' \
        | sed 's/^"//;s/"$//' \
        | sed '/^$/d' || true

    return 0
}

# Check whether a top-level key exists in a JSON object.
# Usage: json_has_key "$json" "field_name" && echo "exists"
json_has_key() {
    local json="$1"
    local key="$2"
    echo "$json" | grep -qE "\"${key}\"[[:space:]]*:"
}
