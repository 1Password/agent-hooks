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
    local regex='^\{"decision":"allow","message":""\}$'
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
    [[ $output == '{"decision":"allow","message":""}' ]]
}

@test "empty workspace_roots returns allow and exit 0" {
    run bash -c "echo '$canonical_empty_roots' | bash \"${HOOK_SCRIPT}\""
    [[ $status -eq 0 ]]
    [[ "$output" == '{"decision":"allow","message":""}' ]]
}

