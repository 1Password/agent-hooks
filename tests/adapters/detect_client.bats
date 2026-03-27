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

# ========== GitHub Copilot detection (process of elimination) ==========
# Copilot sends hook_event_name just like Cursor.
# It is identified by having hook_event_name but no Cursor-specific signals.

@test "detect_client returns github-copilot for hook_event_name payload without Cursor signals" {
    run detect_client '{"hook_event_name": "PreToolUse", "tool_name": "run_in_terminal", "cwd": "/tmp"}'
    [[ "$output" == "github-copilot" ]]
}

@test "detect_client returns github-copilot for SessionStart payload" {
    run detect_client '{"hook_event_name": "SessionStart", "sessionId": "abc-123"}'
    [[ "$output" == "github-copilot" ]]
}

# ========== Windsurf (Cascade) ==========

@test "detect_client returns windsurf when payload has agent_action_name" {
    run detect_client '{"agent_action_name":"pre_run_command","tool_info":{"command_line":"ls","cwd":"/tmp"}}'
    [[ "$output" == "windsurf" ]]
}

@test "detect_client prefers cursor over agent_action_name when cursor_version present" {
    run detect_client '{"cursor_version":"1.0.0","agent_action_name":"pre_run_command","tool_info":{"command_line":"ls","cwd":"/tmp"}}'
    [[ "$output" == "cursor" ]]
}

@test "detect_client prefers windsurf over github-copilot when both hook_event_name and agent_action_name present" {
    run detect_client '{"agent_action_name":"pre_run_command","hook_event_name":"PreToolUse","tool_info":{"command_line":"ls","cwd":"/tmp"}}'
    [[ "$output" == "windsurf" ]]
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

@test "detect_client does not confuse Cursor payload (with hook_event_name) for copilot" {
    CURSOR_VERSION="1.7.2" run detect_client '{"hook_event_name": "beforeShellExecution", "tool_name": "Shell", "workspace_roots": ["/tmp"]}'
    [[ "$output" == "cursor" ]]
}
