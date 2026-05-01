#!/usr/bin/env bash
# Runs MikeTodoList UI tests (XCUITest). Execute from repo root.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

DESTINATION="${DESTINATION:-platform=iOS Simulator,name=iPhone 17,OS=latest}"

echo "==> xcodebuild test scheme=MikeTodoList destination=${DESTINATION}"
xcodebuild \
  -scheme MikeTodoList \
  -destination "$DESTINATION" \
  -only-testing:MikeTodoListUITests \
  test

echo "==> UI tests finished successfully"
