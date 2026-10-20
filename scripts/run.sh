#!/bin/zsh
# Bundles (debug) and launches Kerf.app.
set -euo pipefail
cd "${0:A:h}/.."
scripts/bundle.sh --debug
open dist/Kerf.app
