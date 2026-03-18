# Hook: Local .env File Validation for 1Password Environments

This hook validates locally mounted .env files from [1Password Environments](https://developer.1password.com/docs/environments) to make sure they're properly mounted. It automatically discovers configured .env files and prevents command or tool execution when required files are missing or invalid. It works with supported agents and is invoked via `bin/run-hook.sh 1password-validate-mounted-env-files` (implementation is in [`hook.sh`](./hook.sh)).

## Details

### General Description

When the agent runs the hook, it executes and queries 1Password for your configured [local .env files](https://developer.1password.com/docs/environments/local-env-file). It validates that each file is enabled and exists as a valid FIFO (named pipe). When validation fails, the hook blocks execution and provides clear error messages indicating which files are missing or need to be enabled from the 1Password app. The agent will then guide you towards a proper configuration.

Note: [Local .env files](https://developer.1password.com/docs/environments/local-env-file) from 1Password Environments are only available on Mac and Linux. Windows is not yet supported. If you're on Windows, the hook will skip any validations.

### Intended Events

Use with the event that runs before shell command execution in your agent. When configured, the hook prevents the agent from proceeding when required environment files are not available.

**Examples (event name depends on your agent):** `beforeShellExecution` (e.g. Cursor), `PreToolUse` (e.g. GitHub Copilot).

## Functionality

The hook supports two validation modes: **configured** (when a TOML configuration file is present and properly defined) and **default** (when no configuration is provided).

### Configured Mode

When a `.1password/environments.toml` file exists at the project root **and** contains a `mount_paths` field, the hook is considered configured. In this mode, **only** the files specified in the TOML file are validated, overriding the default behavior.

The hook parses the TOML file to extract paths from a top-level `mount_paths` array field:

```toml
mount_paths = [".env", "billing.env"]
```

**Behavior:**

- If `mount_paths = [".env"]` is specified, only `.env` is validated within the project path.
- If `mount_paths = []` (empty array) is specified, no local .env files are validated (all commands are allowed).
- Mount paths can be relative to the project root or absolute.
- Each specified file is validated to ensure it exists, is a valid FIFO file, and is enabled in 1Password.

**Important:** The `mount_paths` field must be explicitly defined in the TOML file. If the file exists but doesn't contain a `mount_paths` field, the hook will log a warning and fall back to default mode.

### Default Mode

When no `.1password/environments.toml` file exists, or when the file exists but doesn't specify a `mount_paths` field, the hook uses default mode. In this mode, the hook:

1. **Detects the operating system** (macOS or Linux).
2. **Queries 1Password** for mount configurations.
3. **Filters local .env files** relevant to the current project directory.
4. **Validates all discovered local .env files** by checking:
   - The mounted file is enabled.
   - The mounted file exists as a valid FIFO (named pipe).
5. **Returns a permission decision**:
   - `allow` - All discovered local .env files are valid and enabled.
   - `deny` - One or more discovered local .env files are missing, disabled, or invalid.

The hook uses a "fail open" approach: if 1Password can't access local .env file data, the hook allows execution to proceed. This prevents blocking development when 1Password is not installed or unexpected errors occur.

### Validation Flow

The hook follows this decision flow:

1. **Check for `.1password/environments.toml`**

   - If file exists and contains `mount_paths` field → **Configured Mode**.
   - If file exists but no `mount_paths` field → Warning logged, **Default Mode**.
   - If file doesn't exist → **Default Mode**.

2. **In Configured Mode:**

   - Parse `mount_paths` array from TOML.
   - Validate only the specified files.
   - If `mount_paths = []`, no validation is performed (all commands allowed).

3. **In Default Mode:**
   - Query 1Password for all local .env files.
   - Filter them by the project directory.
   - Validate that they're properly configured.

### Examples

**Example 1: Configured - Single Mount**

```toml
# .1password/environments.toml
mount_paths = [".env"]
```

Only `.env` is validated. Other files in the project are ignored.

**Example 2: Configured - Multiple Files**

```toml
# .1password/environments.toml
mount_paths = [".env", "billing.env", "database.env"]
```

Only these three files are validated.

**Example 3: Configured - No Validation**

```toml
# .1password/environments.toml
mount_paths = []
```

No files are validated. All commands are allowed.

**Example 4: Default Mode**
No `.1password/environments.toml` file exists. The hook discovers and validates all files configured in 1Password that are within the project directory.

## Configuration

Install the hook using the repo's [install script](../../README.md#installation). It copies the hook and configures the agent's config file when missing. Config location is agent-specific.

### Example Configuration

The command must run `run-hook.sh` with the hook name. The path to `run-hook.sh` is relative to the config file's directory (e.g. `cursor-1password-hooks-bundle/bin/run-hook.sh` for project scope). Example (e.g. Cursor — `.cursor/hooks.json`):

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

For other agents, use the event and config path for your agent. See [.github/hooks/hooks.json](../../.github/hooks/hooks.json) in this repo for another example.

### Dependencies

**Required:**

- `sqlite3` - For querying 1Password. Must be installed and available in your PATH.

**Standard POSIX Commands Used:**
The hook uses only standard POSIX commands that are available by default on both macOS and Linux:

- `bash` - Shell interpreter.
- `grep`, `sed`, `echo`, `date`, `tr` - Text processing.
- `cd`, `pwd`, `dirname`, `basename` - Path manipulation.
- `printf` - Hex decoding and string formatting.

The hook uses a "fail open" approach: if `sqlite3` is not available, the hook logs a warning and allows execution to proceed. This prevents blocking development when 1Password is not installed or the database is unavailable.

## Debugging

If the hook is not working as expected, there are several ways to gather more information about what's happening.

### Agent Execution Log

The easiest way to see if the hook is running is through your agent's execution or hooks log. Look for entries related to `run-hook.sh` or `1password-validate-mounted-env-files`. (For example, in Cursor: **Settings** > **Hooks** > **Execution Log**.) Each entry shows whether the hook ran successfully, its output, and any error messages.

### Manual Testing with Debug Mode

You can run the hook manually via the runner to see output in your terminal. Run from the repo root (or use the installed path to `run-hook.sh`). The runner expects the agent's raw JSON on stdin (format may vary by agent). Example input (e.g. Cursor-style):

```json
{
  "command": "<command to be executed>",
  "workspace_roots": ["<workspace root path>"]
}
```

Example command (repo root; use your installed path if you installed elsewhere):

```bash
echo '{"command": "echo test", "workspace_roots": ["/path/to/project"]}' | ./bin/run-hook.sh 1password-validate-mounted-env-files
```

With `DEBUG=1` in the environment, the hook may output extra logs. The runner outputs the agent's expected JSON to stdout (e.g. `{"permission": "allow"}` or `{"permission": "deny", "agent_message": "..."}`).

### Where to Find Logs

When not running the hook manually, it may log to `/tmp/1password-hooks.log` (or the path in `LOG_FILE` if set) for troubleshooting. Check that path or the agent's log directory if you encounter issues.

Log entries include timestamps and detailed information about:

- 1Password queries and results.
- Local .env file validation checks.
- Permission decisions.
- Error conditions.
