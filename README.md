# 1Password Agent Hooks

This repository provides 1Password agent hooks that run inside supported IDEs and AI agents. The hooks fire on agent events (e.g. before shell or tool use) to validate, verify, and automate 1Password setup so commands run with the right secrets and config.

## Overview

1Password agent hooks validate and verify 1Password setup when supported agents run commands. They run on agent events (e.g. before shell or tool use) and help prevent errors from missing or invalid 1Password config.

Configuration is agent-specific and may use config files or editor settings. It can usually be scoped to:

- **Project-specific**: `.cursor/hooks.json` in the project root (applies only to that project)
- **User-specific**: `~/.cursor/hooks.json` or similar user configuration directory (applies to all projects for that user)
- **Global/system-level**: System-wide configuration location (applies to all users on the system)

Configuration at more specific levels (project) takes precedence over more general levels (user, global).

## Supported agents

Use the `--agent` value when running the install script:

| Agent | `--agent` value | Config location (project) | Docs |
|-------|-----------------|---------------------------|------|
| **Cursor** | `cursor` | `.cursor/hooks.json` | [Cursor Hooks](https://cursor.com/docs/agent/hooks) |
| **GitHub Copilot** | `github-copilot` | `.github/hooks.json` | [Custom agents configuration](https://docs.github.com/en/copilot/reference/custom-agents-configuration) |

User-level config lives under your home directory (e.g. `~/.cursor/` for Cursor, `~/.config/github-copilot/` for GitHub Copilot).

## Available Hooks

- [`1password-validate-mounted-env-files`](./hooks/1password-validate-mounted-env-files/README.md) - Mounted .env file Validation

## Installation

This repo includes an install script that copies hook files (bin, lib, adapters, and hooks) into a bundle. Run it from this repo’s root. The script uses `--agent` to pick paths and config for each supported agent.

- **`--agent`** (required) — The agent or IDE (e.g. `cursor`, `github-copilot`). See the table above.
- **`--target-dir`** (optional) — If set, the script installs the bundle into that path and creates the agent's config file from a template when it doesn't already exist. If unset, the script only creates the bundle in the current directory and you move it and add config yourself.

There are two ways to install:

### 1. Bundle

Create a portable bundle in the current directory (no config file). Move the folder wherever you want (e.g. a project repo or your user config directory) and add your agent's hooks config so it runs the bundle's `bin/run-hook.sh <hook-name>` for the events you need.

```bash
./install.sh --agent <agent>
```

**Examples:**

```bash
# Cursor: creates cursor-1password-hooks-bundle/ in cwd
./install.sh --agent cursor

# GitHub Copilot: creates github-copilot-1password-hooks-bundle/ in cwd
./install.sh --agent github-copilot
```

Then move that folder (e.g. into a project's `.cursor/` or `.github/`, or into `~/.cursor/` for user-level).

⚠️ When you use Bundle, the script does not create a (hooks.json). You'll need to add or update manually. See **Config File** section below.

### 2. Bundle and Move

Install the bundle into a target directory (e.g. a project repo). The script creates the bundle there and, if the agent's config file doesn't already exist, creates it from a template with the correct path to `run-hook.sh`.

```bash
./install.sh --agent <agent> --target-dir /path/to/repo
```

**Examples:**

```bash
# Cursor: installs into repo/.cursor/cursor-1password-hooks-bundle and repo/.cursor/hooks.json (if missing)
./install.sh --agent cursor --target-dir /path/to/your/repo

# GitHub Copilot: installs into repo/.github/github-copilot-1password-hooks-bundle and repo/.github/hooks.json (if missing)
./install.sh --agent github-copilot --target-dir /path/to/your/repo
```

If the install directory already exists, the script will ask before overwriting. Type `y` to continue or `n` to cancel.

⚠️ You may see a warning that a config file was not created. When you use --target-dir, the script never overwrites an existing config file. It only creates one from a template when the file is missing. See instructions below.

### Config File

For **Bundle**, the script does not create a config file. When you use **Bundle and Move**, the script only creates the agent's config file when it doesn't already exist; it never overwrites an existing config file. If you see a message that the config already exists, the script has copied the hook files but **has not** added or changed entries in your config.

**What to do:**

1. Open the config file at the path the script printed (agent-specific; see [Supported agents](#supported-agents) or the templates in this repo).
2. Add or update hook entries so they run `<bundle-name>/bin/run-hook.sh <hook-name>` for the events you want. The path is relative to the config file's directory.
3. Use this repo's templates as reference: [.cursor/hooks.json](./.cursor/hooks.json), [.github/hooks.json](./.github/hooks.json).

**Example (Cursor)** — inside the `"hooks"` object in `.cursor/hooks.json`:

```json
"beforeShellExecution": [
  {
    "command": "cursor-1password-hooks-bundle/bin/run-hook.sh 1password-validate-mounted-env-files"
  }
]
```

**Example (GitHub Copilot)** — use the event `PreToolUse` and path `github-copilot-1password-hooks-bundle/bin/run-hook.sh`. See [.github/hooks.json](./.github/hooks.json) for an example.

### Verifying installation

1. **Hook files** — The bundle directory should contain `bin/run-hook.sh`, `lib/`, `adapters/`, and `hooks/`.
2. **Config** — Your agent's config file should include an entry that runs `run-hook.sh` with the hook name.
3. **Run it** — Use the agent or IDE as usual; the hook runs on the configured event. Check the agent's output or logs to confirm.
