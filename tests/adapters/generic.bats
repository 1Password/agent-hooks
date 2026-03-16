#!/usr/bin/env bats

load "../test_helper"

setup() {
    unset _ADAPTER_GENERIC_LOADED _ADAPTERS_LIB_LOADED _LIB_JSON_LOADED _LIB_LOGGING_LOADED
    source "${PROJECT_ROOT}/adapters/generic.sh"
}

# ========== normalize_input ==========

@test "normalize_input sets client to unknown" {
    local payload='{"cwd": "/tmp", "command": "echo hi"}'
    local result
    result=$(normalize_input "$payload")
    local client
    client=$(extract_json_string "$result" "client")
    [[ "$client" == "unknown" ]]
}

@test "normalize_input extracts cwd and command" {
    local payload='{"cwd": "/project", "command": "npm test"}'
    local result
    result=$(normalize_input "$payload")
    [[ $(extract_json_string "$result" "cwd") == "/project" ]]
    [[ $(extract_json_string "$result" "command") == "npm test" ]]
}

@test "normalize_input falls back to cwd when workspace_roots missing" {
    local payload='{"cwd": "/project", "command": "ls"}'
    local result
    result=$(normalize_input "$payload")
    local roots
    roots=$(parse_json_workspace_roots "$result")
    [[ "$roots" == "/project" ]]
}

@test "normalize_input uses workspace_roots when present" {
    local payload='{"workspace_roots": ["/project-a"], "cwd": "/project-a", "command": "ls"}'
    local result
    result=$(normalize_input "$payload")
    local roots
    roots=$(parse_json_workspace_roots "$result")
    [[ "$roots" == "/project-a" ]]
}

# ========== emit_output ==========

@test "emit_output exits 0 and produces no stdout for allow" {
    local canonical='{"decision": "allow", "message": ""}'
    run emit_output "$canonical"
    [[ "$status" -eq 0 ]]
    [[ -z "$output" ]]
}

@test "emit_output exits 1 and writes message to stderr for deny" {
    local canonical='{"decision": "deny", "message": "blocked by policy"}'
    run emit_output "$canonical"
    [[ "$status" -eq 1 ]]
}
