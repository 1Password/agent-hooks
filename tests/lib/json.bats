#!/usr/bin/env bats

load "../test_helper"

setup() {
    unset _LIB_JSON_LOADED _LIB_LOGGING_LOADED
    source "${LIB_DIR}/json.sh"
}

# ========== escape_json_string ==========

@test "escape_json_string escapes double quotes" {
    run escape_json_string 'say "hello"'
    [[ "$output" == 'say \"hello\"' ]]
}

@test "escape_json_string escapes backslashes" {
    run escape_json_string 'path\to\file'
    [[ "$output" == 'path\\to\\file' ]]
}

@test "escape_json_string handles plain string unchanged" {
    run escape_json_string "no special chars"
    [[ "$output" == "no special chars" ]]
}

@test "escape_json_string handles empty string" {
    run escape_json_string ""
    [[ "$output" == "" ]]
}

# ========== extract_json_string ==========

@test "extract_json_string extracts a simple field" {
    local json='{"cwd": "/Users/alice/project"}'
    run extract_json_string "$json" "cwd"
    [[ "$output" == "/Users/alice/project" ]]
}

@test "extract_json_string extracts first match when key appears multiple times" {
    local json='{"name": "first", "nested": {"name": "second"}}'
    run extract_json_string "$json" "name"
    [[ "$output" == "first" ]]
}

@test "extract_json_string returns empty for missing key" {
    local json='{"name": "alice"}'
    run extract_json_string "$json" "cwd"
    [[ "$status" -eq 0 ]]
    [[ "$output" == "" ]]
}

@test "extract_json_string returns empty for empty JSON" {
    run extract_json_string "{}" "cwd"
    [[ "$status" -eq 0 ]]
    [[ "$output" == "" ]]
}

@test "extract_json_string handles whitespace around colon" {
    local json='{"cwd"  :  "/tmp"}'
    run extract_json_string "$json" "cwd"
    [[ "$output" == "/tmp" ]]
}

@test "extract_json_string handles Cursor payload" {
    local json='{"command": "npm run build", "workspace_roots": ["/project"], "cwd": "/project"}'
    run extract_json_string "$json" "command"
    [[ "$output" == "npm run build" ]]
}

@test "extract_json_string handles Windsurf agent_action_name" {
    local json='{"agent_action_name": "pre_run_command", "tool_info": {"cwd": "/tmp"}}'
    run extract_json_string "$json" "agent_action_name"
    [[ "$output" == "pre_run_command" ]]
}

@test "extract_json_string handles Claude Code hook_event_name" {
    local json='{"hook_event_name": "PreToolUse", "tool_name": "Bash", "cwd": "/project"}'
    run extract_json_string "$json" "hook_event_name"
    [[ "$output" == "PreToolUse" ]]
}

# ========== parse_json_workspace_roots ==========

@test "parse_json_workspace_roots extracts single-line array" {
    local json='{"workspace_roots": ["/Users/alice/project"]}'
    run parse_json_workspace_roots "$json"
    [[ "$output" == "/Users/alice/project" ]]
}

@test "parse_json_workspace_roots extracts multiple roots" {
    local json='{"workspace_roots": ["/project-a", "/project-b"]}'
    run parse_json_workspace_roots "$json"
    local -a lines
    mapfile -t lines <<< "$output"
    [[ "${lines[0]}" == "/project-a" ]]
    [[ "${lines[1]}" == "/project-b" ]]
}

@test "parse_json_workspace_roots handles multi-line array" {
    local json='{
  "workspace_roots": [
    "/project-a",
    "/project-b"
  ]
}'
    run parse_json_workspace_roots "$json"
    local -a lines
    mapfile -t lines <<< "$output"
    [[ "${lines[0]}" == "/project-a" ]]
    [[ "${lines[1]}" == "/project-b" ]]
}

@test "parse_json_workspace_roots returns empty for empty array" {
    local json='{"workspace_roots": []}'
    run parse_json_workspace_roots "$json"
    [[ "$status" -eq 0 ]]
    [[ -z "$output" ]]
}

@test "parse_json_workspace_roots returns empty when key is missing" {
    local json='{"cwd": "/tmp"}'
    run parse_json_workspace_roots "$json"
    [[ "$status" -eq 0 ]]
    [[ -z "$output" ]]
}

# ========== json_has_key ==========

@test "json_has_key returns 0 when key exists" {
    json_has_key '{"workspace_roots": []}' "workspace_roots"
}

@test "json_has_key returns 1 when key is missing" {
    ! json_has_key '{"other": 1}' "workspace_roots"
}

@test "json_has_key works with string values" {
    json_has_key '{"agent_action_name": "pre_run_command"}' "agent_action_name"
}

@test "json_has_key does not match partial key names" {
    ! json_has_key '{"workspace_roots_extra": []}' "workspace_roots"
}
