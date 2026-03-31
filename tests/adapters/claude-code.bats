#!/usr/bin/env bats

load "../test_helper"

setup() {
    unset _ADAPTERS_LIB_LOADED _ADAPTER_CLAUDE_CODE_LOADED _LIB_JSON_LOADED _LIB_LOGGING_LOADED
    unset CURSOR_VERSION CLAUDE_PROJECT_DIR
    export CLAUDE_PROJECT_DIR="/tmp"
    source "${PROJECT_ROOT}/adapters/claude-code.sh"
}

# ========== normalize_input ==========

@test "normalize_input produces canonical JSON with correct client field" {
    local payload='{"hook_event_name": "PreToolUse", "tool_name": "Bash", "tool_input": {"command": "ls -la"}, "cwd": "/tmp", "command": "ls -la", "permission_mode": "default"}'
    result=$(normalize_input "$payload")
    local client
    client=$(echo "$result" | grep -oE '"client"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*: *"\(.*\)"/\1/')
    [[ "$client" == "claude-code" ]]
}

@test "normalize_input sets event to before_shell_execution" {
    local payload='{"hook_event_name": "PreToolUse", "tool_name": "Bash", "cwd": "/tmp", "command": "echo hi"}'
    result=$(normalize_input "$payload")
    local event
    event=$(echo "$result" | grep -oE '"event"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*: *"\(.*\)"/\1/')
    [[ "$event" == "before_shell_execution" ]]
}

@test "normalize_input sets type to command" {
    local payload='{"hook_event_name": "PreToolUse", "tool_name": "Bash", "cwd": "/tmp", "command": "echo hi"}'
    result=$(normalize_input "$payload")
    local type
    type=$(echo "$result" | grep -oE '"type"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*: *"\(.*\)"/\1/')
    [[ "$type" == "command" ]]
}

@test "normalize_input extracts cwd" {
    local payload='{"cwd": "/home/user/project", "command": "echo hi"}'
    result=$(normalize_input "$payload")
    local cwd
    cwd=$(echo "$result" | grep -oE '"cwd"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*: *"\(.*\)"/\1/')
    [[ "$cwd" == "/home/user/project" ]]
}

@test "normalize_input extracts command" {
    local payload='{"cwd": "/tmp", "command": "npm test"}'
    result=$(normalize_input "$payload")
    local command
    command=$(echo "$result" | grep -oE '"command"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*: *"\(.*\)"/\1/')
    [[ "$command" == "npm test" ]]
}

@test "normalize_input extracts tool_name" {
    local payload='{"tool_name": "Bash", "cwd": "/tmp", "command": "echo hi"}'
    result=$(normalize_input "$payload")
    local tool_name
    tool_name=$(echo "$result" | grep -oE '"tool_name"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*: *"\(.*\)"/\1/')
    [[ "$tool_name" == "Bash" ]]
}

@test "normalize_input uses CLAUDE_PROJECT_DIR as workspace root" {
    export CLAUDE_PROJECT_DIR="/home/user/myproject"
    local payload='{"cwd": "/home/user/myproject/src", "command": "ls"}'
    result=$(normalize_input "$payload")
    [[ "$result" == *"/home/user/myproject"* ]]
}

@test "normalize_input falls back to cwd when CLAUDE_PROJECT_DIR is unset" {
    unset CLAUDE_PROJECT_DIR
    local payload='{"cwd": "/home/user/project", "command": "ls"}'
    result=$(normalize_input "$payload")
    [[ "$result" == *"/home/user/project"* ]]
}

# ========== emit_output ==========

@test "emit_output exits 0 and produces no stdout for allow" {
    run emit_output '{"decision":"allow","message":""}'
    [[ $status -eq 0 ]]
    [[ -z "$output" ]]
}

@test "emit_output exits 2 and writes message to stderr for deny" {
    run emit_output '{"decision":"deny","message":"Environment files are missing"}'
    [[ $status -eq 2 ]]
    [[ "$output" == *"Environment files are missing"* ]]
}
