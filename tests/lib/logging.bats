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

@test "log uses default tag ide-hooks when LOG_TAG is unset" {
    local tmpfile
    tmpfile=$(mktemp)

    unset LOG_TAG
    LOG_FILE="$tmpfile" log "default tag"

    grep -q "\[ide-hooks\]" "$tmpfile"
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
