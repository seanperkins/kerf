#!/bin/zsh
# Sourced by the other scripts. SwiftPM compiles Package.swift under its own `sandbox-exec`, and
# macOS refuses to nest one sandbox inside another ("sandbox_apply: Operation not permitted"), so
# any `swift build` / `swift test` run from a sandboxed agent shell (Claude Code, Codex, OMP) fails
# before it starts. Probe for that and add `--disable-sandbox` only when needed; SwiftPM's sandbox
# only guards the manifest and plugins, so nothing is lost for this package.
# Set KERF_SWIFTPM_FLAGS to override (e.g. KERF_SWIFTPM_FLAGS="" to force the default).
typeset -ga SWIFTPM_FLAGS
if [[ -n "${KERF_SWIFTPM_FLAGS+x}" ]]; then
  SWIFTPM_FLAGS=(${=KERF_SWIFTPM_FLAGS})
elif command -v sandbox-exec >/dev/null 2>&1 && ! sandbox-exec -p '(version 1)(allow default)' /usr/bin/true 2>/dev/null; then
  SWIFTPM_FLAGS=(--disable-sandbox)
else
  SWIFTPM_FLAGS=()
fi
