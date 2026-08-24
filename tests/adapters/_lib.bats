#!/usr/bin/env bats

load "../test_helper"

setup() {
    unset _ADAPTERS_LIB_LOADED _LIB_JSON_LOADED _LIB_LOGGING_LOADED
    source "${PROJECT_ROOT}/adapters/_lib.sh"
}

# ========== build_canonical_input — raw_payload validation ==========

@test "build_canonical_input falls back to empty object for empty raw_payload" {
    local result
    result=$(build_canonical_input "cursor" "before_shell_execution" "command" '[]' "/tmp" "ls" "" "")
    [[ "$result" == *'"raw_payload": {}'* ]]
}

@test "build_canonical_input falls back to empty object for plain string raw_payload" {
    local result
    result=$(build_canonical_input "cursor" "before_shell_execution" "command" '[]' "/tmp" "ls" "" "not json at all")
    [[ "$result" == *'"raw_payload": {}'* ]]
}

@test "build_canonical_input falls back to empty object for truncated JSON raw_payload" {
    local result
    result=$(build_canonical_input "cursor" "before_shell_execution" "command" '[]' "/tmp" "ls" "" '{"key": "val')
    [[ "$result" == *'"raw_payload": {}'* ]]
}

@test "build_canonical_input falls back to empty object for JSON array raw_payload" {
    local result
    result=$(build_canonical_input "cursor" "before_shell_execution" "command" '[]' "/tmp" "ls" "" '[1,2,3]')
    [[ "$result" == *'"raw_payload": {}'* ]]
}

@test "build_canonical_input preserves valid JSON object raw_payload" {
    local payload='{"command": "ls", "cwd": "/tmp"}'
    local result
    result=$(build_canonical_input "cursor" "before_shell_execution" "command" '[]' "/tmp" "ls" "" "$payload")
    [[ "$result" == *'"raw_payload": {"command": "ls", "cwd": "/tmp"}'* ]]
}

@test "build_canonical_input preserves valid JSON object with leading/trailing whitespace" {
    local payload='  {"command": "ls"}  '
    local result
    result=$(build_canonical_input "cursor" "before_shell_execution" "command" '[]' "/tmp" "ls" "" "$payload")
    [[ "$result" == *'"raw_payload": {"command": "ls"}'* ]]
}

# ========== build_canonical_input — file_path (9th, optional) ==========

@test "build_canonical_input defaults file_path to empty string when omitted" {
    local result
    result=$(build_canonical_input "cursor" "before_shell_execution" "command" '[]' "/tmp" "ls" "" "{}")
    [[ "$result" == *'"file_path": ""'* ]]
}

@test "build_canonical_input includes a supplied file_path" {
    local result
    result=$(build_canonical_input "claude-code" "before_file_read" "file_read" '[]' "/tmp" "" "Read" "{}" "/tmp/.env")
    [[ "$result" == *'"file_path": "/tmp/.env"'* ]]
}
