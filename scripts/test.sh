#!/bin/zsh
# Runs swift-testing under Command Line Tools only (no Xcode installed).
# Usage: scripts/test.sh [--filter X] [--scratch-path DIR]
F=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
L=/Library/Developer/CommandLineTools/Library/Developer/usr/lib
exec swift test -Xswiftc -F$F -Xlinker -F$F -Xlinker -rpath -Xlinker $F -Xlinker -rpath -Xlinker $L "$@"
