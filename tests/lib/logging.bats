#!/usr/bin/env bats

load "../test_helper"

setup() {
    # Reset the source guard so each test gets a clean load
    unset _LIB_LOGGING_LOADED
    source "${LIB_DIR}/logging.sh"
}

# ---------- log to file ----------

@test "log writes to LOG_FILE" {
    local tmpfile
    tmpfile=$(mktemp)

    LOG_FILE="$tmpfile" log "hello from test"

    grep -q "hello from test" "$tmpfile"
    rm -f "$tmpfile"
}

@test "log includes LOG_TAG in output" {
    local tmpfile
    tmpfile=$(mktemp)

    LOG_TAG="my-hook" LOG_FILE="$tmpfile" log "tagged message"

    grep -q "\[my-hook\]" "$tmpfile"
    rm -f "$tmpfile"
}

@test "log uses default tag agent-hooks when LOG_TAG is unset" {
    local tmpfile
    tmpfile=$(mktemp)

    unset LOG_TAG
    LOG_FILE="$tmpfile" log "default tag"

    grep -q "\[agent-hooks\]" "$tmpfile"
    rm -f "$tmpfile"
}

@test "log includes timestamp" {
    local tmpfile
    tmpfile=$(mktemp)

    LOG_FILE="$tmpfile" log "timestamped"

    # Matches [YYYY-MM-DD HH:MM:SS]
    grep -qE "\[[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}\]" "$tmpfile"
    rm -f "$tmpfile"
}

# ---------- DEBUG mode ----------

@test "log writes to stderr when DEBUG=1" {
    run bash -c 'source "'"${LIB_DIR}/logging.sh"'" && DEBUG=1 log "debug msg" 2>&1 1>/dev/null'
    # stderr was redirected to stdout for capture
    [[ "$output" == *"debug msg"* ]]
}

@test "log does not write to file when DEBUG=1" {
    local tmpfile
    tmpfile=$(mktemp)

    DEBUG=1 LOG_FILE="$tmpfile" log "should not appear" 2>/dev/null

    [[ ! -s "$tmpfile" ]]
    rm -f "$tmpfile"
}

# ---------- source guard ----------

@test "source guard prevents double loading" {
    # First load already happened in setup
    [[ "$_LIB_LOGGING_LOADED" == "1" ]]

    # Source again — should be a no-op
    source "${LIB_DIR}/logging.sh"
    [[ "$_LIB_LOGGING_LOADED" == "1" ]]
}

# ---------- log file permissions ----------

# Mirrors the stat idiom already used in lib/telemetry.sh: BSD first, GNU second.
file_mode() {
    stat -f%Lp "$1" 2>/dev/null || stat -c%a "$1" 2>/dev/null
}

@test "log creates a new log file with 0600 permissions" {
    local logfile="${BATS_TEST_TMPDIR}/fresh.log"

    LOG_FILE="$logfile" log "first line"

    [[ -f "$logfile" ]]
    [[ "$(file_mode "$logfile")" == "600" ]]
    grep -q "first line" "$logfile"
}

@test "log appends to an existing file owned by the caller" {
    local logfile="${BATS_TEST_TMPDIR}/existing.log"
    printf 'pre-existing\n' > "$logfile"

    LOG_FILE="$logfile" log "appended line"

    grep -q "pre-existing" "$logfile"
    grep -q "appended line" "$logfile"
}

@test "log does not write through a symlink to a regular file" {
    local target="${BATS_TEST_TMPDIR}/target.txt"
    local link="${BATS_TEST_TMPDIR}/link.log"
    printf 'untouched\n' > "$target"
    ln -s "$target" "$link"

    LOG_FILE="$link" log "must not land here"

    [[ "$(cat "$target")" == "untouched" ]]
}

@test "log does not create a file through a dangling symlink" {
    local target="${BATS_TEST_TMPDIR}/not-yet-there.txt"
    local link="${BATS_TEST_TMPDIR}/dangling.log"
    ln -s "$target" "$link"

    LOG_FILE="$link" log "must not create the target"

    [[ ! -e "$target" ]]
}

@test "log still honours LOG_FILE=/dev/null" {
    # The shared test helper points LOG_FILE at /dev/null to silence logging,
    # so a permissions check that rejected non-regular files would break every
    # other test in the suite.
    LOG_FILE="/dev/null" log "swallowed"
}

@test "log tightens a world-readable log left by an earlier version" {
    local logfile="${BATS_TEST_TMPDIR}/legacy.log"
    printf 'written by an older version\n' > "$logfile"
    chmod 644 "$logfile"

    LOG_FILE="$logfile" log "new line"

    [[ "$(file_mode "$logfile")" == "600" ]]
    grep -q "written by an older version" "$logfile"
    grep -q "new line" "$logfile"
}
