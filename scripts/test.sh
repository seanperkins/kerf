#!/bin/zsh
# Runs the swift-testing suite.
# With only Command Line Tools installed (no Xcode), swift-testing's framework and
# interop dylib are not on the default search paths, so inject them.
# Usage: scripts/test.sh [--filter X] [--scratch-path DIR]
F=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
L=/Library/Developer/CommandLineTools/Library/Developer/usr/lib
if [[ "$(xcode-select -p 2>/dev/null)" == /Library/Developer/CommandLineTools* && -d $F/Testing.framework ]]; then
  exec swift test -Xswiftc -F$F -Xlinker -F$F -Xlinker -rpath -Xlinker $F -Xlinker -rpath -Xlinker $L "$@"
fi
exec swift test "$@"
