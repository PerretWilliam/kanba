#!/bin/sh
# Runs the Swift tests and fails unless every line of the logic layer is covered (lcov line coverage = 100%).
# Scope: Model/ and Support/BoardFile.swift. SwiftUI views, components, dialogs and the app entry are excluded (UI, not unit-testable).
set -e
cd "$(dirname "$0")/.."
swift test --no-parallel --enable-code-coverage >/dev/null
PROF=$(dirname "$(swift test --show-codecov-path)")/default.profdata
XCT=$(find .build -name '*.xctest' -maxdepth 6 | head -1)
BIN=$XCT/Contents/MacOS/$(basename "$XCT" .xctest)
SRC=$(ls Sources/Kanban/Model/*.swift Sources/Kanban/Support/BoardFile.swift)
xcrun llvm-cov export -format=lcov "$BIN" -instr-profile "$PROF" $SRC > .build/coverage.lcov
awk -F'[:,]' '/^SF:/ { f=$2 } /^DA:/ { total++; if ($3 == 0) { print "uncovered: " f ":" $2; miss++ } }
  END { printf "Swift line coverage: %d/%d lines\n", total - miss, total; exit miss > 0 }' .build/coverage.lcov
