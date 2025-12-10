# 1Password Cursor Hooks

This repository contains [Cursor Hooks](https://cursor.com/docs/agent/hooks) designed to integrate with 1Password. These hooks execute at specific events emitted by Cursor to provide validation, verification, and automation for 1Password-related operations.

## Overview

1Password Cursor Hooks provide automated validation and verification of 1Password configurations and integrations. They help ensure that required 1Password resources are properly set up before commands are executed, preventing errors and security issues.

Hooks are automatically executed by Cursor when the corresponding [events](https://cursor.com/docs/agent/hooks#hook-events) occur. The hook [configuration](https://cursor.com/docs/agent/hooks#configuration) is defined in `hooks.json` and can be placed at multiple levels:

- **Project-specific**: `.cursor/hooks.json` in the project root (applies only to that project)
- **User-specific**: `~/.cursor/hooks.json` or similar user configuration directory (applies to all projects for that user)
- **Global/system-level**: System-wide configuration location (applies to all users on the system)

Configuration at more specific levels (project) takes precedence over more general levels (user, global).

## Available Hooks

- [`1password-verify-environments`](./.cursor/hooks/verify-environments/README.md) - Mounted .env file Validation
