#!/usr/bin/env bats

load "../test_helper"

setup() {
    unset _ADAPTERS_LIB_LOADED _LIB_JSON_LOADED _LIB_LOGGING_LOADED
    unset CURSOR_VERSION CLAUDE_PROJECT_DIR
    source "${PROJECT_ROOT}/adapters/_lib.sh"
}

# ========== Cursor detection ==========

@test "detect_client returns cursor when CURSOR_VERSION is set" {
    CURSOR_VERSION="1.7.2" run detect_client '{"command": "ls"}'
    [[ "$output" == "cursor" ]]
}

@test "detect_client returns cursor when payload has cursor_version" {
    run detect_client '{"cursor_version": "1.7.2", "command": "ls", "workspace_roots": ["/tmp"]}'
    [[ "$output" == "cursor" ]]
}

@test "detect_client returns cursor even when CLAUDE_PROJECT_DIR is also set" {
    CURSOR_VERSION="1.7.2" CLAUDE_PROJECT_DIR="/tmp" run detect_client '{"cursor_version": "1.7.2"}'
    [[ "$output" == "cursor" ]]
}

# ========== Windsurf detection ==========

@test "detect_client returns windsurf for agent_action_name payload" {
    run detect_client '{"agent_action_name": "pre_run_command", "tool_info": {"command_line": "ls"}}'
    [[ "$output" == "windsurf" ]]
}

@test "detect_client returns windsurf for post_write_code action" {
    run detect_client '{"agent_action_name": "post_write_code", "trajectory_id": "abc"}'
    [[ "$output" == "windsurf" ]]
}

# ========== Claude Code detection ==========

@test "detect_client returns claude when CLAUDE_PROJECT_DIR set (no Cursor env)" {
    CLAUDE_PROJECT_DIR="/home/user/project" run detect_client '{"hook_event_name": "PreToolUse", "tool_name": "Bash"}'
    [[ "$output" == "claude" ]]
}

@test "detect_client returns claude when payload has permission_mode" {
    run detect_client '{"hook_event_name": "PreToolUse", "permission_mode": "default", "tool_name": "Bash"}'
    [[ "$output" == "claude" ]]
}

# ========== GitHub Copilot detection ==========

@test "detect_client returns github-copilot for hookEventName payload" {
    run detect_client '{"hookEventName": "PreToolUse", "tool_name": "run_in_terminal", "cwd": "/tmp"}'
    [[ "$output" == "github-copilot" ]]
}

@test "detect_client returns github-copilot for sessionId payload" {
    run detect_client '{"hookEventName": "SessionStart", "sessionId": "abc-123"}'
    [[ "$output" == "github-copilot" ]]
}

# ========== Unknown / fallback ==========

@test "detect_client returns unknown for empty object" {
    run detect_client '{}'
    [[ "$output" == "unknown" ]]
}

@test "detect_client returns unknown for unrecognized payload" {
    run detect_client '{"foo": "bar", "baz": 42}'
    [[ "$output" == "unknown" ]]
}

# ========== Priority / ambiguity tests ==========

@test "detect_client prefers cursor over claude when both env vars set" {
    CURSOR_VERSION="1.7.2" CLAUDE_PROJECT_DIR="/tmp" run detect_client '{"command": "ls"}'
    [[ "$output" == "cursor" ]]
}

@test "detect_client does not confuse Cursor payload (with hook_event_name) for copilot" {
    CURSOR_VERSION="1.7.2" run detect_client '{"hook_event_name": "beforeShellExecution", "tool_name": "Shell", "workspace_roots": ["/tmp"]}'
    [[ "$output" == "cursor" ]]
}

@test "detect_client distinguishes Claude Code from Copilot by permission_mode" {
    run detect_client '{"hook_event_name": "PreToolUse", "permission_mode": "default", "tool_name": "Bash"}'
    [[ "$output" == "claude" ]]
}
