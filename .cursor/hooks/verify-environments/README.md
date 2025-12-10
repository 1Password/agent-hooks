# Mounted .env file Validation

The [`1password-verify-environments.sh`](./1password-verify-environments.sh) hook validates that locally mounted .env files from [1Password Environments](https://developer.1password.com/docs/environments) are properly configured and enabled before allowing shell command execution in Cursor.

## Details

### General Description

This hook ensures that required 1Password environment files are properly mounted before commands are executed by the Cursor Agent. It queries the 1Password SQLite database to discover [local .env files](https://developer.1password.com/docs/environments/local-env-file/) that have been configured within the current path and validates that they are enabled and correctly mounted as FIFO (named pipe) files. If any required .env files are missing, disabled, or invalid, the hook denies command execution and provides clear error messages to help resolve the issue.

### Recommended Event

**`beforeShellExecution`** - This hook should be configured to run before shell commands are executed to prevent commands from running when required environment files are not available.

## Functionality

The hook supports two validation modes: **default** (when no configuration is provided) and **configured** (when a TOML configuration file is present).

### Configured Mode

When a `.1password/environments.toml` file exists at the project root **and** contains a `mounts` field, the hook is considered configured. In this mode, **only** the mounts specified in the TOML file are validated, overriding the default behavior.

The hook parses the TOML file to extract mount paths from an `[[environments]]` section with a `mounts` array field:

```toml
[[environments]]
mounts = [".env", "billing.env"]
```

**Behavior:**

- If `mounts = [".env"]` is specified, only `.env` is validated within the project path
- If `mounts = []` (empty array) is specified, no local .env files are validated (all commands are allowed)
- Mount paths can be relative to the project root or absolute
- Each specified mount is validated to ensure it exists, is a valid FIFO file, and is enabled in 1Password

**Important:** The `mounts` field must be explicitly defined in the TOML file. If the file exists but doesn't contain a `mounts` field, the hook will log a warning and fall back to default mode.

### Default Mode

When no `.1password/environments.toml` file exists, or when the file exists but doesn't specify a `mounts` field, the hook uses default mode. In this mode, the hook:

1. **Detects the operating system** (macOS or Linux)
2. **Locates the 1Password SQLite database** in the standard location:
   - macOS: `~/Library/Group Containers/2BUA8C4S2C.com.1password/Library/Application Support/1Password/Data/1Password.sqlite`
   - Linux: `~/.config/1Password/1Password.sqlite` (or alternative locations for snap/flatpak installations)
3. **Queries the database** for mount configurations using SQLite
4. **Filters local .env files** relevant to the current project directory
5. **Validates all discovered local .env files** by checking:
   - Mount is enabled (`isEnabled: true`)
   - Mount file exists and is a valid FIFO (named pipe)
6. **Returns a permission decision**:
   - `allow` - All discovered local .env files are valid and enabled
   - `deny` - One or more discovered local .env files are missing, disabled, or invalid

The hook uses a "fail open" approach: if the 1Password database cannot be accessed, the hook allows execution to proceed. This prevents blocking development when 1Password is not installed or the database is unavailable.

### Validation Flow

The hook follows this decision flow:

1. **Check for `.1password/environments.toml`**

   - If file exists and contains `mounts` field → **Configured Mode**
   - If file exists but no `mounts` field → Warning logged, **Default Mode**
   - If file doesn't exist → **Default Mode**

2. **In Configured Mode:**

   - Parse `mounts` array from TOML
   - Validate only the specified mounts
   - If `mounts = []`, no validation is performed (all commands allowed)

3. **In Default Mode:**
   - Query 1Password database for all mounts
   - Filter mounts within the project directory
   - Validate all discovered mounts

### Examples

**Example 1: Configured - Single Mount**

```toml
# .1password/environments.toml
[[environments]]
mounts = [".env"]
```

Only `.env` is validated. Other mounts in the project are ignored.

**Example 2: Configured - Multiple Mounts**

```toml
# .1password/environments.toml
[[environments]]
mounts = [".env", "billing.env", "database.env"]
```

Only these three files are validated.

**Example 3: Configured - No Validation**

```toml
# .1password/environments.toml
[[environments]]
mounts = []
```

No mounts are validated. All commands are allowed.

**Example 4: Default Mode**
No `.1password/environments.toml` file exists. The hook discovers and validates all mounts configured in 1Password that are within the project directory.

### Windows Not Supported

Local .env file mounting relies on FIFO (named pipe) files, which are only supported on macOS and Linux. As a result, this feature and hook is currently unavailable on Windows platforms.

If you're on Windows, this hook will be skipped automatically.

## Configuration

Hooks are intended to be configured at the project or user-specific level. Simply add the hook file to the desired location and then configure it in the corresponding `.cursor/hooks.json` file, and the behaviour will become available. [More information here](https://cursor.com/docs/agent/hooks#configuration).

### Example Configuration

Add the following to `.cursor/hooks.json`:

```json
{
  "version": 1,
  "hooks": {
    "beforeShellExecution": [
      {
        "command": ".cursor/hooks/verify-environments/1password-verify-environments.sh"
      }
    ]
  }
}
```

### Dependencies

**Required:**

- `sqlite3` - For querying the 1Password database. Must be installed and available in your PATH.

**Standard POSIX Commands Used:**
The hook uses only standard POSIX commands that are available by default on both macOS and Linux:

- `bash` - Shell interpreter
- `grep`, `sed`, `echo`, `date`, `tr` - Text processing
- `cd`, `pwd`, `dirname`, `basename` - Path manipulation
- `printf` - Hex decoding and string formatting

The hook uses a "fail open" approach: if `sqlite3` is not available, the hook logs a warning and allows execution to proceed. This prevents blocking development when 1Password is not installed or the database is unavailable.

## Testing and Debugging

### Running Manually

You can test the hook manually by running it directly with JSON input:

```bash
# Test with a simple command
echo '{"command": "echo test", "cwd": "/path/to/project"}' | ./.cursor/hooks/verify-environments/1password-verify-environments.sh
```

The hook expects JSON input on stdin with the following format:

```json
{
  "command": "<command to be executed>",
  "cwd": "<current working directory>"
}
```

It outputs JSON to stdout:

```json
{
  "permission": "allow" | "deny",
  "agent_message": "Message shown to agent (if denied)"
}
```

**Enable Debug Mode:**

Set `DEBUG=1` to output logs directly to the shell instead of the log file:

```bash
DEBUG=1 echo '{"command": "echo test", "cwd": "/path/to/project"}' | ./.cursor/hooks/verify-environments/1password-verify-environments.sh
```

### Where to Find Logs

The hook logs information to `/tmp/1password-cursor-hooks.log` for troubleshooting. Check this file if you encounter issues.

Log entries include timestamps and detailed information about:

- Database queries and results
- Local .env file validation checks
- Permission decisions
- Error conditions
