#!/usr/bin/env bash
# Boots an iPhone Simulator, builds MikeTodoList (Debug), installs, and launches it.
# Run from repo root: ./scripts/run-ios-simulator.sh
#
# Environment:
#   SIMULATOR_NAME — device name as shown in Simulator (default: iPhone 17)
#   DESTINATION    — full xcodebuild destination (overrides SIMULATOR_NAME when set)
#                     default: platform=iOS Simulator,name=iPhone 17,OS=latest
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

SCHEME="MikeTodoList"
PROJECT="MikeTodoList.xcodeproj"
BUNDLE_ID="com.example.MikeTodoList"
DERIVED="$ROOT/build/ios-simulator-run"

DESTINATION="${DESTINATION:-}"
SIMULATOR_NAME="${SIMULATOR_NAME:-iPhone 17}"

if [[ -z "$DESTINATION" ]]; then
  DESTINATION="platform=iOS Simulator,name=${SIMULATOR_NAME},OS=latest"
fi

resolve_udid() {
  local want="$1"
  python3 -c "
import json, subprocess, sys
want = sys.argv[1]
raw = subprocess.check_output(
    ['xcrun', 'simctl', 'list', 'devices', 'available', '-j'],
    text=True,
)
data = json.loads(raw)
for _rt, devices in data.get('devices', {}).items():
    for d in devices:
        if d.get('name') == want and d.get('isAvailable', True):
            print(d['udid'])
            sys.exit(0)
sys.stderr.write(f'No available simulator named {want!r}. Try: xcrun simctl list devices available\n')
sys.exit(1)
" "$want"
}

if [[ "$DESTINATION" =~ name=([^,]+) ]]; then
  SIMULATOR_NAME="${BASH_REMATCH[1]}"
fi

UDID="$(resolve_udid "$SIMULATOR_NAME")"

echo "==> Simulator: ${SIMULATOR_NAME} (${UDID})"
xcrun simctl boot "$UDID" 2>/dev/null || true
open -a Simulator

echo "==> xcodebuild build scheme=${SCHEME} destination=${DESTINATION}"
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Debug \
  -destination "$DESTINATION" \
  -derivedDataPath "$DERIVED" \
  build

APP="$DERIVED/Build/Products/Debug-iphonesimulator/${SCHEME}.app"
if [[ ! -d "$APP" ]]; then
  echo "error: built app not found at $APP" >&2
  exit 1
fi

echo "==> Install & launch ${BUNDLE_ID}"
xcrun simctl install "$UDID" "$APP"
xcrun simctl launch "$UDID" "$BUNDLE_ID"

echo "==> Done"
