#!/usr/bin/env bats

load "../test_helper"

setup() {
    unset _ADAPTER_CURSOR_LOADED _ADAPTERS_LIB_LOADED _LIB_JSON_LOADED _LIB_LOGGING_LOADED
    source "${PROJECT_ROOT}/adapters/cursor.sh"
}

CURSOR_PAYLOAD='{"command": "npm run build", "workspace_roots": ["/Users/alice/project"], "cwd": "/Users/alice/project"}'

# ========== normalize_input ==========

@test "normalize_input produces canonical JSON with correct client field" {
    local result
    result=$(normalize_input "$CURSOR_PAYLOAD")
    local client
    client=$(extract_json_string "$result" "client")
    [[ "$client" == "cursor" ]]
}

@test "normalize_input sets event to before_shell_execution" {
    local result
    result=$(normalize_input "$CURSOR_PAYLOAD")
    local event
    event=$(extract_json_string "$result" "event")
    [[ "$event" == "before_shell_execution" ]]
}

@test "normalize_input sets type to command" {
    local result
    result=$(normalize_input "$CURSOR_PAYLOAD")
    local type
    type=$(extract_json_string "$result" "type")
    [[ "$type" == "command" ]]
}

@test "normalize_input extracts cwd" {
    local result
    result=$(normalize_input "$CURSOR_PAYLOAD")
    local cwd
    cwd=$(extract_json_string "$result" "cwd")
    [[ "$cwd" == "/Users/alice/project" ]]
}

@test "normalize_input extracts command" {
    local result
    result=$(normalize_input "$CURSOR_PAYLOAD")
    local cmd
    cmd=$(extract_json_string "$result" "command")
    [[ "$cmd" == "npm run build" ]]
}

@test "normalize_input extracts workspace_roots" {
    local result
    result=$(normalize_input "$CURSOR_PAYLOAD")
    local roots
    roots=$(parse_json_workspace_roots "$result")
    [[ "$roots" == "/Users/alice/project" ]]
}

@test "normalize_input handles multiple workspace roots" {
    local payload='{"command": "ls", "workspace_roots": ["/project-a", "/project-b"], "cwd": "/project-a"}'
    local result
    result=$(normalize_input "$payload")
    local roots
    roots=$(parse_json_workspace_roots "$result")
    local -a lines=()
    while IFS= read -r line || [[ -n "$line" ]]; do
        lines+=("$line")
    done <<< "$roots"
    [[ "${lines[0]}" == "/project-a" ]]
    [[ "${lines[1]}" == "/project-b" ]]
}

@test "normalize_input embeds raw_payload" {
    local result
    result=$(normalize_input "$CURSOR_PAYLOAD")
    # raw_payload should contain the original fields
    [[ "$result" == *"raw_payload"* ]]
    [[ "$result" == *"npm run build"* ]]
}

# ========== emit_output ==========

@test "emit_output produces allow JSON for allow decision" {
    local canonical='{"decision": "allow", "message": ""}'
    run emit_output "$canonical"
    [[ "$status" -eq 0 ]]
    [[ "$output" == '{"permission": "allow"}' ]]
}

@test "emit_output produces deny JSON with agent_message" {
    local canonical='{"decision": "deny", "message": "env file missing"}'
    run emit_output "$canonical"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *'"permission": "deny"'* ]]
    [[ "$output" == *'"agent_message": "env file missing"'* ]]
}

@test "emit_output always exits 0 for Cursor (even on deny)" {
    local canonical='{"decision": "deny", "message": "blocked"}'
    run emit_output "$canonical"
    [[ "$status" -eq 0 ]]
}

@test "emit_output preserves environment name in deny message with escaped quotes" {
    local canonical='{"decision": "deny", "message": "Environment name: \"cursor-hook-test\". Path: \"/tmp/.env\"."}'
    run emit_output "$canonical"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *'cursor-hook-test'* ]]
    [[ "$output" == *'/tmp/.env'* ]]
}
