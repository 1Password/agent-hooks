# Shared logging utilities for agent-hooks.
# Source this file; it defines functions only.
#
# Environment variables:
#   DEBUG       — set to "1" to echo logs to stderr instead of the log file
#   LOG_FILE    — override the default log file path
#   LOG_TAG     — override the default log tag (default: "agent-hooks")

[[ -n "${_LIB_LOGGING_LOADED:-}" ]] && return 0
_LIB_LOGGING_LOADED=1

log() {
    local timestamp
    timestamp=$(date +"%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "$(date +%s)")
    local tag="${LOG_TAG:-agent-hooks}"
    local log_message="[${timestamp}] [${tag}] $*"

    if [[ "${DEBUG:-}" == "1" ]]; then
        echo "$log_message" >&2
    else
        local log_file="${LOG_FILE:-/tmp/1password-hooks.log}"
        echo "$log_message" >> "$log_file" 2>/dev/null || true
    fi
}
