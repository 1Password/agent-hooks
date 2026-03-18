#!/usr/bin/env bats

load "../test_helper"

setup() {
    unset _LIB_PATHS_LOADED _LIB_LOGGING_LOADED
    source "${LIB_DIR}/paths.sh"

    TEST_TMPDIR=$(mktemp -d)
}

teardown() {
    rm -rf "$TEST_TMPDIR"
}

# ========== validate_path ==========

@test "validate_path accepts normal absolute path" {
    validate_path "/usr/local/bin"
}

@test "validate_path accepts relative path" {
    validate_path "src/lib/utils.sh"
}

@test "validate_path accepts path with spaces" {
    validate_path "/Users/name/My Documents/file.txt"
}

@test "validate_path accepts path with dots" {
    validate_path "/project/../other/./file"
}

@test "validate_path accepts path with hyphens and underscores" {
    validate_path "/my-project/sub_dir/file-name_v2.sh"
}

@test "validate_path rejects empty string" {
    ! validate_path ""
}

@test "validate_path rejects dollar-paren command substitution" {
    ! validate_path '/tmp/$(rm -rf /)'
}

@test "validate_path rejects dollar-brace expansion" {
    ! validate_path '/tmp/${HOME}'
}

@test "validate_path rejects backtick substitution" {
    ! validate_path '/tmp/`whoami`'
}

@test "validate_path rejects semicolons" {
    ! validate_path "/tmp/foo;rm -rf /"
}

@test "validate_path rejects pipes" {
    ! validate_path "/tmp/foo|cat"
}

@test "validate_path rejects ampersands" {
    ! validate_path "/tmp/foo&bg"
}

@test "validate_path rejects redirect operators" {
    ! validate_path "/tmp/foo>bar"
    ! validate_path "/tmp/foo<bar"
}

# ========== normalize_path ==========

@test "normalize_path resolves existing directory" {
    run normalize_path "/tmp"
    [[ "$status" -eq 0 ]]
    [[ "$output" == "/tmp" ]] || [[ "$output" == "/private/tmp" ]]
}

@test "normalize_path resolves directory with trailing slash" {
    run normalize_path "/tmp/"
    [[ "$status" -eq 0 ]]
    [[ "$output" == "/tmp" ]] || [[ "$output" == "/private/tmp" ]]
}

@test "normalize_path resolves .. in path" {
    run normalize_path "/tmp/../tmp"
    [[ "$status" -eq 0 ]]
    [[ "$output" == "/tmp" ]] || [[ "$output" == "/private/tmp" ]]
}

@test "normalize_path resolves existing file" {
    local tmpfile="${TEST_TMPDIR}/testfile"
    touch "$tmpfile"

    run normalize_path "$tmpfile"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"/testfile" ]]
}

@test "normalize_path handles non-existent file with existing parent" {
    run normalize_path "${TEST_TMPDIR}/nonexistent.txt"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"/nonexistent.txt" ]]
}

@test "normalize_path returns unsafe path as-is without crashing" {
    run normalize_path '/tmp/$(evil)'
    [[ "$status" -eq 0 ]]
    [[ "$output" == '/tmp/$(evil)' ]]
}

@test "normalize_path returns completely invalid path as-is" {
    run normalize_path "/nonexistent/deeply/nested/path"
    [[ "$status" -eq 0 ]]
    [[ "$output" == "/nonexistent/deeply/nested/path" ]]
}

@test "normalize_path resolves FIFO pipe" {
    local fifo="${TEST_TMPDIR}/test.fifo"
    mkfifo "$fifo"

    run normalize_path "$fifo"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"/test.fifo" ]]
}
