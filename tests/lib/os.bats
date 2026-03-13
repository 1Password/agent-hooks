#!/usr/bin/env bats

load "../test_helper"

setup() {
    unset _LIB_OS_LOADED _LIB_LOGGING_LOADED
    source "${LIB_DIR}/os.sh"
}

@test "detect_os returns macos or unix on supported platforms" {
    run detect_os
    [[ "$status" -eq 0 ]]
    [[ "$output" == "macos" ]] || [[ "$output" == "unix" ]]
}

@test "detect_os returns a non-empty string" {
    run detect_os
    [[ -n "$output" ]]
}

@test "detect_os is consistent across calls" {
    local first second
    first=$(detect_os)
    second=$(detect_os)
    [[ "$first" == "$second" ]]
}

@test "source guard prevents double loading" {
    [[ "$_LIB_OS_LOADED" == "1" ]]
    source "${LIB_DIR}/os.sh"
    [[ "$_LIB_OS_LOADED" == "1" ]]
}
