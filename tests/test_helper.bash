# Shared test helper sourced by all bats test files.
# Usage: load "../test_helper"

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB_DIR="${PROJECT_ROOT}/lib"

# Suppress logging to files during tests
export LOG_FILE="/dev/null"
export LOG_TAG="test"
