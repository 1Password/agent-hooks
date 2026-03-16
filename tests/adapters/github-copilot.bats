#!/usr/bin/env bats

load "../test_helper"

setup() {
    unset _ADAPTER_COPILOT_LOADED _ADAPTERS_LIB_LOADED _LIB_JSON_LOADED _LIB_LOGGING_LOADED
    unset CLAUDE_PROJECT_DIR CURSOR_VERSION
    source "${PROJECT_ROOT}/adapters/github-copilot.sh"
}

COPILOT_PAYLOAD='{"hookEventName": "PreToolUse", "tool_name": "run_in_terminal", "cwd": "/Users/bob/project", "command": "make test"}'

# ========== normalize_input ==========

@test "normalize_input produces canonical JSON with correct client field" {
    local result
    result=$(normalize_input "$COPILOT_PAYLOAD")
    local client
    client=$(extract_json_string "$result" "client")
    [[ "$client" == "github-copilot" ]]
}

@test "normalize_input sets event to before_shell_execution" {
    local result
    result=$(normalize_input "$COPILOT_PAYLOAD")
    local event
    event=$(extract_json_string "$result" "event")
    [[ "$event" == "before_shell_execution" ]]
}

@test "normalize_input sets type to command" {
    local result
    result=$(normalize_input "$COPILOT_PAYLOAD")
    local type
    type=$(extract_json_string "$result" "type")
    [[ "$type" == "command" ]]
}

@test "normalize_input extracts cwd" {
    local result
    result=$(normalize_input "$COPILOT_PAYLOAD")
    local cwd
    cwd=$(extract_json_string "$result" "cwd")
    [[ "$cwd" == "/Users/bob/project" ]]
}

@test "normalize_input extracts tool_name" {
    local result
    result=$(normalize_input "$COPILOT_PAYLOAD")
    local tn
    tn=$(extract_json_string "$result" "tool_name")
    [[ "$tn" == "run_in_terminal" ]]
}

@test "normalize_input extracts command" {
    local result
    result=$(normalize_input "$COPILOT_PAYLOAD")
    local cmd
    cmd=$(extract_json_string "$result" "command")
    [[ "$cmd" == "make test" ]]
}

@test "normalize_input uses cwd as workspace_roots" {
    local result
    result=$(normalize_input "$COPILOT_PAYLOAD")
    local roots
    roots=$(parse_json_workspace_roots "$result")
    [[ "$roots" == "/Users/bob/project" ]]
}

@test "normalize_input embeds raw_payload" {
    local result
    result=$(normalize_input "$COPILOT_PAYLOAD")
    [[ "$result" == *"raw_payload"* ]]
    [[ "$result" == *"PreToolUse"* ]]
}

# ========== emit_output ==========

@test "emit_output produces continue true for allow" {
    local canonical='{"decision": "allow", "message": ""}'
    run emit_output "$canonical"
    [[ "$status" -eq 0 ]]
    [[ "$output" == '{"continue": true}' ]]
}

@test "emit_output produces continue false with stopReason for deny" {
    local canonical='{"decision": "deny", "message": "env file missing"}'
    run emit_output "$canonical"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *'"continue": false'* ]]
    [[ "$output" == *'"stopReason": "env file missing"'* ]]
}

@test "emit_output always exits 0 for Copilot (even on deny)" {
    local canonical='{"decision": "deny", "message": "blocked"}'
    run emit_output "$canonical"
    [[ "$status" -eq 0 ]]
}
