#!/bin/zsh
# Runs the swift-testing suite.
# With only Command Line Tools installed (no Xcode), swift-testing's framework and
# interop dylib are not on the default search paths, so inject them.
# Works inside a sandboxed agent shell too (see swiftpm-env.sh).
# Usage: scripts/test.sh [--filter X] [--scratch-path DIR]
cd "${0:A:h}/.."
source scripts/swiftpm-env.sh
F=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
L=/Library/Developer/CommandLineTools/Library/Developer/usr/lib
if [[ "$(xcode-select -p 2>/dev/null)" == /Library/Developer/CommandLineTools* && -d $F/Testing.framework ]]; then
  exec swift test "${SWIFTPM_FLAGS[@]}" -Xswiftc -F$F -Xlinker -F$F -Xlinker -rpath -Xlinker $F -Xlinker -rpath -Xlinker $L "$@"
fi
exec swift test "${SWIFTPM_FLAGS[@]}" "$@"
