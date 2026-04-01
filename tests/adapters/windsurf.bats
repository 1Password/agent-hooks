#!/usr/bin/env bats

load "../test_helper"

setup() {
    unset _ADAPTER_WINDSURF_LOADED _ADAPTERS_LIB_LOADED _LIB_JSON_LOADED _LIB_LOGGING_LOADED
    source "${PROJECT_ROOT}/adapters/windsurf.sh"
}

WINDSURF_PRE_RUN='{"agent_action_name":"pre_run_command","tool_info":{"command_line":"npm run build","cwd":"/Users/alice/project"}}'

# ========== normalize_input ==========

@test "normalize_input produces canonical JSON with client windsurf" {
    local result
    result=$(normalize_input "$WINDSURF_PRE_RUN")
    local client
    client=$(extract_json_string "$result" "client")
    [[ "$client" == "windsurf" ]]
}

@test "normalize_input maps pre_run_command to before_shell_execution" {
    local result
    result=$(normalize_input "$WINDSURF_PRE_RUN")
    local event
    event=$(extract_json_string "$result" "event")
    [[ "$event" == "before_shell_execution" ]]
}

@test "normalize_input extracts command from command_line" {
    local result
    result=$(normalize_input "$WINDSURF_PRE_RUN")
    local cmd
    cmd=$(extract_json_string "$result" "command")
    [[ "$cmd" == "npm run build" ]]
}

@test "normalize_input extracts cwd from tool_info" {
    local result
    result=$(normalize_input "$WINDSURF_PRE_RUN")
    local cwd
    cwd=$(extract_json_string "$result" "cwd")
    [[ "$cwd" == "/Users/alice/project" ]]
}

@test "normalize_input uses cwd as workspace root when workspace_roots absent" {
    local result
    result=$(normalize_input "$WINDSURF_PRE_RUN")
    local roots
    roots=$(parse_json_workspace_roots "$result")
    [[ "$roots" == "/Users/alice/project" ]]
}

# ========== emit_output ==========

@test "emit_output exits 0 on allow" {
    local canonical='{"decision":"allow","message":""}'
    run emit_output "$canonical"
    [[ "$status" -eq 0 ]]
    [[ -z "$output" ]]
}

@test "emit_output exits 2 and prints message to stderr on deny" {
    local canonical='{"decision":"deny","message":"env file missing"}'
    run emit_output "$canonical"
    [[ "$status" -eq 2 ]]
    [[ "$output" == "env file missing" ]]
}
