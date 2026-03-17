#!/bin/bash

set -euo pipefail

# Entry point for all IDE hook invocations.
# Usage: bin/run-hook.sh <hook-name>
#
# Reads raw IDE JSON from stdin, detects the calling IDE, normalizes input
# through the matching adapter, runs the hook, and translates the output
# back to the IDE's expected format.
#
# Fails open on any error — emits the IDE's "allow" response and exits cleanly.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

source "${REPO_ROOT}/lib/logging.sh"
source "${REPO_ROOT}/lib/json.sh"

HOOK_NAME="${1:-}"
if [[ -z "$HOOK_NAME" ]]; then
    log "Error: no hook name provided to run-hook.sh"
    exit 0
fi

if [[ "$HOOK_NAME" == */* ]] || [[ "$HOOK_NAME" == *..* ]]; then
    log "Error: invalid hook name '${HOOK_NAME}' — must not contain '/' or '..'"
    exit 0
fi

HOOK_SCRIPT="${REPO_ROOT}/hooks/${HOOK_NAME}/hook.sh"
if [[ ! -f "$HOOK_SCRIPT" ]]; then
    log "Error: hook script not found: ${HOOK_SCRIPT}"
    exit 0
fi

LOG_TAG="run-hook:${HOOK_NAME}"

# ── 1. Buffer raw payload ────────────────────────────────────────────────
raw_payload=$(cat)

if [[ -z "$raw_payload" ]]; then
    log "Warning: empty payload on stdin, failing open"
    exit 0
fi

# ── 2. Detect client ─────────────────────────────────────────────────────
# Centralized detection in adapters/_lib.sh uses env vars + payload fields
# in most-specific-first order to avoid ambiguity.
ADAPTERS_DIR="${REPO_ROOT}/adapters"
source "${ADAPTERS_DIR}/_lib.sh"

detected_client=$(detect_client "$raw_payload")

# Map "unknown" to the generic fallback adapter
detected_adapter="$detected_client"
if [[ "$detected_adapter" == "unknown" ]]; then
    detected_adapter="generic"
fi

log "Detected client: ${detected_adapter}"

# ── 3. Source matching adapter ───────────────────────────────────────────
adapter_file="${ADAPTERS_DIR}/${detected_adapter}.sh"
if [[ ! -f "$adapter_file" ]]; then
    log "Error: adapter file not found: ${adapter_file}, failing open"
    exit 0
fi
source "$adapter_file"

# ── 4. Normalize input ──────────────────────────────────────────────────
canonical_input=$(normalize_input "$raw_payload") || {
    log "Error: normalize_input failed, failing open"
    exit 0
}

if [[ -z "$canonical_input" ]]; then
    log "Error: normalize_input produced empty output, failing open"
    exit 0
fi

log "Canonical event: $(extract_json_string "$canonical_input" "event")"

# ── 5. Pipe to hook ─────────────────────────────────────────────────────
start_ms=$(($(date +%s) * 1000))

canonical_output=$(echo "$canonical_input" | bash "$HOOK_SCRIPT" 2>/dev/null) || true

end_ms=$(($(date +%s) * 1000))
duration_ms=$((end_ms - start_ms))

if [[ -z "$canonical_output" ]]; then
    log "Warning: hook produced no output, failing open"
    canonical_output='{"decision":"allow","message":""}'
fi

# ── 6–7. Log telemetry ──────────────────────────────────────────────────
decision=$(extract_json_string "$canonical_output" "decision")
if [[ -z "$decision" ]]; then
    log "Warning: could not extract decision from hook output, failing open"
    canonical_output='{"decision":"allow","message":""}'
    decision="allow"
fi

log "Hook result: decision=${decision} duration_ms=${duration_ms}"

# ── 8–9. Emit client-specific output and exit ───────────────────────────────
emit_output "$canonical_output"
