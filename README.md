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

This repo includes an install script that copies hook files (bin, lib, adapters, and hooks) into your project or user directory. Clone this repo and install from this repo’s root.

### Install at project level

Install hooks for a single repo. Use `--target-dir` to point at the repo you want to install into.

```bash
./install.sh --agent cursor --scope project --target-dir /path/to/your/repo
```

- **`--agent`** — Your agent (e.g. `cursor`, `github-copilot`).
- **`--target-dir`** — Path to the target repo (e.g. `~/Projects/my-app`).

If the script says hooks are already installed, it will ask before overwriting so you don't lose any changes you made. Type `y` to continue or `n` to cancel.

### Install at user level

Install hooks under your home directory so they apply to all your projects.

```bash
./install.sh --agent cursor --scope user
```

- **`--agent`** — Your agent (e.g. `cursor`, `github-copilot`).
- No `--target-dir` needed; the script uses your home directory (e.g. `~/.cursor/1password-hooks` for Cursor, `~/.config/github-copilot/1password-hooks` for GitHub Copilot).

If the script says hooks are already installed, it will ask before overwriting so you don't lose any changes you made. Type `y` to continue or `n` to cancel.

### Config file already exists

The install script only creates the agent's config file (e.g. `hooks.json`) when it doesn't already exist. If you see a message that the config already exists, the script has copied the hook files but **has not** added or changed entries in your config.

**What to do:**

1. Open the config file at the path the script printed (e.g. `.cursor/hooks.json` or `.github/hooks.json`).
2. Add or update hook entries. Use a template in this repo as reference: [.cursor/hooks.json](./.cursor/hooks.json) or [.github/hooks.json](./.github/hooks.json).
3. Each entry should run `bin/run-hook.sh <hook-name>` for the event you want (e.g. `beforeShellExecution` for Cursor, `PreToolUse` for GitHub Copilot).
4. The path to `run-hook.sh` must be relative to the config file's directory. For project scope that's usually `1password-hooks/bin/run-hook.sh`.

**Example** (Cursor, project scope — add this inside the `"hooks"` object in your `.cursor/hooks.json`):

```json
"beforeShellExecution": [
  {
    "command": "1password-hooks/bin/run-hook.sh 1password-validate-mounted-env-files"
  }
]
```

For GitHub Copilot use the event `"PreToolUse"` and the path may differ (e.g. `1password-hooks/bin/run-hook.sh` under `.github/`). See [.github/hooks.json](./.github/hooks.json) for a full example.

### Verifying installation

1. **Hook files** — The install directory should contain `bin/run-hook.sh`, `lib/`, `adapters/`, and `hooks/`.
2. **Config** — Your agent's config file (e.g. `.cursor/hooks.json`) should include an entry that runs `run-hook.sh` with the hook name.
3. **Run it** — Use the agent as usual; the hook runs on the configured event. Check the agent's output or logs to confirm.
