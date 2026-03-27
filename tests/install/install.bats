#!/usr/bin/env bats

load "../test_helper"

INSTALL_SCRIPT="${PROJECT_ROOT}/install.sh"
T="$BATS_TEST_TMPDIR"

# ---- Help / usage ----

@test "install.sh --help prints usage" {
  run bash "${INSTALL_SCRIPT}" --help
  [[ $status -eq 1 ]]
  [[ "$output" == *"Usage:"* ]]
  [[ "$output" == *"--agent"* ]]
  [[ "$output" == *"--target-dir"* ]]
}

@test "install.sh invalid --agent exits non-zero" {
  run bash "${INSTALL_SCRIPT}" --agent invalid --target-dir "${T}"
  [[ $status -ne 0 ]]
  [[ "$output" == *"could not find agent block"* ]]
  [[ "$output" == *"invalid"* ]]
}

@test "install.sh unknown option exits non-zero" {
  run bash "${INSTALL_SCRIPT}" --agent cursor --scope project
  [[ $status -ne 0 ]]
  [[ "$output" == *"Unknown option"* ]]
}

@test "install.sh nonexistent --target-dir exits non-zero" {
  run bash "${INSTALL_SCRIPT}" --agent cursor --target-dir "${T}/nonexistent"
  [[ $status -ne 0 ]]
  [[ "$output" == *"does not exist"* ]]
}

@test "install.sh without --target-dir creates bundle in cwd and does not create hooks.json" {
  run bash -c "cd '${T}' && bash '${INSTALL_SCRIPT}' --agent cursor"
  [[ $status -eq 0 ]]
  [[ -f "${T}/cursor-1password-hooks-bundle/bin/run-hook.sh" ]]
  [[ -f "${T}/cursor-1password-hooks-bundle/adapters/cursor.sh" ]]
  [[ -f "${T}/cursor-1password-hooks-bundle/hooks/1password-validate-mounted-env-files/hook.sh" ]]
  [[ "$output" == *"Bundle created at:"* ]]
  [[ "$output" == *"Add hooks.json"* ]]
  [[ ! -f "${T}/cursor-1password-hooks-bundle/hooks.json" ]]
  [[ ! -f "${T}/.cursor/hooks.json" ]]
}

# ---- Cursor: install paths ----

@test "cursor: hooks.json command path is rewritten to bundle-relative path" {
  run bash "${INSTALL_SCRIPT}" --agent cursor --target-dir "${T}"
  [[ $status -eq 0 ]]
  run grep -Fq '.cursor/cursor-1password-hooks-bundle/bin/run-hook.sh' "${T}/.cursor/hooks.json"
  [[ $status -eq 0 ]]
}

@test "cursor: --target-dir creates .cursor/cursor-1password-hooks-bundle and expected files" {
  run bash "${INSTALL_SCRIPT}" --agent cursor --target-dir "${T}"
  [[ $status -eq 0 ]]
  [[ -f "${T}/.cursor/cursor-1password-hooks-bundle/bin/run-hook.sh" ]]
  [[ -d "${T}/.cursor/cursor-1password-hooks-bundle/lib" ]]
  [[ -n "$(echo "${T}"/.cursor/cursor-1password-hooks-bundle/lib/*.sh)" ]]
  [[ -f "${T}/.cursor/cursor-1password-hooks-bundle/adapters/_lib.sh" ]]
  [[ -f "${T}/.cursor/cursor-1password-hooks-bundle/adapters/cursor.sh" ]]
  [[ -f "${T}/.cursor/cursor-1password-hooks-bundle/adapters/generic.sh" ]]
  [[ -f "${T}/.cursor/cursor-1password-hooks-bundle/hooks/1password-validate-mounted-env-files/hook.sh" ]]
  [[ -f "${T}/.cursor/hooks.json" ]]
  [[ "$output" == *"Config path:"* ]]
  [[ "$output" == *"Done. Hook(s) installed"* ]]
}

@test "cursor: does not overwrite existing hooks.json" {
  mkdir -p "${T}/.cursor"
  echo '{"version":1,"hooks":{"custom":"unchanged"}}' > "${T}/.cursor/hooks.json"
  run bash "${INSTALL_SCRIPT}" --agent cursor --target-dir "${T}"
  [[ $status -eq 0 ]]
  [[ "$output" == *"Config already exists at"* ]]
  [[ "$output" == *"update it to add or change hook entries"* ]]
  [[ "$(cat "${T}/.cursor/hooks.json")" == '{"version":1,"hooks":{"custom":"unchanged"}}' ]]
}

# ---- Multiple hooks per event ----

@test "cursor: installs all hooks when event has multiple hooks" {
  # Create a temp repo with custom config: one event, two hooks
  local repo="${T}/repo"
  mkdir -p "${repo}/bin" "${repo}/lib" "${repo}/adapters" "${repo}/hooks/hook-a" "${repo}/hooks/hook-b"
  cp "${PROJECT_ROOT}/install.sh" "${repo}/"
  cp "${PROJECT_ROOT}/bin/run-hook.sh" "${repo}/bin/"
  cp "${PROJECT_ROOT}/lib/"*.sh "${repo}/lib/" 2>/dev/null || true
  cp "${PROJECT_ROOT}/adapters/"*.sh "${repo}/adapters/" 2>/dev/null || true
  echo '#!/bin/bash' > "${repo}/hooks/hook-a/hook.sh"
  echo '#!/bin/bash' > "${repo}/hooks/hook-b/hook.sh"
  cat > "${repo}/install-client-config.json" << 'EOF'
{
  "cursor": {
    "adapters": ["_lib.sh", "cursor.sh", "generic.sh"],
    "hook_events": {
      "beforeShellExecution": ["hook-a", "hook-b"]
    },
    "project": {
      "install_dir": ".cursor/cursor-1password-hooks-bundle",
      "config_path": ".cursor/hooks.json"
    }
  }
}
EOF
  run bash "${repo}/install.sh" --agent cursor --target-dir "${T}"
  [[ $status -eq 0 ]]
  [[ -f "${T}/.cursor/cursor-1password-hooks-bundle/hooks/hook-a/hook.sh" ]]
  [[ -f "${T}/.cursor/cursor-1password-hooks-bundle/hooks/hook-b/hook.sh" ]]
}

# ---- GitHub Copilot: install paths ----

@test "github-copilot: --target-dir creates .github/github-copilot-1password-hooks-bundle and expected files" {
  run bash "${INSTALL_SCRIPT}" --agent github-copilot --target-dir "${T}"
  [[ $status -eq 0 ]]
  [[ -f "${T}/.github/github-copilot-1password-hooks-bundle/bin/run-hook.sh" ]]
  [[ -d "${T}/.github/github-copilot-1password-hooks-bundle/lib" ]]
  [[ -f "${T}/.github/github-copilot-1password-hooks-bundle/adapters/_lib.sh" ]]
  [[ -f "${T}/.github/github-copilot-1password-hooks-bundle/adapters/generic.sh" ]]
  [[ -f "${T}/.github/github-copilot-1password-hooks-bundle/adapters/github-copilot.sh" ]]
  [[ ! -f "${T}/.github/github-copilot-1password-hooks-bundle/adapters/cursor.sh" ]]
  [[ -f "${T}/.github/github-copilot-1password-hooks-bundle/hooks/1password-validate-mounted-env-files/hook.sh" ]]
  [[ -f "${T}/.github/hooks/hooks.json" ]]
  [[ "$output" == *"Done. Hook(s) installed"* ]]
}

@test "github-copilot: hooks.json command path is rewritten to bundle-relative path" {
  run bash "${INSTALL_SCRIPT}" --agent github-copilot --target-dir "${T}"
  [[ $status -eq 0 ]]
  run grep -Fq '.github/github-copilot-1password-hooks-bundle/bin/run-hook.sh' "${T}/.github/hooks/hooks.json"
  [[ $status -eq 0 ]]
}

@test "github-copilot: does not overwrite existing hooks.json" {
  mkdir -p "${T}/.github/hooks"
  echo '{"version":1,"hooks":{"PreToolUse":[]}}' > "${T}/.github/hooks/hooks.json"
  run bash "${INSTALL_SCRIPT}" --agent github-copilot --target-dir "${T}"
  [[ $status -eq 0 ]]
  [[ "$output" == *"Config already exists at"* ]]
  [[ "$(cat "${T}/.github/hooks/hooks.json")" == '{"version":1,"hooks":{"PreToolUse":[]}}' ]]
}

# ---- Windsurf: install paths ----

@test "windsurf: --target-dir creates .windsurf/windsurf-1password-hooks-bundle and expected files" {
  run bash "${INSTALL_SCRIPT}" --agent windsurf --target-dir "${T}"
  [[ $status -eq 0 ]]
  [[ -f "${T}/.windsurf/windsurf-1password-hooks-bundle/bin/run-hook.sh" ]]
  [[ -d "${T}/.windsurf/windsurf-1password-hooks-bundle/lib" ]]
  [[ -f "${T}/.windsurf/windsurf-1password-hooks-bundle/adapters/_lib.sh" ]]
  [[ -f "${T}/.windsurf/windsurf-1password-hooks-bundle/adapters/windsurf.sh" ]]
  [[ -f "${T}/.windsurf/windsurf-1password-hooks-bundle/adapters/generic.sh" ]]
  [[ ! -f "${T}/.windsurf/windsurf-1password-hooks-bundle/adapters/cursor.sh" ]]
  [[ -f "${T}/.windsurf/windsurf-1password-hooks-bundle/hooks/1password-validate-mounted-env-files/hook.sh" ]]
  [[ -f "${T}/.windsurf/hooks.json" ]]
  [[ "$output" == *"Done. Hook(s) installed"* ]]
}

@test "windsurf: hooks.json command path is rewritten to bundle-relative path" {
  run bash "${INSTALL_SCRIPT}" --agent windsurf --target-dir "${T}"
  [[ $status -eq 0 ]]
  run grep -Fq '.windsurf/windsurf-1password-hooks-bundle/bin/run-hook.sh' "${T}/.windsurf/hooks.json"
  [[ $status -eq 0 ]]
}

@test "windsurf: does not overwrite existing hooks.json" {
  mkdir -p "${T}/.windsurf"
  echo '{"hooks":{"pre_run_command":[]}}' > "${T}/.windsurf/hooks.json"
  run bash "${INSTALL_SCRIPT}" --agent windsurf --target-dir "${T}"
  [[ $status -eq 0 ]]
  [[ "$output" == *"Config already exists at"* ]]
  [[ "$(cat "${T}/.windsurf/hooks.json")" == '{"hooks":{"pre_run_command":[]}}' ]]
}

# ---- Smoke: installed run-hook.sh is runnable ----

@test "cursor: installed run-hook.sh runs (smoke)" {
  run bash "${INSTALL_SCRIPT}" --agent cursor --target-dir "${T}"
  [[ $status -eq 0 ]]
  run bash -c "echo '{}' | ${T}/.cursor/cursor-1password-hooks-bundle/bin/run-hook.sh 1password-validate-mounted-env-files"
  [[ $status -eq 0 ]]
}

@test "github-copilot: installed run-hook.sh runs (smoke)" {
  run bash "${INSTALL_SCRIPT}" --agent github-copilot --target-dir "${T}"
  [[ $status -eq 0 ]]
  run bash -c "echo '{}' | ${T}/.github/github-copilot-1password-hooks-bundle/bin/run-hook.sh 1password-validate-mounted-env-files"
  [[ $status -eq 0 ]]
}

@test "windsurf: installed run-hook.sh runs (smoke)" {
  run bash "${INSTALL_SCRIPT}" --agent windsurf --target-dir "${T}"
  [[ $status -eq 0 ]]
  run bash -c "echo '{}' | ${T}/.windsurf/windsurf-1password-hooks-bundle/bin/run-hook.sh 1password-validate-mounted-env-files"
  [[ $status -eq 0 ]]
}
