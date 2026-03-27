#!/usr/bin/env bats

load "../test_helper"

HOOK_SCRIPT="${PROJECT_ROOT}/hooks/1password-validate-mounted-env-files/hook.sh"

canonical_empty_roots='{"client":"cursor","event":"before_shell_execution","type":"command","workspace_roots":[],"cwd":"","command":"echo hi","raw_payload":{}}'


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
    local ws="${BATS_TEST_TMPDIR}/workspace"
    mkdir -p "$ws/.1password"
    printf '%s\n' 'mount_paths = [".env.missing"]' > "$ws/.1password/environments.toml"

    local payload
    payload=$(python3 -c "import json,sys; print(json.dumps({
        'client': 'cursor',
        'event': 'before_shell_execution',
        'type': 'command',
        'workspace_roots': [sys.argv[1]],
        'cwd': sys.argv[1],
        'command': 'echo hi',
        'raw_payload': {},
    }))" "$ws")

    run bash "$HOOK_SCRIPT" <<<"$payload"
    run bash "$HOOK_SCRIPT" <<<"$payload"
    [[ $status -eq 1 ]]
    [[ -n "$output" ]]
    [[ $(printf '%s' "$output" | wc -l) -eq 1 ]]
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

