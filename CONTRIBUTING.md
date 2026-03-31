# Contributing to 1Password Agent Hooks

Thanks for your interest in contributing to the 1Password Agent Hooks project! 🙌 We appreciate your time and effort. Here are some guidelines to help you get started.

## Scope

This repository ships **1Password agent hooks** for supported IDEs/agents (e.g. Cursor, GitHub Copilot). Hooks run on agent events (such as before shell or tool use) and are installed via `install.sh` from the repo root. For user-facing install and config steps, see [README.md](README.md).

## Getting started

1. Fork and clone the repository.
2. Install [Bats](https://github.com/bats-core/bats-core) (the test suite uses Bats).
3. From the repo root, run the full test suite (see below).

## Running tests

Run all tests:

```bash
bats -r tests/
```

## Conventions

- New hooks: Put them in `hooks/<hook-name>/` with a README that covers behavior, which agent events to use, and known limits.
- Shipping a hook: Update `install-client-config.json` (and confirm `install.sh` works. e.g ./`install.sh --agent cursor --target-dir /path/to/your/repo`).
- Tests: Add Bats tests for changes or new additions.
