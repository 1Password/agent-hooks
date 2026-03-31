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

# ============================================================================
# TOML mount_paths parsing tests (extract_toml_array_items / parse_toml_mount_paths)
# ============================================================================

# Source the hook functions for unit testing.
# Uses awk to extract top-level function definitions (handles nested braces).
_extract_func() {
    awk "/^$1\(\)/,/^}/" "$2"
}

TOML_TMPFILE=""

setup_toml_tests() {
    source "${PROJECT_ROOT}/lib/json.sh"
    source "${PROJECT_ROOT}/lib/os.sh"
    source "${PROJECT_ROOT}/lib/paths.sh"
    source "${PROJECT_ROOT}/lib/logging.sh"

    eval "$(_extract_func normalize_toml_line "${HOOK_SCRIPT}")"
    eval "$(_extract_func extract_toml_array_items "${HOOK_SCRIPT}")"
    eval "$(_extract_func has_toml_mount_paths_field "${HOOK_SCRIPT}")"
    eval "$(_extract_func parse_toml_mount_paths "${HOOK_SCRIPT}")"

    TOML_TMPFILE=$(mktemp)
}

teardown() {
    if [[ -n "$TOML_TMPFILE" ]]; then
        rm -f "$TOML_TMPFILE"
    fi
}

# Helper: assert output contains exactly the expected lines (order-independent).
assert_lines() {
    local expected=("$@")
    local actual_count
    actual_count=$(echo "$output" | wc -l | tr -d ' ')
    [[ "$actual_count" -eq ${#expected[@]} ]]
    for expected_line in "${expected[@]}"; do
        echo "$output" | grep -qxF "$expected_line"
    done
}

@test "parse_toml_mount_paths handles double-quoted items" {
    setup_toml_tests
    echo 'mount_paths = [".env", ".env.test"]' > "$TOML_TMPFILE"

    run parse_toml_mount_paths "$TOML_TMPFILE"

    [[ $status -eq 0 ]]
    assert_lines ".env" ".env.test"
}

@test "parse_toml_mount_paths handles single-quoted items" {
    setup_toml_tests
    printf "mount_paths = ['.env', '.env.test']\n" > "$TOML_TMPFILE"

    run parse_toml_mount_paths "$TOML_TMPFILE"

    [[ $status -eq 0 ]]
    assert_lines ".env" ".env.test"
}

@test "parse_toml_mount_paths handles mixed single and double quotes" {
    setup_toml_tests
    printf "mount_paths = ['.env', \".env.test\"]\n" > "$TOML_TMPFILE"

    run parse_toml_mount_paths "$TOML_TMPFILE"

    [[ $status -eq 0 ]]
    assert_lines ".env" ".env.test"
}

@test "parse_toml_mount_paths handles multi-line single-quoted items" {
    setup_toml_tests
    cat > "$TOML_TMPFILE" <<'TOML'
mount_paths = [
    '.env',
    '.env.test'
]
TOML

    run parse_toml_mount_paths "$TOML_TMPFILE"

    [[ $status -eq 0 ]]
    assert_lines ".env" ".env.test"
}

@test "parse_toml_mount_paths handles multi-line mixed quotes" {
    setup_toml_tests
    cat > "$TOML_TMPFILE" <<'TOML'
mount_paths = [
    '.env',
    ".env.test"
]
TOML

    run parse_toml_mount_paths "$TOML_TMPFILE"

    [[ $status -eq 0 ]]
    assert_lines ".env" ".env.test"
}

@test "parse_toml_mount_paths still handles empty array" {
    setup_toml_tests
    echo 'mount_paths = []' > "$TOML_TMPFILE"

    run parse_toml_mount_paths "$TOML_TMPFILE"

    [[ $status -eq 0 ]]
    [[ -z "$output" ]]
}

@test "parse_toml_mount_paths handles paths with spaces" {
    setup_toml_tests
    printf "mount_paths = ['.env file', \"other env\"]\n" > "$TOML_TMPFILE"

    run parse_toml_mount_paths "$TOML_TMPFILE"

    [[ $status -eq 0 ]]
    assert_lines ".env file" "other env"
}

@test "parse_toml_mount_paths handles single item array" {
    setup_toml_tests
    printf "mount_paths = ['.env']\n" > "$TOML_TMPFILE"

    run parse_toml_mount_paths "$TOML_TMPFILE"

    [[ $status -eq 0 ]]
    assert_lines ".env"
}

