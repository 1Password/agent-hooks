#!/usr/bin/env bats

load "../test_helper"

HOOK_SCRIPT="${PROJECT_ROOT}/hooks/1password-validate-mounted-env-files/hook.sh"

# Minimal SQLite DB at the path find_1password_db expects; query_mounts requires objects_associated.
create_minimal_1password_sqlite_fixture() {
    local fake_home="$1"
    local db_path
    case "$(uname -s)" in
        Darwin*)
            db_path="${fake_home}/Library/Group Containers/2BUA8C4S2C.com.1password/Library/Application Support/1Password/Data/1Password.sqlite"
            ;;
        *)
            db_path="${fake_home}/.config/1Password/1Password.sqlite"
            ;;
    esac
    mkdir -p "$(dirname "$db_path")"
    sqlite3 "$db_path" 'CREATE TABLE objects_associated (key_name TEXT, data BLOB);'
}

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
    local regex='^\{"decision":"allow","message":"","mode":"default","mount_count":0,"deny_reason":null\}$'
    [[ $output =~ $regex ]]
}

@test "deny output has non-empty message" {
    if ! command -v sqlite3 &>/dev/null; then
        skip "sqlite3 not available"
    fi

    export HOME="${BATS_TEST_TMPDIR}/home"
    mkdir -p "$HOME"
    create_minimal_1password_sqlite_fixture "$HOME"

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

    run env HOME="$HOME" bash "$HOOK_SCRIPT" <<<"$payload"
    [[ $status -eq 1 ]]
    [[ $(printf '%s\n' "$output" | wc -l) -eq 1 ]]
    printf '%s' "$output" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d.get("decision")=="deny" and d.get("message"), d'
}

@test "hook produces no extra lines or stderr" {
    run bash -c "echo '$canonical_empty_roots' | bash \"${HOOK_SCRIPT}\" 2>&1"
    [[ $status -eq 0 ]]
    [[ $(echo "$output" | wc -l) -eq 1 ]]
    [[ $output == '{"decision":"allow","message":"","mode":"default","mount_count":0,"deny_reason":null}' ]]
}

@test "empty workspace_roots returns allow and exit 0" {
    run bash -c "echo '$canonical_empty_roots' | bash \"${HOOK_SCRIPT}\""
    [[ $status -eq 0 ]]
    [[ "$output" == '{"decision":"allow","message":"","mode":"default","mount_count":0,"deny_reason":null}' ]]
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

# ============================================================================
# Fail-open regression tests for `set -e` aborts on the 1Password DB lookup
# ============================================================================
#
# find_1password_db and query_mounts use a non-zero return as a normal
# "not found / unavailable" signal. Under `set -euo pipefail`, a non-zero
# command substitution in an assignment aborts the script before the
# fail-open logic runs — so the hook would exit 1 with empty stdout instead
# of allowing. These two tests pin the intended fail-open behavior and run
# without sqlite3 (the exact path the prior `deny` test skips).

# Build a canonical-input payload for one workspace root.
_canonical_for_root() {
    python3 -c "import json,sys; print(json.dumps({
        'client': 'cursor',
        'event': 'before_shell_execution',
        'type': 'command',
        'workspace_roots': [sys.argv[1]],
        'cwd': sys.argv[1],
        'command': 'echo hi',
        'raw_payload': {},
    }))" "$1"
}

@test "fails open (allow) when no 1Password database is present" {
    # Regression for line ~415: db_path=$(find_1password_db ...) returns
    # non-zero when no database exists on disk.
    local home="${BATS_TEST_TMPDIR}/home"
    mkdir -p "$home"   # intentionally no 1Password sqlite database

    local ws="${BATS_TEST_TMPDIR}/workspace"
    mkdir -p "$ws"     # no .1password/environments.toml -> default mode

    run env HOME="$home" bash "$HOOK_SCRIPT" <<<"$(_canonical_for_root "$ws")"

    [[ $status -eq 0 ]]
    [[ "$output" == '{"decision":"allow","message":""}' ]]
}

@test "fails open (allow) when the 1Password database cannot be queried" {
    # Regression for line ~417: mount_hex_data=$(query_mounts ...) returns
    # non-zero when sqlite3 is missing or the database is invalid/unreadable.
    # A present-but-invalid db file reaches query_mounts and forces the
    # non-zero path regardless of whether sqlite3 is installed.
    local home="${BATS_TEST_TMPDIR}/home"
    local db_dir
    case "$(uname -s)" in
        Darwin*)
            db_dir="${home}/Library/Group Containers/2BUA8C4S2C.com.1password/Library/Application Support/1Password/Data"
            ;;
        *)
            db_dir="${home}/.config/1Password"
            ;;
    esac
    mkdir -p "$db_dir"
    printf 'not-a-valid-sqlite-database' > "${db_dir}/1Password.sqlite"

    local ws="${BATS_TEST_TMPDIR}/workspace"
    mkdir -p "$ws"

    run env HOME="$home" bash "$HOOK_SCRIPT" <<<"$(_canonical_for_root "$ws")"

    [[ $status -eq 0 ]]
    [[ "$output" == '{"decision":"allow","message":""}' ]]
}

