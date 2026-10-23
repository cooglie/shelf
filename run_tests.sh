#!/bin/bash
#
# run_tests.sh — Baut und führt die FileCoordinator-Tests aus.
# Kein Xcode-Projekt / XCTest nötig — kompiliert FileCoordinator.swift + Tests
# gegen Foundation und führt das Binary aus.
#
# Nutzung:  cd Schelf && bash run_tests.sh
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
BUILD="$ROOT/.build/tests"

echo "=== Schelf Tests ==="
mkdir -p "$BUILD"

# FileCoordinator isoliert kompilieren (es nutzt nur Foundation).
swiftc -parse-as-library \
    -target x86_64-apple-macosx12.0 \
    -sdk "$SDK" -O \
    -framework Foundation \
    "$ROOT/Sources/FileCoordinator.swift" \
    "$ROOT/Tests/SchelfTests/FileCoordinatorTests.swift" \
    -o "$BUILD/SchelfTests"

"$BUILD/SchelfTests"
