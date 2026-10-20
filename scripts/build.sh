#!/bin/zsh
# Debug build. Same as `swift build`, but works inside a sandboxed agent shell (see swiftpm-env.sh).
# Usage: scripts/build.sh [swift build arguments...]
set -euo pipefail
cd "${0:A:h}/.."
source scripts/swiftpm-env.sh
exec swift build "${SWIFTPM_FLAGS[@]}" "$@"
