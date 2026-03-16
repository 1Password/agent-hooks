#!/usr/bin/env bash
#
# Install agent hooks for Cursor or GitHub Copilot.
# Copies files only; does not create or modify hooks.json (you add entries yourself).
# Run from this repo; can install into this repo (project/user) or into --target-dir.
#
# Usage: ./install.sh [--agent cursor|github-copilot] [--scope user|project] [--target-dir DIR]
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
  echo "Usage: $0 [--agent cursor|github-copilot] [--scope user|project] [--target-dir DIR]"
  echo ""
  echo "  --agent      Agent to install (default: cursor)"
  echo "  --scope      user = use user paths (e.g. under $HOME). project = use project paths (default; use with --target-dir to install into another repo)."
  echo "  --target-dir Install into DIR (e.g. install from this repo into another: --target-dir /path/to/other/repo)"
  echo ""
  echo "This script only copies files. It does not create or edit hooks.json; add hook entries yourself."
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

# ---- Main ----
AGENT="cursor"
SCOPE="project"
TARGET_DIR=""

# Require a non-option value for the last option; call from case branch before using $2.
require_value() {
  local opt="$1"
  if [[ $# -lt 2 || -z "$2" || "$2" == -* ]]; then
    echo "Error: $opt requires a value (e.g. for --agent: cursor, github-copilot)" >&2
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
    --scope)
      require_value "--scope" "${2:-}"
      SCOPE="$2"
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

if [[ "$SCOPE" != "user" && "$SCOPE" != "project" ]]; then
  echo "Error: --scope must be 'user' or 'project'"
  exit 1
fi

if [[ ! -f "$CONFIG_PATH" ]]; then
  echo "Error: config not found: $CONFIG_PATH"
  exit 1
fi

CONFIG_CONTENT=$(cat "$CONFIG_PATH")
AGENT_BLOCK=$(get_json_block "$CONFIG_CONTENT" "$AGENT") || true
if [[ -z "$AGENT_BLOCK" ]]; then
  echo "Error: could not find agent block for: $AGENT"
  exit 1
fi

SCOPE_BLOCK=$(get_json_block "$AGENT_BLOCK" "$SCOPE") || true
if [[ -z "$SCOPE_BLOCK" ]]; then
  echo "Error: could not find scope block for: $SCOPE"
  exit 1
fi

INSTALL_DIR_REL=$(get_string_key "$SCOPE_BLOCK" "install_dir") || true
CONFIG_PATH_REL=$(get_string_key "$SCOPE_BLOCK" "config_path") || true
if [[ -z "$INSTALL_DIR_REL" || -z "$CONFIG_PATH_REL" ]]; then
  echo "Error: missing install_dir or config_path for agent=$AGENT scope=$SCOPE"
  exit 1
fi

# Resolve base directory
if [[ -n "${TARGET_DIR:-}" ]]; then
  if [[ ! -d "$TARGET_DIR" ]]; then
    echo "Error: target directory does not exist: $TARGET_DIR"
    exit 1
  fi
  BASE="$(cd "$TARGET_DIR" && pwd)"
  echo "Target directory: $BASE"
else
  if [[ "$SCOPE" == "user" ]]; then
    BASE="${HOME}"
  else
    BASE="$(pwd)"
  fi
fi

INSTALL_DIR="${BASE}/${INSTALL_DIR_REL}"
CONFIG_FILE="${BASE}/${CONFIG_PATH_REL}"

echo "Agent: $AGENT | Scope: $SCOPE"
echo "Install dir:  $INSTALL_DIR"
echo "Config path: $CONFIG_FILE (not created or modified)"
echo ""

mkdir -p "${INSTALL_DIR}/bin" "${INSTALL_DIR}/lib" "${INSTALL_DIR}/adapters" "${INSTALL_DIR}/hooks"

# Copy lib and bin
cp "${REPO_ROOT}/bin/run-hook.sh" "${INSTALL_DIR}/bin/run-hook.sh"
for f in "${REPO_ROOT}/lib/"*.sh; do
  [[ -f "$f" ]] && cp "$f" "${INSTALL_DIR}/lib/"
done

# Copy adapters for this agent
while IFS= read -r adapter; do
  [[ -z "$adapter" ]] && continue
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
  hook_dir="${REPO_ROOT}/hooks/${hook_name}"
  if [[ -d "$hook_dir" && -f "${hook_dir}/hook.sh" ]]; then
    mkdir -p "${INSTALL_DIR}/hooks/${hook_name}"
    cp -r "${hook_dir}/"* "${INSTALL_DIR}/hooks/${hook_name}/"
  else
    echo "Warning: hook not found: $hook_dir (or hook.sh missing)"
  fi
done < <(get_hook_events "$AGENT_BLOCK")

echo "Done. Add hook entries to your config yourself."
