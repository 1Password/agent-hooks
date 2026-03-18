# Shared path utilities for agent-hooks.
# Source this file; it defines functions only and has no side effects.

[[ -n "${_LIB_PATHS_LOADED:-}" ]] && return 0
_LIB_PATHS_LOADED=1

_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_LIB_DIR}/logging.sh"

# Validate a path string to prevent command injection.
# Returns 0 if the path is safe to use with cd/cat/etc, 1 if unsafe.
validate_path() {
    local path="$1"

    [[ -z "$path" ]] && return 1

    # Command substitution patterns
    if [[ "$path" =~ \$\( ]] || [[ "$path" =~ \$\{ ]]; then
        return 1
    fi

    # Backtick command substitution
    if [[ "$path" =~ \` ]]; then
        return 1
    fi

    # Shell metacharacters
    if [[ "$path" =~ [\;\|\&\<\>] ]]; then
        return 1
    fi

    # Check for control characters that could break commands
    # Remove all printable characters; if anything remains, there are control chars
    local non_printable
    non_printable=$(printf '%s' "$path" | tr -d '[:print:]' 2>/dev/null || echo "")
    if [[ -n "$non_printable" ]]; then
        return 1
    fi

    return 0
}

# Resolve a path to its canonical form (resolves symlinks, . and ..).
# Falls back to returning the path as-is when resolution is not possible.
normalize_path() {
    local path="$1"
    local normalized normalized_dir file_part dir_part

    # Validate path before using it with cd to prevent command injection
    if ! validate_path "$path"; then
        log "Warning: Unsafe path detected, skipping normalization: ${path}"
        echo "$path"
        return 0
    fi

    if [[ -d "$path" ]]; then
        normalized=$(cd "$path" && pwd 2>/dev/null)
        if [[ -n "$normalized" ]]; then
            echo "$normalized"
            return 0
        fi
    elif [[ -f "$path" ]] || [[ -p "$path" ]]; then
        # For files/FIFOs, resolve the directory part
        dir_part=$(dirname "$path")
        file_part=$(basename "$path")

        # Validate dir_part before using with cd
        if validate_path "$dir_part" && [[ -d "$dir_part" ]]; then
            normalized_dir=$(cd "$dir_part" && pwd 2>/dev/null)
            if [[ -n "$normalized_dir" ]]; then
                echo "${normalized_dir}/${file_part}"
                return 0
            fi
        fi
    else
        # Attempt to normalize non-existent paths (e.g., with .. components)
        dir_part=$(dirname "$path")
        file_part=$(basename "$path")

        if validate_path "$dir_part" && [[ -d "$dir_part" ]]; then
            normalized_dir=$(cd "$dir_part" && pwd 2>/dev/null)
            if [[ -n "$normalized_dir" ]]; then
                echo "${normalized_dir}/${file_part}"
                return 0
            fi
        fi
    fi

    # Last resort: return path as-is
    echo "$path"
}
