#!/usr/bin/env bats

load "../test_helper"

HOOK_SCRIPT="${PROJECT_ROOT}/hooks/1password-validate-mounted-env-files/hook.sh"

canonical_empty_roots='{"client":"cursor","event":"before_shell_execution","type":"command","workspace_roots":[],"cwd":"","command":"echo hi","raw_payload":{}}'
canonical_one_root='{"client":"cursor","event":"before_shell_execution","type":"command","workspace_roots":["/tmp"],"cwd":"/tmp","command":"echo hi","raw_payload":{}}'


@test "hook outputs exactly one line" {
    run bash -c "echo '$canonical_empty_roots' | bash \"${HOOK_SCRIPT}\""
    [[ $status -eq 0 ]]
    [[ $(echo "$output" | wc -l) -eq 1 ]]
}

@test "hook output has decision and message keys" {
    run bash -c "echo '$canonical_empty_roots' | bash \"${HOOK_SCRIPT}\""
    [[ $status -eq 0 ]]
    local regex='^\{"decision":"allow","message":""\}$'
    [[ $output =~ $regex ]]
}

@test "deny output has non-empty message" {
    run bash -c "echo '$canonical_one_root' | bash \"${HOOK_SCRIPT}\""
    if [[ $status -eq 1 ]]; then
        [[ $(echo "$output" | grep -oE '"message"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*: *"\(.*\)".*/\1/') != "" ]]
    fi
}

@test "hook produces no extra lines or stderr" {
    run bash -c "echo '$canonical_empty_roots' | bash \"${HOOK_SCRIPT}\" 2>&1"
    [[ $status -eq 0 ]]
    [[ $(echo "$output" | wc -l) -eq 1 ]]
    [[ $output == '{"decision":"allow","message":""}' ]]
}

@test "empty workspace_roots returns allow and exit 0" {
    run bash -c "echo '$canonical_empty_roots' | bash \"${HOOK_SCRIPT}\""
    [[ $status -eq 0 ]]
    [[ "$output" == '{"decision":"allow","message":""}' ]]
}

