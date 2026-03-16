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

@test "install.sh invalid --scope exits non-zero" {
  run bash "${INSTALL_SCRIPT}" --agent cursor --scope invalid --target-dir "${T}"
  [[ $status -ne 0 ]]
  [[ "$output" == *"must be 'user' or 'project'"* ]]
}

@test "install.sh nonexistent --target-dir exits non-zero" {
  run bash "${INSTALL_SCRIPT}" --agent cursor --target-dir "${T}/nonexistent"
  [[ $status -ne 0 ]]
  [[ "$output" == *"does not exist"* ]]
}

# ---- Cursor: install paths ----

@test "cursor: --target-dir creates .cursor/agent-hooks and expected files" {
  run bash "${INSTALL_SCRIPT}" --agent cursor --target-dir "${T}"
  [[ $status -eq 0 ]]
  [[ -f "${T}/.cursor/agent-hooks/bin/run-hook.sh" ]]
  [[ -d "${T}/.cursor/agent-hooks/lib" ]]
  [[ -n "$(echo "${T}"/.cursor/agent-hooks/lib/*.sh)" ]]
  [[ -f "${T}/.cursor/agent-hooks/adapters/_lib.sh" ]]
  [[ -f "${T}/.cursor/agent-hooks/adapters/cursor.sh" ]]
  [[ -f "${T}/.cursor/agent-hooks/adapters/generic.sh" ]]
  [[ -f "${T}/.cursor/agent-hooks/hooks/1password-validate-mounted-env-files/hook.sh" ]]
  [[ ! -f "${T}/.cursor/hooks.json" ]]
  [[ "$output" == *"Config path:"* ]]
  [[ "$output" == *"Done. Add hook entries to your config yourself."* ]]
}

@test "cursor: --scope project (cwd) creates .cursor/agent-hooks" {
  run bash -c "cd '${T}' && bash '${INSTALL_SCRIPT}' --agent cursor --scope project"
  [[ $status -eq 0 ]]
  [[ -f "${T}/.cursor/agent-hooks/bin/run-hook.sh" ]]
  [[ -f "${T}/.cursor/agent-hooks/adapters/cursor.sh" ]]
  [[ -f "${T}/.cursor/agent-hooks/hooks/1password-validate-mounted-env-files/hook.sh" ]]
  [[ ! -f "${T}/.cursor/hooks.json" ]]
}

@test "cursor: --scope user (HOME) creates .cursor/agent-hooks under HOME" {
  run env HOME="${T}" bash "${INSTALL_SCRIPT}" --agent cursor --scope user
  [[ $status -eq 0 ]]
  [[ -f "${T}/.cursor/agent-hooks/bin/run-hook.sh" ]]
  [[ -f "${T}/.cursor/agent-hooks/adapters/cursor.sh" ]]
  [[ -f "${T}/.cursor/agent-hooks/hooks/1password-validate-mounted-env-files/hook.sh" ]]
  [[ ! -f "${T}/.cursor/hooks.json" ]]
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
      "install_dir": ".cursor/agent-hooks",
      "config_path": ".cursor/hooks.json"
    }
  }
}
EOF
  run bash "${repo}/install.sh" --agent cursor --scope project --target-dir "${T}"
  [[ $status -eq 0 ]]
  [[ -f "${T}/.cursor/agent-hooks/hooks/hook-a/hook.sh" ]]
  [[ -f "${T}/.cursor/agent-hooks/hooks/hook-b/hook.sh" ]]
}

# ---- GitHub Copilot: install paths ----

@test "github-copilot: --target-dir creates .github/agent-hooks and expected files" {
  run bash "${INSTALL_SCRIPT}" --agent github-copilot --target-dir "${T}"
  [[ $status -eq 0 ]]
  [[ -f "${T}/.github/agent-hooks/bin/run-hook.sh" ]]
  [[ -d "${T}/.github/agent-hooks/lib" ]]
  [[ -f "${T}/.github/agent-hooks/adapters/_lib.sh" ]]
  [[ -f "${T}/.github/agent-hooks/adapters/generic.sh" ]]
  [[ -f "${T}/.github/agent-hooks/adapters/github-copilot.sh" ]]
  [[ ! -f "${T}/.github/agent-hooks/adapters/cursor.sh" ]]
  [[ -f "${T}/.github/agent-hooks/hooks/1password-validate-mounted-env-files/hook.sh" ]]
  [[ ! -f "${T}/.github/hooks.json" ]]
  [[ "$output" == *"Done. Add hook entries to your config yourself."* ]]
}

@test "github-copilot: --scope project (cwd) creates .github/agent-hooks" {
  run bash -c "cd '${T}' && bash '${INSTALL_SCRIPT}' --agent github-copilot --scope project"
  [[ $status -eq 0 ]]
  [[ -f "${T}/.github/agent-hooks/bin/run-hook.sh" ]]
  [[ -f "${T}/.github/agent-hooks/adapters/github-copilot.sh" ]]
  [[ -f "${T}/.github/agent-hooks/hooks/1password-validate-mounted-env-files/hook.sh" ]]
  [[ ! -f "${T}/.github/hooks.json" ]]
}

@test "github-copilot: --scope user (HOME) creates .config/github-copilot/agent-hooks" {
  run env HOME="${T}" bash "${INSTALL_SCRIPT}" --agent github-copilot --scope user
  [[ $status -eq 0 ]]
  [[ -f "${T}/.config/github-copilot/agent-hooks/bin/run-hook.sh" ]]
  [[ -f "${T}/.config/github-copilot/agent-hooks/adapters/github-copilot.sh" ]]
  [[ -f "${T}/.config/github-copilot/agent-hooks/hooks/1password-validate-mounted-env-files/hook.sh" ]]
  [[ ! -f "${T}/.config/github-copilot/hooks.json" ]]
}

# ---- Smoke: installed run-hook.sh is runnable ----

@test "cursor: installed run-hook.sh runs (smoke)" {
  run bash "${INSTALL_SCRIPT}" --agent cursor --target-dir "${T}"
  [[ $status -eq 0 ]]
  run bash -c "echo '{}' | ${T}/.cursor/agent-hooks/bin/run-hook.sh 1password-validate-mounted-env-files"
  [[ $status -eq 0 ]]
}

@test "github-copilot: installed run-hook.sh runs (smoke)" {
  run bash "${INSTALL_SCRIPT}" --agent github-copilot --target-dir "${T}"
  [[ $status -eq 0 ]]
  run bash -c "echo '{}' | ${T}/.github/agent-hooks/bin/run-hook.sh 1password-validate-mounted-env-files"
  [[ $status -eq 0 ]]
}
