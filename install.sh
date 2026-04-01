#!/usr/bin/env bash
#
# Install agent hooks for Cursor, GitHub Copilot, Claude Code, or Windsurf.
# Always creates a bundle (hook files). With --target-dir, installs that bundle into DIR and creates hooks.json from template if missing (never overwrites existing hooks.json).
# Run from this repo.
#
# Usage: ./install.sh --agent cursor|github-copilot|claude-code|windsurf [--target-dir DIR]
#
set -euo pipefail

CONFIG_NAME="install-client-config.json"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${SCRIPT_DIR}"
if [[ ! -f "${REPO_ROOT}/${CONFIG_NAME}" ]]; then
  REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
fi
CONFIG_PATH="${REPO_ROOT}/${CONFIG_NAME}"

usage() {
  echo "Usage: $0 --agent cursor|github-copilot|claude-code|windsurf [--target-dir DIR]"
  echo ""
  echo "  --agent      (required) Agent (cursor, github-copilot, claude-code, or windsurf)."
  echo "  --target-dir If set: install bundle into DIR (creates hooks.json from template if missing). If unset: create bundle in current directory only (no hooks.json)."
  echo ""
  exit 1
}

# ---- Config parsing ----
# Get the JSON object value for key (first occurrence), by brace counting.
get_json_block() {
  local content="$1"
  local key="$2"
  local rest
  rest="${content#*\"${key}\"*:}"
  [[ "$rest" == "$content" ]] && return 1
  rest="${rest#"${rest%%[![:space:]]*}"}"
  [[ "${rest:0:1}" != "{" ]] && return 1
  local depth=1 i=1
  local len=${#rest}
  while (( i < len && depth > 0 )); do
    local c="${rest:$i:1}"
    [[ "$c" == "{" ]] && (( depth++ ))
    [[ "$c" == "}" ]] && (( depth-- ))
    (( i++ ))
  done
  echo "${rest:0:$i}"
}

# Get first string value for key in a JSON fragment: "key": "value"
get_string_key() {
  local block="$1"
  local key="$2"
  if [[ "$block" =~ \"$key\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
    echo "${BASH_REMATCH[1]}"
    return 0
  fi
  return 1
}

# Get array of quoted strings for key: "key": ["a", "b"]
get_string_array() {
  local block="$1"
  local key="$2"
  local line
  line=$(echo "$block" | grep -oE "\"${key}\"[[:space:]]*:[[:space:]]*\[[^]]*\]" | head -1)
  [[ -z "$line" ]] && return 1
  local inner="${line#*\[}"
  inner="${inner%\]}"
  local result=()
  while [[ "$inner" =~ \"([^\"]+)\" ]]; do
    result+=( "${BASH_REMATCH[1]}" )
    inner="${inner#*\"${BASH_REMATCH[1]}\"}"
    inner="${inner#,}"
    inner="${inner#"${inner%%[![:space:]]*}"}"
  done
  printf '%s\n' "${result[@]}"
}

# Get hook_events as lines "event\hookname" from block
get_hook_events() {
  local block="$1"
  local events_block
  events_block=$(get_json_block "$block" "hook_events")
  [[ -z "$events_block" ]] && return 0
  while [[ "$events_block" =~ \"([^\"]+)\"[[:space:]]*:[[:space:]]*\[ ]]; do
    local event="${BASH_REMATCH[1]}"
    local rest="${events_block#*${BASH_REMATCH[0]}}"
    local inner="${rest%%\]*}"
    events_block="${rest#*\]}"
    while [[ "$inner" =~ \"([^\"]+)\" ]]; do
      echo "${event}	${BASH_REMATCH[1]}"
      inner="${inner#*\"${BASH_REMATCH[1]}\"}"
      inner="${inner#,}"
      inner="${inner#"${inner%%[![:space:]]*}"}"
    done
  done
}

# Reject relative path if it could escape the base (path traversal).
# Call after reading install_dir and config_path from config.
is_unsafe_relative_path() {
  local path="$1"
  [[ "$path" == *"/../"* ]] && return 0
  [[ "$path" == *"/.." ]] && return 0
  [[ "$path" == "../"* ]] && return 0
  [[ "$path" == ".." ]] && return 0
  return 1
}

# Reject adapter or hook name that could be used for path traversal.
# Names must be a single segment (no slashes) and not . or ..
is_unsafe_segment() {
  local name="$1"
  [[ -z "$name" ]] && return 0
  [[ "$name" == "." ]] && return 0
  [[ "$name" == *"/"* ]] && return 0
  is_unsafe_relative_path "$name" && return 0
  return 1
}

# ---- Main ----
AGENT=""
TARGET_DIR=""

require_value() {
  local opt="$1"
  if [[ $# -lt 2 || -z "$2" || "$2" == -* ]]; then
    echo "Error: $opt requires a value (e.g. for --agent: cursor, github-copilot, claude-code, or windsurf)" >&2
    exit 1
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --agent)
      require_value "--agent" "${2:-}"
      AGENT="$2"
      shift 2
      ;;
    --target-dir)
      require_value "--target-dir" "${2:-}"
      TARGET_DIR="$2"
      shift 2
      ;;
    -h|--help) usage ;;
    *) echo "Unknown option: $1" >&2; usage ;;
  esac
done

# Ensure an agent is specified
if [[ -z "$AGENT" ]]; then
  echo "Error: --agent is required (cursor, github-copilot, claude-code, or windsurf)" >&2
  usage
fi

# Ensure the config file exists
if [[ ! -f "$CONFIG_PATH" ]]; then
  echo "Error: config not found: $CONFIG_PATH" >&2
  exit 1
fi

# Get the agent block
CONFIG_CONTENT=$(cat "$CONFIG_PATH")
AGENT_BLOCK=$(get_json_block "$CONFIG_CONTENT" "$AGENT") || true
if [[ -z "$AGENT_BLOCK" ]]; then
  echo "Error: could not find agent block for: $AGENT" >&2
  exit 1
fi

# Get the project block used for the install directory and config path
SCOPE_BLOCK=$(get_json_block "$AGENT_BLOCK" "project") || true
if [[ -z "$SCOPE_BLOCK" ]]; then
  echo "Error: could not find project block for: $AGENT" >&2
  exit 1
fi

# Get the install directory and config path relative to the project block
INSTALL_DIR_REL=$(get_string_key "$SCOPE_BLOCK" "install_dir") || true
CONFIG_PATH_REL=$(get_string_key "$SCOPE_BLOCK" "config_path") || true
if [[ -z "$INSTALL_DIR_REL" || -z "$CONFIG_PATH_REL" ]]; then
  echo "Error: missing install_dir or config_path for agent=$AGENT" >&2
  exit 1
fi

# Reject unsafe relative paths
if is_unsafe_relative_path "$INSTALL_DIR_REL" || is_unsafe_relative_path "$CONFIG_PATH_REL"; then
  echo "Error: install_dir or config_path may not contain '..' (path traversal)." >&2
  exit 1
fi

if [[ "$INSTALL_DIR_REL" == *$'\n'* || "$CONFIG_PATH_REL" == *$'\n'* ]]; then
  echo "Error: install_dir or config_path may not contain newlines." >&2
  exit 1
fi

# Resolve install directory (and config path only when --target-dir is set)
BUNDLE_NAME="${INSTALL_DIR_REL##*/}"
if [[ -n "${TARGET_DIR:-}" ]]; then
  if [[ ! -d "$TARGET_DIR" ]]; then
    echo "Error: target directory does not exist: $TARGET_DIR" >&2
    exit 1
  fi
  BASE="$(cd "$TARGET_DIR" && pwd)"
  INSTALL_DIR="${BASE}/${INSTALL_DIR_REL}"
  CONFIG_FILE="${BASE}/${CONFIG_PATH_REL}"
  echo "Target directory: $BASE"
else
  INSTALL_DIR="$(pwd)/${BUNDLE_NAME}"
  CONFIG_FILE=""
fi

echo "Agent: $AGENT"
echo "Install dir:  $INSTALL_DIR"
if [[ -n "$CONFIG_FILE" ]]; then
  echo "Config path: $CONFIG_FILE (created if missing)"
fi
echo ""

# Overwrite prompt: same for bundle-in-cwd or install-into-target (never overwrite existing hooks.json)
if [[ -d "$INSTALL_DIR" ]] && [[ -t 0 ]]; then
  echo "1Password agent hooks already installed at: $INSTALL_DIR"
  echo "This will overwrite with a fresh install. Any changes you made may be lost."
  read -r -p "Continue? (y/n) " response
  case "$response" in
    [yY]|[yY][eE][sS]) ;;
    *) echo "Aborted."; exit 0 ;;
  esac
  rm -rf "$INSTALL_DIR"
fi

mkdir -p "${INSTALL_DIR}/bin" "${INSTALL_DIR}/lib" "${INSTALL_DIR}/adapters" "${INSTALL_DIR}/hooks"

# Copy lib and bin
cp "${REPO_ROOT}/bin/run-hook.sh" "${INSTALL_DIR}/bin/run-hook.sh"
for f in "${REPO_ROOT}/lib/"*.sh; do
  [[ -f "$f" ]] && cp "$f" "${INSTALL_DIR}/lib/"
done

# Copy adapters for this agent
while IFS= read -r adapter; do
  [[ -z "$adapter" ]] && continue
  if is_unsafe_segment "$adapter"; then
    echo "Error: invalid adapter name (path traversal). skipping." >&2
    exit 1
  fi
  src="${REPO_ROOT}/adapters/${adapter}"
  if [[ -f "$src" ]]; then
    cp "$src" "${INSTALL_DIR}/adapters/"
  else
    echo "Warning: adapter not found: $src"
  fi
done < <(get_string_array "$AGENT_BLOCK" "adapters")

# Copy only hooks referenced in hook_events
while IFS=$'\t' read -r event hook_name; do
  [[ -z "$hook_name" ]] && continue
  if is_unsafe_segment "$hook_name"; then
    echo "Error: invalid hook name (path traversal). skipping." >&2
    exit 1
  fi
  hook_dir="${REPO_ROOT}/hooks/${hook_name}"
  if [[ -d "$hook_dir" && -f "${hook_dir}/hook.sh" ]]; then
    mkdir -p "${INSTALL_DIR}/hooks/${hook_name}"
    cp -r "${hook_dir}/"* "${INSTALL_DIR}/hooks/${hook_name}/"
  else
    echo "Warning: hook not found: $hook_dir (or hook.sh missing)"
  fi
done < <(get_hook_events "$AGENT_BLOCK")

# Create hooks.json only when --target-dir was set: from template if missing and never overwrite existing
if [[ -n "$CONFIG_FILE" ]]; then
  if [[ ! -f "$CONFIG_FILE" ]]; then
    mkdir -p "$(dirname "$CONFIG_FILE")"
    template="${REPO_ROOT}/${CONFIG_PATH_REL}"

    # Template is the repo file at the same path (.cursor/hooks.json).
    if [[ -f "$template" ]]; then
      cp "$template" "$CONFIG_FILE"
      # Replace placeholder "bin/run-hook.sh" in template with install-relative path (cursor-1password-hooks-bundle/bin/run-hook.sh).
      SCRIPT_PATH_REL="${INSTALL_DIR_REL}/bin/run-hook.sh"
      SCRIPT_PATH_REL_SED="${SCRIPT_PATH_REL//\\/\\\\}"
      SCRIPT_PATH_REL_SED="${SCRIPT_PATH_REL_SED//&/\\&}"

      # Replace "bin/run-hook.sh" in the copied config with the install path so the agent runs the correct script.
      if sed --version 2>/dev/null | grep -q GNU; then
        sed -i "s|bin/run-hook\.sh|${SCRIPT_PATH_REL_SED}|g" "$CONFIG_FILE"
      else
        sed -i.bak "s|bin/run-hook\.sh|${SCRIPT_PATH_REL_SED}|g" "$CONFIG_FILE" && rm -f "${CONFIG_FILE}.bak"
      fi
      echo "Created $CONFIG_FILE with default hook entries."
    else
      echo "Warning: no template at $template; skipping config creation."
    fi
  else
    echo "" >&2
    echo "WARNING: Config already exists at $CONFIG_FILE; update it to add or change hook entries." >&2
    echo "" >&2
  fi
fi

if [[ -n "$CONFIG_FILE" ]]; then
  echo "Done. Hook(s) installed"
else
  echo "Bundle created at: $INSTALL_DIR"
  echo "Add hooks.json at your config path and set command to: ${INSTALL_DIR}/bin/run-hook.sh <hook-name>"
fi
