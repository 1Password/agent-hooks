# Shared logging utilities for agent-hooks.
# Source this file; it defines functions only.
#
# Environment variables:
#   DEBUG       — set to "1" to echo logs to stderr instead of the log file
#   LOG_FILE    — override the default log file path
#   LOG_TAG     — override the default log tag (default: "agent-hooks")
#
# The default log path lives in /tmp, which is world-writable, so the log file
# is created with 0600 and a path that is unsafe to append to is skipped rather
# than written. See _log_file_is_writable below.

[[ -n "${_LIB_LOGGING_LOADED:-}" ]] && return 0
_LIB_LOGGING_LOADED=1

# Decide whether it is safe to append to the log path, creating the file with
# restrictive permissions when it does not exist yet.
#
# Two hazards follow from the default path being a fixed name in a
# world-writable directory:
#
#   - A file created by a plain append inherits the process umask. Under the
#     common default of 022 that is mode 0644, so every local user can read the
#     environment names and .env paths the hooks log.
#   - An attacker who knows the fixed path can pre-create it as a symlink, and
#     the append then lands on a file of their choosing, written with the
#     privileges of whoever ran the hook.
#
# Returns non-zero when the path is not safe to write. log() then skips the
# write silently, because logging must never affect a hook decision.
_log_file_is_writable() {
    local log_file="$1"

    if [[ -L "$log_file" ]]; then
        # A symlink to a character device or pipe (/dev/stdout, /dev/stderr) is
        # a deliberate choice by the caller and is honoured. A symlink to a
        # regular file — or to a path that does not exist yet — is the
        # redirection hazard described above.
        [[ -c "$log_file" || -p "$log_file" ]] || return 1
        return 0
    fi

    if [[ -e "$log_file" ]]; then
        # Not a regular file (/dev/null, a fifo): left exactly as it is.
        [[ -f "$log_file" ]] || return 0
        # A regular file owned by somebody else is not ours to append to.
        [[ -O "$log_file" ]] || return 1
        # A log written by an earlier version is still world-readable, so
        # tighten it rather than appending to it as it stands. chmod on a file
        # that is already 0600 is a single cheap syscall, and a failure here is
        # not fatal — the file is ours either way.
        chmod 600 "$log_file" 2>/dev/null || true
        return 0
    fi

    # Create it before the first append so it is never briefly world-readable.
    ( umask 077 && : >> "$log_file" ) 2>/dev/null || return 1
}

log() {
    local timestamp
    timestamp=$(date +"%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "$(date +%s)")
    local tag="${LOG_TAG:-agent-hooks}"
    local log_message="[${timestamp}] [${tag}] $*"

    if [[ "${DEBUG:-}" == "1" ]]; then
        echo "$log_message" >&2
    else
        local log_file="${LOG_FILE:-/tmp/1password-hooks.log}"
        _log_file_is_writable "$log_file" || return 0
        echo "$log_message" >> "$log_file" 2>/dev/null || true
    fi
}
