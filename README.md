# 1Password Agent Hooks

This repository provides 1Password agent hooks that run inside supported IDEs and AI agents. The hooks fire on agent events (e.g. before shell or tool use) to validate, verify, and automate 1Password setup so commands run with the right secrets and config.

## Overview

1Password agent hooks validate and verify 1Password setup when supported agents run commands. They run on agent events (e.g. before shell or tool use) and help prevent errors from missing or invalid 1Password config.

Configuration is agent-specific and may use config files or editor settings. Scope depends on the agent:

- **Project-specific**: e.g. `.cursor/hooks.json`, `.github/hooks/hooks.json`, `.claude/settings.json`, or `.windsurf/hooks.json` in the project root (applies only to that project)

Other levels (user-specific or global) may be supported by some agents. See each agent’s documentation for details. The table below in **Supported Agents** references documentation.

## Supported agents

Use the `--agent` value when running the install script:

| Agent | `--agent` value | Docs |
|-------|-----------------|------|
| **Cursor** | `cursor` | [Cursor Hooks](https://cursor.com/docs/agent/hooks) |
| **Claude Code** | `claude-code` | [Claude Code Hooks](https://docs.anthropic.com/en/docs/claude-code/hooks) |
| **GitHub Copilot** | `github-copilot` | [Custom agents configuration](https://docs.github.com/en/copilot/how-tos/use-copilot-agents/coding-agent/use-hooks) |
| **Windsurf (Cascade)** | `windsurf` | [Cascade Hooks](https://docs.windsurf.com/windsurf/cascade/hooks) |


## Available Hooks

| Hook | Installation |
|------|--------------|
| [`1password-validate-mounted-env-files`](./hooks/1password-validate-mounted-env-files/README.md) — validates mounted `.env` files from 1Password Environments | <ul><li><strong>Cursor:</strong> <a href="https://cursor.com/marketplace/1password">1Password plugin</a> (e.g. <code>/add-plugin 1password</code>); or <a href="#installation">Installation</a> with <code>install.sh</code> (<code>--agent cursor</code>).</li><li><strong>Claude Code:</strong> <a href="#installation">Installation</a> with <code>install.sh</code> (<code>--agent claude-code</code>).</li><li><strong>GitHub Copilot:</strong> <a href="#installation">Installation</a> with <code>install.sh</code> (<code>--agent github-copilot</code>).</li><li><strong>Windsurf (Cascade):</strong> <a href="#installation">Installation</a> with <code>install.sh</code> (<code>--agent windsurf</code>).</li></ul> |

## Installation

This repo includes an install script that copies hook files (bin, lib, adapters, and hooks) into a bundle. Run it from this repo’s root. The script uses `--agent` to pick paths and config for each supported agent.

### Initial setup
1. Clone this repo.
2. Run the install script from the repo root. Choose one of the two ways below:
   - [**Bundle**](#bundle) — build in current directory and you move it and add config.
   - [**Bundle and Move**](#bundle-and-move) — install into a target directory and script can create config from a template.

#### Bundle

Create a portable bundle in the current directory (no config file). Move the folder wherever you want (e.g. a project repo or your user config directory) and add your agent's hooks config so it runs the bundle's `bin/run-hook.sh <hook-name>` for the events you need.

```bash
./install.sh --agent <agent>
```

**Examples:**

```bash
# Cursor: creates cursor-1password-hooks-bundle/ in cwd
./install.sh --agent cursor

# Claude Code: creates claude-code-1password-hooks-bundle/ in cwd
./install.sh --agent claude-code

# GitHub Copilot: creates github-copilot-1password-hooks-bundle/ in cwd
./install.sh --agent github-copilot

# Windsurf (Cascade): creates windsurf-1password-hooks-bundle/ in cwd
./install.sh --agent windsurf
```

Then move that folder into the project’s directory for your agent (e.g. `.cursor/`, `.github/`, or `.windsurf/` for Windsurf Cascade).

⚠️ When you use Bundle, the script does not create a config file(`hooks.json`). You'll need to add or update manually. See the [**Config File**](#config-file) section below.

#### Bundle and Move

Install the bundle into a target directory (e.g. a project repo). The script creates the bundle there and, if the agent's config file doesn't already exist, creates it from a template with the correct path to `run-hook.sh`.

```bash
./install.sh --agent <agent> --target-dir /path/to/repo
```

**Examples:**

```bash
# Cursor: installs into repo/.cursor/cursor-1password-hooks-bundle and repo/.cursor/hooks.json
./install.sh --agent cursor --target-dir /path/to/your/repo

# Claude Code: installs into repo/.claude/claude-code-1password-hooks-bundle and repo/.claude/settings.json
./install.sh --agent claude-code --target-dir /path/to/your/repo

# GitHub Copilot: installs into repo/.github/github-copilot-1password-hooks-bundle and repo/.github/hooks/hooks.json
./install.sh --agent github-copilot --target-dir /path/to/your/repo

# Windsurf (Cascade): installs into repo/.windsurf/windsurf-1password-hooks-bundle and repo/.windsurf/hooks.json
./install.sh --agent windsurf --target-dir /path/to/your/repo
```

If the install directory already exists, the script will ask before overwriting. Type `y` to continue or `n` to cancel.

⚠️ You may see a warning that a config file was not created. When you use `--target-dir`, the script never overwrites an existing config file. It only creates one from a template when the file is missing. See instructions below.

### Config File

For **Bundle**, the script does not create a config file. When you use **Bundle and Move**, the script only creates the agent's config file when it doesn't already exist. It never overwrites an existing config file. If you see a message that the config already exists, the script has copied the hook files but **has not** added or changed entries in your config.

**What to do:**

- **Bundle** — The script didn’t create a config file. Create it at your agent’s path (e.g. `.cursor/hooks.json`, `.github/hooks/hooks.json`, `.github/hooks/hooks.json`, or `.windsurf/hooks.json` for Windsurf Cascade), then add hook entries as in the examples below.
- **Bundle and Move** — The script did not create the config because it already existed at the target directory. Open it at the path the script printed and add or update hook entries as below.

**Steps (both):**

1. Open (or create) the config file at your agent’s path (e.g. `.cursor/hooks.json`, `.github/hooks/hooks.json`, `.github/hooks/hooks.json`, or `.windsurf/hooks.json` for Windsurf Cascade).
2. Add or update hook entries so they run `<bundle-name>/bin/run-hook.sh <hook-name>` for the events you want. The path is relative to the config file’s directory.

**Example config files:**

Cursor — `.cursor/hooks.json`:

```json
{
  "version": 1,
  "hooks": {
    "beforeShellExecution": [
      {
        "command": "cursor-1password-hooks-bundle/bin/run-hook.sh 1password-validate-mounted-env-files"
      }
    ]
  }
}
```

Claude Code — `.claude/settings.json`:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "claude-code-1password-hooks-bundle/bin/run-hook.sh 1password-validate-mounted-env-files"
          }
        ]
      }
    ]
  }
}
```

### Verifying installation

1. **Hook files** — The bundle directory should contain `bin/run-hook.sh`, `lib/`, `adapters/`, and `hooks/`.
2. **Config** — Your agent's config file should include an entry that runs `run-hook.sh` with the hook name.
3. **Run it** — Use the agent or IDE as usual. The hook runs on the configured event. Check the agent's output or logs to confirm.
