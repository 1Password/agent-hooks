#!/usr/bin/env bats

load "../test_helper"

setup() {
    unset _LIB_TELEMETRY_LOADED _LIB_JSON_LOADED _LIB_LOGGING_LOADED _LIB_OS_LOADED

    # Use a temp HOME so we don't touch real config
    export ORIGINAL_HOME="$HOME"
    export HOME="${BATS_TEST_TMPDIR}/home"
    mkdir -p "$HOME"

    source "${LIB_DIR}/telemetry.sh"
}

teardown() {
    export HOME="$ORIGINAL_HOME"
}

# Helper: create the consent signal file
create_consent_signal() {
    mkdir -p "${HOME}/.config/1Password"
    touch "${HOME}/.config/1Password/telemetry-enabled"
}

# ========== bucket_duration_ms ==========

@test "bucket_duration_ms: 0 returns ms_0_to_50" {
    run bucket_duration_ms 0
    [[ "$output" == "ms_0_to_50" ]]
}

@test "bucket_duration_ms: 49 returns ms_0_to_50" {
    run bucket_duration_ms 49
    [[ "$output" == "ms_0_to_50" ]]
}

@test "bucket_duration_ms: 50 returns ms_50_to_100" {
    run bucket_duration_ms 50
    [[ "$output" == "ms_50_to_100" ]]
}

@test "bucket_duration_ms: 99 returns ms_50_to_100" {
    run bucket_duration_ms 99
    [[ "$output" == "ms_50_to_100" ]]
}

@test "bucket_duration_ms: 100 returns ms_100_to_200" {
    run bucket_duration_ms 100
    [[ "$output" == "ms_100_to_200" ]]
}

@test "bucket_duration_ms: 500 returns ms_500_to_1000" {
    run bucket_duration_ms 500
    [[ "$output" == "ms_500_to_1000" ]]
}

@test "bucket_duration_ms: 1000 returns ms_1000_to_5000" {
    run bucket_duration_ms 1000
    [[ "$output" == "ms_1000_to_5000" ]]
}

@test "bucket_duration_ms: 5000 returns ms_5000_plus" {
    run bucket_duration_ms 5000
    [[ "$output" == "ms_5000_plus" ]]
}

@test "bucket_duration_ms: 10000 returns ms_5000_plus" {
    run bucket_duration_ms 10000
    [[ "$output" == "ms_5000_plus" ]]
}

@test "bucket_duration_ms: empty input returns ms_0_to_50" {
    run bucket_duration_ms ""
    [[ "$output" == "ms_0_to_50" ]]
}

# ========== telemetry_consent_enabled ==========

@test "telemetry_consent_enabled: returns false when signal file absent" {
    run telemetry_consent_enabled
    [[ "$status" -ne 0 ]]
}

@test "telemetry_consent_enabled: returns true when signal file present" {
    create_consent_signal
    run telemetry_consent_enabled
    [[ "$status" -eq 0 ]]
}

# ========== write_telemetry_event ==========

@test "write_telemetry_event: writes a line to events.jsonl" {
    create_consent_signal
    write_telemetry_event '{"test":"value"}'
    local event_file
    event_file="$(get_telemetry_dir)/events.jsonl"
    [[ -f "$event_file" ]]
    [[ "$(cat "$event_file")" == '{"test":"value"}' ]]
}

@test "write_telemetry_event: no-op when consent absent" {
    write_telemetry_event '{"test":"value"}'
    local event_file
    event_file="$(get_telemetry_dir)/events.jsonl"
    [[ ! -f "$event_file" ]]
}

@test "write_telemetry_event: creates directory if missing" {
    create_consent_signal
    local event_dir
    event_dir="$(get_telemetry_dir)"
    [[ ! -d "$event_dir" ]]
    write_telemetry_event '{"test":"value"}'
    [[ -d "$event_dir" ]]
}

@test "write_telemetry_event: respects 1MB cap" {
    create_consent_signal
    local event_dir
    event_dir="$(get_telemetry_dir)"
    mkdir -p "$event_dir"
    local event_file="${event_dir}/events.jsonl"
    # Create a file just over 1MB
    dd if=/dev/zero of="$event_file" bs=1048577 count=1 2>/dev/null
    write_telemetry_event '{"should":"not appear"}'
    # File is at the cap, so the new line is skipped (drop-newest) — never
    # rewritten — leaving the existing contents untouched.
    ! grep -q "should" "$event_file"
}

@test "write_telemetry_event: appends multiple lines" {
    create_consent_signal
    write_telemetry_event '{"line":1}'
    write_telemetry_event '{"line":2}'
    write_telemetry_event '{"line":3}'
    local event_file
    event_file="$(get_telemetry_dir)/events.jsonl"
    local count
    count=$(wc -l < "$event_file" | tr -d ' ')
    [[ "$count" -eq 3 ]]
}

# ========== write_execution_event ==========

@test "write_execution_event: correct JSON structure" {
    create_consent_signal
    write_execution_event \
        "validate_mounted_env_files" \
        "0.1.0" \
        "cursor" \
        "before_shell_execution" \
        "allow" \
        "" \
        "42" \
        "configured" \
        "3"
    local event_file
    event_file="$(get_telemetry_dir)/events.jsonl"
    local line
    line=$(cat "$event_file")
    [[ "$line" == *'"schema":"agent_hook_execution"'* ]]
    [[ "$line" == *'"hook_name":"validate_mounted_env_files"'* ]]
    [[ "$line" == *'"hook_version":"0.1.0"'* ]]
    [[ "$line" == *'"client":"cursor"'* ]]
    [[ "$line" == *'"decision":"allow"'* ]]
    [[ "$line" == *'"deny_reason":null'* ]]
    [[ "$line" == *'"duration_bucket":"ms_0_to_50"'* ]]
    [[ "$line" != *'"duration_ms"'* ]]
    [[ "$line" == *'"mode":"configured"'* ]]
    [[ "$line" == *'"mount_count":3'* ]]
    # ts stamps when the hook fired; OPH maps it to the Snowplow device-created
    # timestamp. Must be an unquoted integer so it parses as a JSON number.
    [[ "$line" =~ \"ts\":[0-9]+ ]]
    [[ "$line" != *'"ts":"'* ]]
}

@test "write_execution_event: deny_reason is set when provided" {
    create_consent_signal
    write_execution_event \
        "validate_mounted_env_files" \
        "0.1.0" \
        "cursor" \
        "before_shell_execution" \
        "deny" \
        "file_missing" \
        "1234" \
        "default" \
        "1"
    local event_file
    event_file="$(get_telemetry_dir)/events.jsonl"
    local line
    line=$(cat "$event_file")
    [[ "$line" == *'"deny_reason":"file_missing"'* ]]
    [[ "$line" == *'"decision":"deny"'* ]]
    [[ "$line" == *'"duration_bucket":"ms_1000_to_5000"'* ]]
    [[ "$line" != *'"duration_ms"'* ]]
}

@test "write_execution_event: empty mode and mount_count serialize as JSON null" {
    create_consent_signal
    write_execution_event \
        "before_shell_execution" \
        "1.0.0" \
        "cursor" \
        "before_shell_execution" \
        "allow" \
        "" \
        "42" \
        "" \
        ""
    local event_file
    event_file="$(get_telemetry_dir)/events.jsonl"
    local line
    line=$(cat "$event_file")
    [[ "$line" == *'"mode":null'* ]]
    [[ "$line" == *'"mount_count":null'* ]]
    # JSON must still be parseable
    if command -v python3 >/dev/null 2>&1; then
        echo "$line" | python3 -c 'import sys, json; json.loads(sys.stdin.read())'
    fi
}

@test "write_execution_event: accepts any deny_reason string (free-form per schema)" {
    create_consent_signal
    # The schema relaxed deny_reason from a closed enum to a free-form string
    # so new denial reasons (policy_violation, timeout, etc.) do not require
    # a schema bump. The writer must just escape and forward the value.
    write_execution_event \
        "before_shell_execution" \
        "1.0.0" \
        "cursor" \
        "before_shell_execution" \
        "deny" \
        "policy_violation" \
        "100" \
        "" \
        ""
    local line
    line=$(cat "$(get_telemetry_dir)/events.jsonl")
    [[ "$line" == *'"deny_reason":"policy_violation"'* ]]
}

@test "write_execution_event: deny_reason is JSON-escaped" {
    create_consent_signal
    # Inject a value containing characters that would break JSON if unescaped.
    # The schema currently only allows enum values, but defense-in-depth says
    # the writer must always produce valid JSON regardless of upstream input.
    write_execution_event \
        "validate_mounted_env_files" \
        "0.1.0" \
        "cursor" \
        "before_shell_execution" \
        "deny" \
        'bad"value\with' \
        "1234" \
        "default" \
        "1"
    local event_file
    event_file="$(get_telemetry_dir)/events.jsonl"
    local line
    line=$(cat "$event_file")
    # Escaped quote and backslash should be present
    [[ "$line" == *'"deny_reason":"bad\"value\\with"'* ]]
    # Raw unescaped form must not appear
    [[ "$line" != *'"deny_reason":"bad"value\with"'* ]]
    # JSON must still be parseable (validate via python if available)
    if command -v python3 >/dev/null 2>&1; then
        echo "$line" | python3 -c 'import sys, json; json.loads(sys.stdin.read())'
    fi
}

# ========== write_install_event ==========

@test "write_install_event: correct JSON structure" {
    create_consent_signal
    write_install_event "cursor" "validate_mounted_env_files" "1.0.0" "install_script"
    local event_file
    event_file="$(get_telemetry_dir)/events.jsonl"
    local line
    line=$(cat "$event_file")
    [[ "$line" == *'"schema":"agent_hook_install"'* ]]
    [[ "$line" == *'"client":"cursor"'* ]]
    [[ "$line" == *'"hook_name":"validate_mounted_env_files"'* ]]
    [[ "$line" == *'"hook_version":"1.0.0"'* ]]
    [[ "$line" == *'"install_method":"install_script"'* ]]
    [[ "$line" =~ \"ts\":[0-9]+ ]]
    [[ "$line" != *'"ts":"'* ]]
    # JSON must be parseable with the ts field present.
    if command -v python3 >/dev/null 2>&1; then
        echo "$line" | python3 -c 'import sys, json; json.loads(sys.stdin.read())'
    fi
}

# ========== emit_manual_install_event_once ==========

@test "emit_manual_install_event_once: writes a manual install event and sentinel" {
    create_consent_signal
    emit_manual_install_event_once "cursor" "validate_mounted_env_files" "1.0.0"
    local event_dir
    event_dir="$(get_telemetry_dir)"
    [[ -f "${event_dir}/.installed-cursor-validate_mounted_env_files-1.0.0-manual" ]]
    local line
    line=$(cat "${event_dir}/events.jsonl")
    [[ "$line" == *'"schema":"agent_hook_install"'* ]]
    [[ "$line" == *'"install_method":"manual"'* ]]
    [[ "$line" == *'"hook_version":"1.0.0"'* ]]
}

@test "emit_manual_install_event_once: no-op on second call (sentinel present)" {
    create_consent_signal
    emit_manual_install_event_once "cursor" "validate_mounted_env_files" "1.0.0"
    local event_file
    event_file="$(get_telemetry_dir)/events.jsonl"
    local count_before
    count_before=$(wc -l < "$event_file" | tr -d ' ')
    emit_manual_install_event_once "cursor" "validate_mounted_env_files" "1.0.0"
    local count_after
    count_after=$(wc -l < "$event_file" | tr -d ' ')
    [[ "$count_before" -eq "$count_after" ]]
}

@test "emit_manual_install_event_once: no-op when consent absent" {
    emit_manual_install_event_once "cursor" "validate_mounted_env_files" "1.0.0"
    local event_dir
    event_dir="$(get_telemetry_dir)"
    [[ ! -f "${event_dir}/.installed-cursor-validate_mounted_env_files-1.0.0-manual" ]]
    [[ ! -f "${event_dir}/events.jsonl" ]]
}

@test "emit_manual_install_event_once: keyed by (client, hook_name, hook_version) — independent dedupe" {
    create_consent_signal
    emit_manual_install_event_once "cursor" "validate_mounted_env_files" "1.0.0"
    emit_manual_install_event_once "claude_code" "validate_mounted_env_files" "1.0.0"
    emit_manual_install_event_once "cursor" "validate_mounted_env_files" "1.0.0"
    local count
    count=$(wc -l < "$(get_telemetry_dir)/events.jsonl" | tr -d ' ')
    # Three calls: two distinct triples → 2 events. The third call repeats
    # the first triple and is deduped.
    [[ "$count" -eq 2 ]]
}

@test "emit_manual_install_event_once: hook_version bump produces a new event" {
    create_consent_signal
    emit_manual_install_event_once "cursor" "validate_mounted_env_files" "1.0.0"
    emit_manual_install_event_once "cursor" "validate_mounted_env_files" "1.1.0"
    local count
    count=$(wc -l < "$(get_telemetry_dir)/events.jsonl" | tr -d ' ')
    # Same (client, hook_name) but distinct versions → 2 events. This is how
    # upgrades to a manually-copied bundle become observable.
    [[ "$count" -eq 2 ]]
}

# ========== detect_install_method ==========

@test "detect_install_method: returns install_script when path contains bundle marker" {
    run detect_install_method "/project/.cursor/cursor-1password-hooks-bundle/bin"
    [[ "$output" == "install_script" ]]
}

@test "detect_install_method: returns manual for manually-copied bundles" {
    run detect_install_method "/some/random/dir"
    [[ "$output" == "manual" ]]
}

@test "detect_install_method: returns manual when caller_dir is empty" {
    run detect_install_method ""
    [[ "$output" == "manual" ]]
}
