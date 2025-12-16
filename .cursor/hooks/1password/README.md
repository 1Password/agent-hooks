# Cursor Hook: Local .env File Validation for 1Password Environments

This directory includes a hook that validates locally mounted .env files from [1Password Environments](https://developer.1password.com/docs/environments) to make sure they're properly mounted. The hook automatically discovers configured .env files and prevents command execution in Cursor when required files are missing or invalid.

## Details

### General Description

Every time Cursor attempts to execute a shell command, the [`validate-mounted-env-files.sh`](./validate-mounted-env-files.sh) script will run and query 1Password for your configured [local .env files](https://developer.1password.com/docs/environments/local-env-file). It will then validate that each file is enabled, and exists as a valid FIFO (named pipe). When validation fails, the hook blocks command execution and provides clear error messages indicating which files are missing or need to be enabled from the 1Password app. The Cursor Agent will then guide you towards a proper configuration.

Note: [Local .env files](https://developer.1password.com/docs/environments/local-env-file) from 1Password Environments are only available on Mac and Linux. Windows is not yet supported. If you're on Windows, Cursor will automatically skip any validations.

### Intended Cursor Event

This hook is intended to be used with the **`beforeShellExecution`** event. When configured with this event, the hook runs before Cursor executes any commands, preventing the Agent from running when required environment files are not available.

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

Hooks can be configured at multiple levels. To do this, add the hook file to the desired location and then configure it in the corresponding `hooks.json` file, and the behavior will become available:

- **Project-specific**: `.cursor/hooks.json` in the project root (applies only to that project).
- **User-specific**: `~/.cursor/hooks.json` or similar user configuration directory (applies to all projects for that user).
- **Global/system-level**: System-wide configuration location (applies to all users on the system).

Configuration at more specific levels (project) takes precedence over more general levels (user, global). [More information here](https://cursor.com/docs/agent/hooks#configuration).

### Example Configuration

Add the following to `hooks.json` within your project:

```json
{
  "version": 1,
  "hooks": {
    "beforeShellExecution": [
      {
        "command": ".cursor/hooks/1password/validate-mounted-env-files.sh"
      }
    ]
  }
}
```

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

### Cursor Execution Log

The easiest way to see if the hook is running and view its output is through Cursor's execution log:

1. Open **Settings** > **Hooks** > **Execution Log**.
2. Look for entries related to `beforeShellExecution` and `validate-mounted-env-files.sh`.
3. Each entry shows whether the hook ran successfully, its output, and any error messages.

This log helps you verify that:

- The hook is being called by Cursor.
- The hook is returning the expected permission decisions.
- Any error messages from the hook execution.

### Manual Testing with Debug Mode

You can manually run the hook in debug mode to see detailed logs directly in your terminal. This is useful for troubleshooting configuration issues or understanding the hook's behavior.

The hook expects JSON input on stdin with the following format:

```json
{
  "command": "<command to be executed>",
  "workspace_roots": ["<workspace root path>"]
}
```

Run the hook with `DEBUG=1` to output logs directly to the shell:

```bash
DEBUG=1 echo '{"command": "echo test", "workspace_roots": ["/path/to/project"]}' | ./.cursor/hooks/1password/validate-mounted-env-files.sh
```

The hook outputs JSON to stdout:

```json
{
  "permission": "allow" | "deny",
  "agent_message": "Message shown to agent (if denied)"
}
```

### Where to Find Logs

When not running the script manually in debug mode, the hook logs information to `/tmp/1password-cursor-hooks.log` for troubleshooting. Check this file if you encounter issues.

Log entries include timestamps and detailed information about:

- 1Password queries and results.
- Local .env file validation checks.
- Permission decisions.
- Error conditions.
