# Environment Mount Validation

The [`1password-verify-environments.sh`](./1password-verify-environments.sh) hook validates that 1Password environment mounts are properly configured and enabled before allowing shell command execution in Cursor.

## Details

### General Description

This hook ensures that required 1Password environment files are properly mounted before commands are executed. It queries the 1Password SQLite database to discover environment mounts configured for the current project and validates that they are enabled and correctly mounted as FIFO (named pipe) files. If required environments are missing, disabled, or invalid, the hook denies command execution and provides clear error messages to help resolve the issue.

### Recommended Event

**`beforeShellExecution`** - This hook should be configured to run before shell commands are executed to prevent commands from running when required environment files are not available.

## Functionality

### Default Behaviour

The hook operates by:

1. **Detecting the operating system** (macOS or Linux)
2. **Locating the 1Password SQLite database** in the standard location:
   - macOS: `~/Library/Group Containers/2BUA8C4S2C.com.1password/Library/Application Support/1Password/Data/1Password.sqlite`
   - Linux: `~/.config/1Password/1Password.sqlite` (or alternative locations for snap/flatpak installations)
3. **Querying the database** for environment mount configurations using SQLite
4. **Filtering mounts** relevant to the current project directory
5. **Validating mounts** by checking:
   - Mount is enabled (`isEnabled: true`)
   - Mount file exists and is a valid FIFO (named pipe)
6. **Returning a permission decision**:
   - `allow` - All required mounts are valid and enabled
   - `deny` - One or more required mounts are missing, disabled, or invalid

The hook uses a "fail open" approach: if the 1Password database cannot be accessed, the hook allows execution to proceed. This prevents blocking development when 1Password is not installed or the database is unavailable.

### Required Mounts

In addition to checking mounts discovered from the 1Password database, the hook also validates mounts specified in an `.1password/environments.toml` file at the project root. This allows projects to explicitly declare required environment files that must be mounted.

The hook parses the TOML file to extract mount paths from `[[environments]]` sections with `mounts` arrays:

```toml
[[environments]]
mounts = ["application.env", "billing.env"]
```

Mount paths can be relative to the project root or absolute. The hook validates that each required mount exists and is a valid FIFO file.

### Windows Not Supported

Local environment file mounting relies on FIFO (named pipe) files, which are only supported on macOS and Linux. As a result, this feature and hook is currently unavailable on Windows platforms.

If you're on Windows, this hook will be skipped automatically.

## Configuration

Hooks can be configured at the project or system level. Simply add the hook file to the desired location and then configure it in the corresponding `.cursor/hooks.json` file, and the behaviour will become available. [More information here.](https://cursor.com/docs/agent/hooks#configuration)

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
- Mount validation checks
- Permission decisions
- Error conditions
