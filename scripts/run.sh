#!/bin/zsh
# Bundles (debug) and launches LoftLine.app.
set -euo pipefail
cd "${0:A:h}/.."
scripts/bundle.sh --debug
open dist/LoftLine.app
