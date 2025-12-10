#!/bin/bash

set -euo pipefail

# ============================================================================
# TABLE OF CONTENTS
# ============================================================================
#
# - Script Header & Configuration
# - Global Variables
# - Core Utility Functions (logging, JSON escaping)
# - System & Path Utility Functions (OS detection, path normalization)
# - 1Password Database Functions (finding and querying database)
# - Mount Parsing & Validation Functions (parsing mount data, validation)
# - TOML Parsing Functions
# - Main Execution Logic
# - Permission Decision Logic
#
# ============================================================================

# ============================================================================
# SCRIPT HEADER & CONFIGURATION
# ============================================================================

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# ============================================================================
# GLOBAL VARIABLES
# ============================================================================

# Array of "mount_path|environment_name"
# Local .env files that are created but not enabled in 1Password.
disabled_mounts=()

# Array of "mount_path|environment_name"
# Local .env files that are created but not valid (file is not present or not a FIFO).
invalid_mounts=()

# Array of mount paths
# Local .env files that are required by TOML but missing or invalid.
required_mounts=()

# The final permission decision to return to Cursor.
permission="allow"
# The message for the agent to interpret if the permission is denied.
agent_message=""

# ============================================================================
# CORE UTILITY FUNCTIONS
# ============================================================================

# Log function for debugging
log() {
    local timestamp
    timestamp=$(date +"%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "$(date +%s)")
    local log_message="[${timestamp}] [verify-environments] $*"
    
    if [[ "${DEBUG:-}" == "1" ]]; then
        # If DEBUG=1, echo directly to terminal (stderr for logs)
        echo "$log_message" >&2
    else
        # Otherwise, send to log file
        local log_file="/tmp/1password-cursor-hooks.log"
        # Ensure log file is writable (create if needed, ignore errors if we can't write)
        echo "$log_message" >> "$log_file" 2>/dev/null || true
    fi
}

# Escape JSON string value (returns escaped string without quotes)
escape_json_string() {
    local str="$1"
    # JSON string escaping (handles most common cases)
    # Escape backslashes, quotes, and control characters
    str=$(echo "$str" | sed 's/\\/\\\\/g')
    str=$(echo "$str" | sed 's/"/\\"/g')
    str=$(echo "$str" | sed 's/\n/\\n/g')
    str=$(echo "$str" | sed 's/\r/\\r/g')
    str=$(echo "$str" | sed 's/\t/\\t/g')
    echo "$str"
}

# Output JSON response with permission decision
output_response() {
    log "Decision: $permission"
    if [[ "$permission" == "deny" ]]; then
        log "Agent message: $agent_message"

        agent_msg_json=$(escape_json_string "$agent_message")

        cat << EOF
{
  "permission": "deny",
  "agent_message": "$agent_msg_json"
}
EOF
    else
        cat << EOF
{
  "permission": "allow"
}
EOF
    fi
}

# ============================================================================
# SYSTEM & PATH UTILITY FUNCTIONS
# ============================================================================

# Detect operating system
detect_os() {
    case "$(uname -s)" in
        Darwin*)
            echo "macos"
            ;;
        Linux*)
            echo "unix"
            ;;
        *)
            log "Warning: Unsupported OS: $(uname -s)"
            echo "unknown"
            ;;
    esac
}

# Normalize path for cross-platform compatibility
normalize_path() {
    local path="$1"
    local normalized
    
    # Normalize a given path using cd
    # This resolves . and .. components and symlinks for existing paths
    if [[ -d "$path" ]]; then
        # For directories, use cd to resolve
        normalized=$(cd "$path" && pwd 2>/dev/null)
        if [[ -n "$normalized" ]]; then
            echo "$normalized"
            return 0
        fi
    elif [[ -f "$path" ]] || [[ -p "$path" ]]; then
        # For files/FIFOs, resolve the directory part
        local dir_part file_part
        dir_part=$(dirname "$path")
        file_part=$(basename "$path")
        if [[ -d "$dir_part" ]]; then
            normalized_dir=$(cd "$dir_part" && pwd 2>/dev/null)
            if [[ -n "$normalized_dir" ]]; then
                echo "${normalized_dir}/${file_part}"
                return 0
            fi
        fi
    fi
    
    # Last resort: return path as-is
    echo "$path"
}

# ============================================================================
# 1PASSWORD DATABASE FUNCTIONS
# ============================================================================

# Find 1Password database based on operating system
find_1password_db() {
    local os_type="$1"
    local home_path="${HOME}"
    local db_paths=()
    
    if [[ "$os_type" == "macos" ]]; then
        db_paths=(
            "${home_path}/Library/Group Containers/2BUA8C4S2C.com.1password/Library/Application Support/1Password/Data/1Password.sqlite"
        )
    elif [[ "$os_type" == "unix" ]]; then
        db_paths=(
            "${home_path}/.config/1Password/1Password.sqlite"
            "${home_path}/snap/1password/current/.config/1Password/1Password.sqlite"
            "${home_path}/.var/app/com.onepassword.OnePassword/config/1Password/1Password.sqlite"
        )
    fi
    
    for db_path in "${db_paths[@]}"; do
        if [[ -f "$db_path" ]]; then
            echo "$db_path"
            return 0
        fi
    done
    
    return 1
}

# Query 1Password database for mounts
query_mounts() {
    local db_path="$1"
    
    if ! command -v sqlite3 &> /dev/null; then
        log "Warning: sqlite3 not found, cannot query 1Password database"
        return 1
    fi
    
    # Check if database is readable
    if [[ ! -r "$db_path" ]]; then
        log "Warning: 1Password database is not readable: ${db_path}"
        return 1
    fi
    
    # Check if database file exists and is a valid SQLite database
    if ! sqlite3 "$db_path" "SELECT 1;" &>/dev/null; then
        log "Warning: 1Password database appears to be invalid or locked: ${db_path}"
        return 1
    fi
    
    # Query for mount entries
    # Suppress errors but capture output
    local result
    result=$(sqlite3 "$db_path" "SELECT hex(data) FROM objects_associated WHERE key_name LIKE 'dev-environment-mount/%';" 2>/dev/null)
    local exit_code=$?
    
    if [[ $exit_code -ne 0 ]]; then
        log "Warning: Failed to query 1Password database (exit code: $exit_code)"
        return 1
    fi
    
    # Return result even if empty (empty string is valid - means no mounts)
    echo "$result"
    return 0
}

# ============================================================================
# MOUNT PARSING & VALIDATION FUNCTIONS
# ============================================================================

# Check if mount path is within project
is_project_mount() {
    local mount_path="$1"
    local project_path="$2"
    
    # Normalize paths for comparison
    local normalized_mount normalized_project
    
    normalized_mount=$(normalize_path "$mount_path")
    normalized_project=$(normalize_path "$project_path")
    
    # Ensure both paths end with / for consistent comparison
    [[ "$normalized_project" != */ ]] && normalized_project="${normalized_project}/"
    
    # Check if mount path starts with project path (mount is within project)
    # Also check original paths in case normalization failed
    if [[ "$normalized_mount" == "$normalized_project"* ]] || \
       [[ "$normalized_mount" == "$project_path" ]] || \
       [[ "$mount_path" == "$project_path"* ]] || \
       [[ "$mount_path" == "$project_path" ]]; then
        return 0
    fi
    
    return 1
}

# Decode hex string to JSON
hex_to_json() {
    local hex="$1"
    # Remove any whitespace/newlines
    hex=$(echo "$hex" | tr -d '[:space:]')
    
    # Skip if empty
    [[ -z "$hex" ]] && return 1
    
    # Use printf with escaped hex
    # Convert hex pairs to \x escaped format
    local escaped_hex decoded
    escaped_hex=$(echo "$hex" | sed 's/\(..\)/\\x\1/g')

    decoded=$(printf "%b" "$escaped_hex" 2>/dev/null || echo "")
    if [[ -n "$decoded" ]] && [[ "$decoded" != "$escaped_hex" ]]; then
        echo "$decoded"
        return 0
    fi
    
    return 1
}

# Parse mount JSON, extract mount path, enabled status, environment name, uuid, and environmentUuid
parse_mount() {
    local hex_data="$1"
    local json_data
    
    json_data=$(hex_to_json "$hex_data")
    
    if [[ -z "$json_data" ]]; then
        return 1
    fi
    
    # Extract mountPath, isEnabled, environmentName, uuid, and environmentUuid from JSON
    # Note: This may not handle all JSON edge cases (escaped quotes, etc.)
    # but should work for typical 1Password mount JSON structures
    local mount_path is_enabled environment_name uuid environment_uuid
    
    # Extract mountPath - handle both BSD and GNU sed
    mount_path=$(echo "$json_data" | grep -oE '"mountPath"[[:space:]]*:[[:space:]]*"[^"]*"' | sed -E 's/.*"mountPath"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/' 2>/dev/null || \
                 echo "$json_data" | grep -o '"mountPath"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"mountPath"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' 2>/dev/null || echo "")
    
    # Check for isEnabled: true or false
    if echo "$json_data" | grep -qE '"isEnabled"[[:space:]]*:[[:space:]]*true'; then
        is_enabled="true"
    else
        is_enabled="false"
    fi
    
    # Extract environmentName - handle both BSD and GNU sed
    environment_name=$(echo "$json_data" | grep -oE '"environmentName"[[:space:]]*:[[:space:]]*"[^"]*"' | sed -E 's/.*"environmentName"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/' 2>/dev/null || \
                      echo "$json_data" | grep -o '"environmentName"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"environmentName"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' 2>/dev/null || echo "")
    
    # Extract uuid - handle both BSD and GNU sed
    uuid=$(echo "$json_data" | grep -oE '"uuid"[[:space:]]*:[[:space:]]*"[^"]*"' | sed -E 's/.*"uuid"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/' 2>/dev/null || \
           echo "$json_data" | grep -o '"uuid"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"uuid"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' 2>/dev/null || echo "")
    
    # Extract environmentUuid - handle both BSD and GNU sed
    environment_uuid=$(echo "$json_data" | grep -oE '"environmentUuid"[[:space:]]*:[[:space:]]*"[^"]*"' | sed -E 's/.*"environmentUuid"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/' 2>/dev/null || \
                      echo "$json_data" | grep -o '"environmentUuid"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"environmentUuid"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' 2>/dev/null || echo "")
    
    if [[ -n "$mount_path" ]]; then
        echo "$mount_path|$is_enabled|$environment_name|$uuid|$environment_uuid"
        return 0
    fi
    
    return 1
}

# ============================================================================
# TOML PARSING FUNCTIONS
# ============================================================================

# Parse TOML file and extract mount paths from environments entries
# Returns newline-separated list of mount paths
parse_toml_mounts() {
    local toml_file="$1"
    
    if [[ ! -f "$toml_file" ]]; then
        return 1
    fi
    
    # Pure bash TOML parsing for environments entries
    # Handles formats like:
    #   mounts = [".env", "billing.env"]
    #   mounts = [
    #     ".env",
    #     "billing.env"
    #   ]
    local in_environments=false
    local in_mounts_array=false
    local mount_paths=""
    local array_content=""
    
    while IFS= read -r line || [[ -n "$line" ]]; do
        # Remove comments (everything after #)
        line="${line%%#*}"
        # Trim leading/trailing whitespace
        line=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        
        # Skip empty lines
        [[ -z "$line" ]] && continue
        
        # Check if we're entering an environments section
        if [[ "$line" =~ ^\[\[environments\]\] ]]; then
            in_environments=true
            in_mounts_array=false
            array_content=""
            continue
        fi
        
        # If we hit another section header, we're no longer in environments
        if [[ "$line" =~ ^\[\[.*\]\] ]] || [[ "$line" =~ ^\[.*\] ]]; then
            in_environments=false
            in_mounts_array=false
            array_content=""
            continue
        fi
        
        # Only process if we're in an environments section
        if [[ "$in_environments" == "true" ]]; then
            # Check for mounts = [...] on a single line
            if [[ "$line" =~ ^mounts[[:space:]]*=[[:space:]]*\[.*\] ]]; then
                # Extract content between [ and ]
                local array_part="${line#*\[}"
                array_part="${array_part%\]*}"
                array_content="$array_part"
                in_mounts_array=false  # Array is complete on one line
                
                # Extract quoted strings from the array content
                while [[ "$array_content" =~ \"([^\"]+)\" ]]; do
                    mount_paths="${mount_paths}${BASH_REMATCH[1]}"$'\n'
                    # Remove the matched string and any following comma/whitespace
                    array_content="${array_content#*\"${BASH_REMATCH[1]}\"}"
                    array_content=$(echo "$array_content" | sed 's/^[[:space:]]*,[[:space:]]*//;s/^[[:space:]]*//')
                done
            # Check for mounts = [ (multi-line array start)
            elif [[ "$line" =~ ^mounts[[:space:]]*=[[:space:]]*\[ ]]; then
                in_mounts_array=true
                # Extract any content after the opening [
                array_content="${line#*\[}"
                array_content=$(echo "$array_content" | sed 's/^[[:space:]]*//')
                # If array closes on same line, process it
                if [[ "$array_content" =~ \] ]]; then
                    array_content="${array_content%\]*}"
                    while [[ "$array_content" =~ \"([^\"]+)\" ]]; do
                        mount_paths="${mount_paths}${BASH_REMATCH[1]}"$'\n'
                        array_content="${array_content#*\"${BASH_REMATCH[1]}\"}"
                        array_content=$(echo "$array_content" | sed 's/^[[:space:]]*,[[:space:]]*//;s/^[[:space:]]*//')
                    done
                    in_mounts_array=false
                    array_content=""
                fi
            # If we're in a mounts array, collect lines until we hit ]
            elif [[ "$in_mounts_array" == "true" ]]; then
                # Check if this line closes the array
                if [[ "$line" =~ \] ]]; then
                    # Extract content before the closing ]
                    local line_content="${line%\]*}"
                    array_content="${array_content} ${line_content}"
                    # Process the complete array content
                    while [[ "$array_content" =~ \"([^\"]+)\" ]]; do
                        mount_paths="${mount_paths}${BASH_REMATCH[1]}"$'\n'
                        array_content="${array_content#*\"${BASH_REMATCH[1]}\"}"
                        array_content=$(echo "$array_content" | sed 's/^[[:space:]]*,[[:space:]]*//;s/^[[:space:]]*//')
                    done
                    in_mounts_array=false
                    array_content=""
                else
                    # Add this line to array content
                    array_content="${array_content} ${line}"
                fi
            fi
        fi
    done < "$toml_file"
    
    # Remove trailing newline and return
    if [[ -n "$mount_paths" ]]; then
        mount_paths=$(echo "$mount_paths" | sed '/^$/d')
        if [[ -n "$mount_paths" ]]; then
            echo "$mount_paths"
            return 0
        fi
    fi
    
    return 1
}

# ============================================================================
# MAIN EXECUTION LOGIC
# ============================================================================

# Query 1Password database and check mounts
log "Checking for local .env files mounted by 1Password..."
log "Project root: $PROJECT_ROOT"

os_type=$(detect_os)

if [[ "$os_type" == "unknown" ]]; then
    log "Unsupported OS, skipping remaining hook"
else
    log "Attempting to access 1Password database..."

    db_path=$(find_1password_db "$os_type")
    if [[ -z "$db_path" ]]; then
        log "1Password database not found, skipping remaining hook"
    else
        log "1Password database found: $db_path"

        # Query for mounts
        mount_hex_data=$(query_mounts "$db_path")

        if [[ -z "$mount_hex_data" ]]; then
            log "No local .env files found in 1Password database, skipping remaining hook"
        else
            log "Environment mount data found, checking relevant local .env files..."

            # Process each mount entry
            while IFS= read -r hex_line || [[ -n "$hex_line" ]]; do
                [[ -z "$hex_line" ]] && continue
                
                mount_info=$(parse_mount "$hex_line")
                if [[ -n "$mount_info" ]]; then
                    # Parse mount_info: mount_path|is_enabled|environment_name|uuid|environment_uuid
                    mount_path="${mount_info%%|*}"
                    remaining="${mount_info#*|}"
                    is_enabled="${remaining%%|*}"
                    remaining="${remaining#*|}"
                    environment_name="${remaining%%|*}"
                    remaining="${remaining#*|}"
                    uuid="${remaining%%|*}"
                    environment_uuid="${remaining#*|}"
                    
                    log "Checking local .env file with id ${uuid} at path \"${mount_path}\" for environment ${environment_uuid} (${environment_name})"

                    # Check if this mount is relevant to the current project
                    if ! is_project_mount "$mount_path" "$PROJECT_ROOT"; then
                        log "Local .env file does not belong to the current project, skipping"
                        continue
                    fi

                    if [[ "$is_enabled" == "true" ]]; then
                        if [[ ! -e "$mount_path" ]] || [[ ! -p "$mount_path" ]]; then
                            log "Local .env file is invalid (file is not present or not a FIFO)"
                            invalid_mounts+=("$mount_path|$environment_name")
                        else
                            log "Local .env file is valid and enabled"
                        fi
                    else
                        log "Local .env file is disabled"
                        disabled_mounts+=("$mount_path|$environment_name")
                    fi
                fi
            done <<< "$mount_hex_data"
        fi
    fi
fi

# Check for TOML-based required mounts
toml_file="${PROJECT_ROOT}/.1password/environments.toml"
if [[ -f "$toml_file" ]]; then
    log "Found environments.toml, checking required files..."
    
    toml_mounts=$(parse_toml_mounts "$toml_file")
    if [[ $? -eq 0 ]] && [[ -n "$toml_mounts" ]]; then
        while IFS= read -r mount_path || [[ -n "$mount_path" ]]; do
            [[ -z "$mount_path" ]] && continue
            
            # Resolve mount path relative to project root
            if [[ "$mount_path" == /* ]]; then
                # Absolute path
                resolved_path="$mount_path"
            else
                # Relative path
                resolved_path="${PROJECT_ROOT}/${mount_path}"
            fi
            
            # Normalize the path
            resolved_path=$(normalize_path "$resolved_path")
            
            log "Checking required local .env file from TOML: \"${resolved_path}\""
            
            # Check if path exists and is a FIFO
            if [[ ! -e "$resolved_path" ]] || [[ ! -p "$resolved_path" ]]; then
                log "Required local .env file is missing or invalid: \"${resolved_path}\""
                required_mounts+=("$resolved_path")
            else
                log "Required local .env file is valid: \"${resolved_path}\""
            fi
        done <<< "$toml_mounts"
    else
        log "Warning: Failed to parse environments.toml or no local .env files found"
    fi
fi

# ============================================================================
# PERMISSION DECISION LOGIC
# ============================================================================

# Consolidate all missing/invalid mounts (from DB and TOML)
all_missing_invalid=()
if [[ ${#invalid_mounts[@]} -gt 0 ]]; then
    for mount_entry in "${invalid_mounts[@]}"; do
        all_missing_invalid+=("${mount_entry%%|*}")
    done
fi
if [[ ${#required_mounts[@]} -gt 0 ]]; then
    for mount_path in "${required_mounts[@]}"; do
        # Avoid duplicates
        is_duplicate=false
        if [[ ${#all_missing_invalid[@]} -gt 0 ]]; then
            for existing_path in "${all_missing_invalid[@]}"; do
                if [[ "$existing_path" == "$mount_path" ]]; then
                    is_duplicate=true
                    break
                fi
            done
        fi
        if [[ "$is_duplicate" == "false" ]]; then
            all_missing_invalid+=("$mount_path")
        fi
    done
fi

# Generate unified error messages
if [[ ${#all_missing_invalid[@]} -gt 0 ]] || [[ ${#disabled_mounts[@]} -gt 0 ]]; then
    permission="deny"
    
    # Build message for missing/invalid mounts
    if [[ ${#all_missing_invalid[@]} -gt 0 ]]; then
        log "Denying permission due to missing or invalid environment files"
        
        # Extract environment name from DB mounts if available
        environment_name=""
        if [[ ${#invalid_mounts[@]} -gt 0 ]]; then
            first_invalid="${invalid_mounts[0]}"
            environment_name="${first_invalid#*|}"
        fi
        
        if [[ ${#all_missing_invalid[@]} -eq 1 ]]; then
            if [[ -n "$environment_name" ]]; then
                agent_message="This project uses 1Password environments. An environment file is expected to be mounted at the specified path. Error: the file is missing or invalid. Environment name: \"${environment_name}\". Path: \"${all_missing_invalid[0]}\". Suggestion: ensure the local .env file is configured and enabled from the environment's destinations tab in the 1Password app."
            else
                agent_message="This project uses 1Password environments. An environment file is required by environments.toml. Error: the file is missing or invalid. Path: \"${all_missing_invalid[0]}\". Suggestion: ensure the local .env file is configured and enabled from the environment's destinations tab in the 1Password app."
            fi
        else
            file_list=$(IFS=', '; echo "${all_missing_invalid[*]}")
            if [[ -n "$environment_name" ]]; then
                agent_message="This project uses 1Password environments. Environment files are expected to be mounted at the specified paths. Error: these files are missing or invalid. Environment name: \"${environment_name}\". Paths: \"${file_list}\". Suggestion: ensure the local .env files are configured and enabled from the environment's destinations tab in the 1Password app."
            else
                agent_message="This project uses 1Password environments. Environment files are required by environments.toml. Error: these files are missing or invalid. Paths: \"${file_list}\". Suggestion: ensure the local .env files are configured and enabled from the environment's destinations tab in the 1Password app."
            fi
        fi
    fi
    
    # Handle disabled mounts (different issue - needs to be enabled, not configured)
    if [[ ${#disabled_mounts[@]} -gt 0 ]]; then
        log "Denying permission due to disabled local .env files"
        
        # Extract environment name
        first_disabled="${disabled_mounts[0]}"
        environment_name="${first_disabled#*|}"
        
        # Extract mount paths
        mount_paths=()
        for mount_entry in "${disabled_mounts[@]}"; do
            mount_paths+=("${mount_entry%%|*}")
        done
        
        if [[ ${#disabled_mounts[@]} -eq 1 ]]; then
            disabled_msg="Error: the file is not mounted. Environment name: \"${environment_name}\". Path: \"${mount_paths[0]}\". Suggestion: enable the local .env file from the environment's destinations tab in the 1Password app."
        else
            file_list=$(IFS=', '; echo "${mount_paths[*]}")
            disabled_msg="Error: these files are not mounted. Environment name: \"${environment_name}\". Paths: \"${file_list}\". Suggestion: enable the local .env files from the environment's destinations tab in the 1Password app."
        fi
        
        # Combine messages if we have both missing/invalid and disabled
        if [[ ${#all_missing_invalid[@]} -gt 0 ]]; then
            agent_message="${agent_message} ${disabled_msg}"
        else
            if [[ ${#disabled_mounts[@]} -eq 1 ]]; then
                agent_message="This project uses 1Password environments. An environment file is expected to be mounted at the specified path. ${disabled_msg}"
            else
                agent_message="This project uses 1Password environments. Environment files are expected to be mounted at the specified paths. ${disabled_msg}"
            fi
        fi
    fi
fi

# Output JSON response with permission decision
output_response
exit 0
