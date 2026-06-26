# Shared telemetry utilities for agent-hooks.
# Source this file; it defines functions only and has no side effects.
#
# Writes JSONL telemetry events to disk for the 1Password app to ingest.
# All functions fail silently — telemetry must never affect hook decisions.

[[ -n "${_LIB_TELEMETRY_LOADED:-}" ]] && return 0
_LIB_TELEMETRY_LOADED=1

_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_LIB_DIR}/logging.sh"
source "${_LIB_DIR}/json.sh"

# Convert raw milliseconds to a bucketed range string.
bucket_duration_ms() {
    local ms="${1:-0}"
    if [[ "$ms" -lt 50 ]]; then echo "ms_0_to_50"
    elif [[ "$ms" -lt 100 ]]; then echo "ms_50_to_100"
    elif [[ "$ms" -lt 200 ]]; then echo "ms_100_to_200"
    elif [[ "$ms" -lt 500 ]]; then echo "ms_200_to_500"
    elif [[ "$ms" -lt 1000 ]]; then echo "ms_500_to_1000"
    elif [[ "$ms" -lt 5000 ]]; then echo "ms_1000_to_5000"
    else echo "ms_5000_plus"
    fi
}

current_time_ms() {
    local now seconds fraction

    if [[ "${EPOCHREALTIME:-}" =~ ^[0-9]+\.[0-9]+$ ]]; then
        seconds="${EPOCHREALTIME%.*}"
        fraction="${EPOCHREALTIME#*.}000"
        echo "${seconds}${fraction:0:3}"
        return 0
    fi

    now=$(date +%s%3N 2>/dev/null || true)
    if [[ "$now" =~ ^[0-9]+$ ]]; then
        echo "$now"
        return 0
    fi

    now=$(perl -MTime::HiRes=time -e 'printf "%.0f\n", time() * 1000' 2>/dev/null || true)
    if [[ "$now" =~ ^[0-9]+$ ]]; then
        echo "$now"
        return 0
    fi

    now=$(python3 -c 'import time; print(int(time.time() * 1000))' 2>/dev/null || true)
    if [[ "$now" =~ ^[0-9]+$ ]]; then
        echo "$now"
        return 0
    fi

    echo "$(($(date +%s) * 1000))"
}

get_telemetry_dir() {
    echo "${HOME}/.config/1Password/data/hook-events"
}

# Emit the `,"ts":<epoch_ms>` JSON fragment stamping when the event was
# produced, or an empty string if the clock is unreadable. Guarded so a non-numeric clock never yields a malformed
# line.
ts_json_fragment() {
    local ts
    ts=$(current_time_ms)
    if [[ "$ts" =~ ^[0-9]+$ ]]; then
        printf ',"ts":%s' "$ts"
    fi
}

# Check whether the 1Password app has signaled that telemetry is enabled.
# Returns 0 (true) if the signal file exists, 1 (false) otherwise.
telemetry_consent_enabled() {
    [[ -f "${HOME}/.config/1Password/telemetry-enabled" ]]
}

# Append a single JSON line to the events.jsonl file.
# Checks consent and enforces a 1MB file size cap (drop-newest).
write_telemetry_event() {
    local json_line="$1"
    local event_dir
    event_dir=$(get_telemetry_dir)

    if ! telemetry_consent_enabled; then
        return 0
    fi

    mkdir -p "$event_dir" 2>/dev/null || return 0

    local event_file="${event_dir}/events.jsonl"

    # 1MB file size cap
    if [[ -f "$event_file" ]]; then
        local file_size
        file_size=$(stat -f%z "$event_file" 2>/dev/null || stat -c%s "$event_file" 2>/dev/null || echo "0")
        if [[ "$file_size" -gt 1048576 ]]; then
            log "Telemetry file exceeds 1MB, skipping write"
            return 0
        fi
    fi

    printf '%s\n' "$json_line" >> "$event_file" 2>/dev/null || true
}

# Write an agent_hook_execution telemetry event.
# `mode` and `mount_count` are hook-specific and may be empty for hooks that
# do not have a meaningful value to populate them; in that case they are
# serialized as JSON null per the schema.
write_execution_event() {
    local hook_name="$1"
    local hook_version="$2"
    local client="$3"
    local event_type="$4"
    local decision="$5"
    local deny_reason="$6"
    local duration_ms="$7"
    local mode="$8"
    local mount_count="$9"

    local escaped_hook_name escaped_hook_version escaped_client escaped_event_type
    escaped_hook_name=$(escape_json_string "$hook_name")
    escaped_hook_version=$(escape_json_string "$hook_version")
    escaped_client=$(escape_json_string "$client")
    escaped_event_type=$(escape_json_string "$event_type")

    local deny_reason_json
    if [[ -z "$deny_reason" ]]; then
        deny_reason_json="null"
    else
        local escaped_deny_reason
        escaped_deny_reason=$(escape_json_string "$deny_reason")
        deny_reason_json="\"${escaped_deny_reason}\""
    fi

    local mode_json
    if [[ -z "$mode" ]]; then
        mode_json="null"
    else
        local escaped_mode
        escaped_mode=$(escape_json_string "$mode")
        mode_json="\"${escaped_mode}\""
    fi

    local mount_count_json
    if [[ -z "$mount_count" ]]; then
        mount_count_json="null"
    else
        mount_count_json="$mount_count"
    fi


    local duration_bucket
    duration_bucket=$(bucket_duration_ms "$duration_ms")

    local ts_field
    ts_field=$(ts_json_fragment)

    local json_line
    json_line="{\"schema\":\"agent_hook_execution\",\"hook_name\":\"${escaped_hook_name}\",\"hook_version\":\"${escaped_hook_version}\",\"client\":\"${escaped_client}\",\"event_type\":\"${escaped_event_type}\",\"decision\":\"${decision}\",\"deny_reason\":${deny_reason_json},\"duration_bucket\":\"${duration_bucket}\",\"mode\":${mode_json},\"mount_count\":${mount_count_json}${ts_field}}"

    write_telemetry_event "$json_line"
}

# Write an agent_hook_install telemetry event.
write_install_event() {
    local client="$1"
    local hook_name="$2"
    local hook_version="$3"
    local install_method="$4"

    local escaped_client escaped_hook_name escaped_hook_version
    escaped_client=$(escape_json_string "$client")
    escaped_hook_name=$(escape_json_string "$hook_name")
    escaped_hook_version=$(escape_json_string "$hook_version")

    local ts_field
    ts_field=$(ts_json_fragment)

    local json_line
    json_line="{\"schema\":\"agent_hook_install\",\"client\":\"${escaped_client}\",\"hook_name\":\"${escaped_hook_name}\",\"hook_version\":\"${escaped_hook_version}\",\"install_method\":\"${install_method}\"${ts_field}}"

    write_telemetry_event "$json_line"
}

# Emit an `agent_hook_install` event with install_method=manual exactly once
# per (client, hook_name, hook_version). Intended for `bin/run-hook.sh` only —
# without the sentinel, the bundle being run from a manually-copied location
# would emit an install event on every hook invocation.
#
# All other install paths (install.sh, plugin marketplaces) call
# write_install_event directly.
emit_manual_install_event_once() {
    local client="$1"
    local hook_name="$2"
    local hook_version="$3"
    local event_dir
    event_dir=$(get_telemetry_dir)

    if ! telemetry_consent_enabled; then
        return 0
    fi

    mkdir -p "$event_dir" 2>/dev/null || return 0

    local sentinel="${event_dir}/.installed-${client}-${hook_name}-${hook_version}-manual"
    if [[ ! -f "$sentinel" ]]; then
        write_install_event "$client" "$hook_name" "$hook_version" "manual"
        touch "$sentinel" 2>/dev/null || true
    fi
}

# Detect how the hook was deployed by this repo's distribution paths.
# Pass the caller's SCRIPT_DIR as the argument.
#
# Returns:
#   install_script — bundle directory matches the layout produced by install.sh
#   manual         — bundle was placed manually (e.g. `cp -r`, custom symlink,
#                    `git clone` + direct IDE config)
#
# Plugin marketplace distributions (Cursor, Claude Code, etc.) are NOT
# detected here. Each plugin repo is responsible for emitting its own
# `agent_hook_install` event with its specific install_method value at
# install/activation time.
detect_install_method() {
    local caller_dir="${1:-}"

    if [[ -n "$caller_dir" ]] && [[ "$caller_dir" == *"-1password-hooks-bundle"* ]]; then
        echo "install_script"
        return 0
    fi

    echo "manual"
}
