# Shared OS detection utilities for ide-hooks.
# Source this file; it defines functions only and has no side effects.

[[ -n "${_LIB_OS_LOADED:-}" ]] && return 0
_LIB_OS_LOADED=1

_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_LIB_DIR}/logging.sh"

# Detect the host operating system.
# Prints one of: "macos", "linux", "unknown"
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
