#!/usr/bin/env bats

load "../test_helper"

HOOK_SCRIPT="${PROJECT_ROOT}/hooks/1password-validate-mounted-env-files/hook.sh"

# Minimal SQLite DB at the path find_1password_db expects; query_mounts requires objects_associated.
# Echoes the resolved db_path so callers can insert additional rows (e.g. via insert_mount_row).
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
    echo "$db_path"
}

# Insert a mount row shaped like a real 1Password dev-environment-mount entry
# (hex-encoded JSON blob, matching what parse_mount/hex_to_json expect).
insert_mount_row() {
    local db_path="$1" mount_path="$2" is_enabled="$3" environment_name="$4" uuid="$5" environment_uuid="$6"

    local json_data hex_data
    json_data=$(python3 -c "import json,sys; print(json.dumps({
        'mountPath': sys.argv[1],
        'isEnabled': sys.argv[2] == 'true',
        'environmentName': sys.argv[3],
        'uuid': sys.argv[4],
        'environmentUuid': sys.argv[5],
    }))" "$mount_path" "$is_enabled" "$environment_name" "$uuid" "$environment_uuid")
    hex_data=$(printf '%s' "$json_data" | xxd -p | tr -d '\n')

    sqlite3 "$db_path" "INSERT INTO objects_associated (key_name, data) VALUES ('dev-environment-mount/${uuid}', X'${hex_data}');"
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

# ============================================================================
# file_read event tests (non-Bash file tools, e.g. Claude Code Read/Edit)
# ============================================================================

# NOTE: every case below exports a fake HOME with a minimal (possibly empty)
# 1Password sqlite fixture, even the ones that only need TOML data. hook.sh
# unconditionally queries the 1Password DB up front (same as the Bash/command
# path), and find_1password_db fails (non-fatal in production only because
# run-hook.sh wraps hook.sh and fails open on any error) when no real
# 1Password install is present — a fake HOME keeps these tests independent of
# whatever happens to be installed on the machine running them.

@test "file_read event with empty file_path allows without validation" {
    if ! command -v sqlite3 &>/dev/null; then
        skip "sqlite3 not available"
    fi

    export HOME="${BATS_TEST_TMPDIR}/home_empty_file_path"
    mkdir -p "$HOME"
    create_minimal_1password_sqlite_fixture "$HOME" >/dev/null

    local payload='{"client":"claude-code","event":"before_file_read","type":"file_read","workspace_roots":["/tmp"],"cwd":"/tmp","command":"","tool_name":"Read","file_path":"","raw_payload":{}}'
    run bash -c "echo '$payload' | bash \"${HOOK_SCRIPT}\""
    [[ $status -eq 0 ]]
    [[ "$output" == '{"decision":"allow","message":"","mode":"default","mount_count":0,"deny_reason":null}' ]]
}

@test "file_read event with file_path that is not a known mount allows, even when the workspace has an unrelated required mount" {
    if ! command -v sqlite3 &>/dev/null; then
        skip "sqlite3 not available"
    fi

    export HOME="${BATS_TEST_TMPDIR}/home_unrelated"
    mkdir -p "$HOME"
    create_minimal_1password_sqlite_fixture "$HOME" >/dev/null

    local ws="${BATS_TEST_TMPDIR}/workspace_unrelated"
    mkdir -p "$ws/.1password"
    printf '%s\n' 'mount_paths = [".env.missing"]' > "$ws/.1password/environments.toml"

    local other_file="${ws}/README.md"
    printf 'hello\n' > "$other_file"

    local payload
    payload=$(python3 -c "import json,sys; print(json.dumps({
        'client': 'claude-code',
        'event': 'before_file_read',
        'type': 'file_read',
        'workspace_roots': [sys.argv[1]],
        'cwd': sys.argv[1],
        'command': '',
        'tool_name': 'Read',
        'file_path': sys.argv[2],
        'raw_payload': {},
    }))" "$ws" "$other_file")

    run bash -c "echo '$payload' | bash \"${HOOK_SCRIPT}\""
    [[ $status -eq 0 ]]
    printf '%s' "$output" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d.get("decision")=="allow" and d.get("mount_count")==0, d'
}

@test "file_read event with file_path matching a TOML-required missing mount denies" {
    if ! command -v sqlite3 &>/dev/null; then
        skip "sqlite3 not available"
    fi

    export HOME="${BATS_TEST_TMPDIR}/home_toml_deny"
    mkdir -p "$HOME"
    create_minimal_1password_sqlite_fixture "$HOME" >/dev/null

    local ws="${BATS_TEST_TMPDIR}/workspace_toml_deny"
    mkdir -p "$ws/.1password"
    printf '%s\n' 'mount_paths = [".env.missing"]' > "$ws/.1password/environments.toml"

    local payload
    payload=$(python3 -c "import json,sys; print(json.dumps({
        'client': 'claude-code',
        'event': 'before_file_read',
        'type': 'file_read',
        'workspace_roots': [sys.argv[1]],
        'cwd': sys.argv[1],
        'command': '',
        'tool_name': 'Read',
        'file_path': sys.argv[1] + '/.env.missing',
        'raw_payload': {},
    }))" "$ws")

    run bash -c "echo '$payload' | bash \"${HOOK_SCRIPT}\""
    [[ $status -eq 1 ]]
    printf '%s' "$output" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d.get("decision")=="deny" and d.get("message") and d.get("mount_count")==1, d'
}

@test "file_read event with file_path matching a disabled DB mount denies" {
    if ! command -v sqlite3 &>/dev/null || ! command -v xxd &>/dev/null; then
        skip "sqlite3 or xxd not available"
    fi

    export HOME="${BATS_TEST_TMPDIR}/home_disabled"
    mkdir -p "$HOME"
    local db_path
    db_path=$(create_minimal_1password_sqlite_fixture "$HOME")

    local ws="${BATS_TEST_TMPDIR}/workspace_disabled"
    mkdir -p "$ws"
    local env_path="${ws}/.env"
    insert_mount_row "$db_path" "$env_path" "false" "Production" "uuid-1" "env-uuid-1"

    local payload
    payload=$(python3 -c "import json,sys; print(json.dumps({
        'client': 'claude-code',
        'event': 'before_file_read',
        'type': 'file_read',
        'workspace_roots': [sys.argv[1]],
        'cwd': sys.argv[1],
        'command': '',
        'tool_name': 'Read',
        'file_path': sys.argv[2],
        'raw_payload': {},
    }))" "$ws" "$env_path")

    run env HOME="$HOME" bash "$HOOK_SCRIPT" <<<"$payload"
    [[ $status -eq 1 ]]
    printf '%s' "$output" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d.get("decision")=="deny" and "Production" in d.get("message",""), d'
}

@test "file_read event with file_path matching a valid enabled FIFO mount allows" {
    if ! command -v sqlite3 &>/dev/null || ! command -v xxd &>/dev/null || ! command -v mkfifo &>/dev/null; then
        skip "sqlite3, xxd, or mkfifo not available"
    fi

    export HOME="${BATS_TEST_TMPDIR}/home_valid"
    mkdir -p "$HOME"
    local db_path
    db_path=$(create_minimal_1password_sqlite_fixture "$HOME")

    local ws="${BATS_TEST_TMPDIR}/workspace_valid"
    mkdir -p "$ws"
    local env_path="${ws}/.env"
    mkfifo "$env_path"
    insert_mount_row "$db_path" "$env_path" "true" "Production" "uuid-2" "env-uuid-2"

    local payload
    payload=$(python3 -c "import json,sys; print(json.dumps({
        'client': 'claude-code',
        'event': 'before_file_read',
        'type': 'file_read',
        'workspace_roots': [sys.argv[1]],
        'cwd': sys.argv[1],
        'command': '',
        'tool_name': 'Read',
        'file_path': sys.argv[2],
        'raw_payload': {},
    }))" "$ws" "$env_path")

    run env HOME="$HOME" bash "$HOOK_SCRIPT" <<<"$payload"
    [[ $status -eq 0 ]]
    [[ "$output" == '{"decision":"allow","message":"","mode":"default","mount_count":1,"deny_reason":null}' ]]
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

