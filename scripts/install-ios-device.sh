#!/usr/bin/env bash
# Build MikeTodoList (Debug) for a physical iPhone/iPad and install it over USB or network-paired Xcode connection.
#
# Prerequisites:
#   - Xcode installed; open the project once and set Signing & Team so Automatic signing works.
#   - iPhone unlocked; trust this Mac; Developer Mode on if iOS asks.
#
# Usage (from repo root):
#   ./scripts/install-ios-device.sh              # install once (fails if no device)
#   ./scripts/install-ios-device.sh --launch     # install and launch the app
#   ./scripts/install-ios-device.sh --watch    # poll until a device appears, install when plugged in / paired
#
# Environment:
#   DEVELOPMENT_TEAM — Apple Team ID string if CLI builds fail to resolve signing (same as Xcode target).
#   IOS_DEVICE_UDID — skip discovery; use this UDID (from Xcode → Window → Devices and Simulators).
#   INSTALL_IOS_DEBUG — set to 1 to print discovery diagnostics on stderr.
#
# Shell: If zsh prints `read-only variable: status`, run with bash explicitly:
#   bash ./scripts/install-ios-device.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

SCHEME="MikeTodoList"
PROJECT="MikeTodoList.xcodeproj"
BUNDLE_ID="${BUNDLE_ID:-com.example.MikeTodoList}"
DERIVED="${DERIVED:-$ROOT/build/ios-device-install}"

WATCH=false
LAUNCH=false

usage() {
  sed -n '1,22p' "$0" | sed -n 's/^# \{0,1\}//p'
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --watch|-w) WATCH=true ;;
    --launch|-l) LAUNCH=true ;;
    -h|--help) usage ;;
    *)
      echo "Unknown option: $1" >&2
      usage ;;
  esac
  shift || true
done

have_devicectl() {
  xcrun devicectl help >/dev/null 2>&1
}

# Prints UDID of first connected physical iOS device (not Simulator).
# Order: IOS_DEVICE_UDID env → devicectl JSON → xcrun xctrace → xcodebuild -showdestinations
pick_physical_device_udid() {
  if [[ -n "${IOS_DEVICE_UDID:-}" ]]; then
    echo "${IOS_DEVICE_UDID}"
    return 0
  fi

  SCHEME="$SCHEME" PROJECT="$PROJECT" ROOT="$ROOT" INSTALL_IOS_DEBUG="${INSTALL_IOS_DEBUG:-}" python3 <<'PY'
import json, os, re, subprocess, sys

scheme = os.environ["SCHEME"]
project = os.environ["PROJECT"]
root = os.environ["ROOT"]
debug = os.environ.get("INSTALL_IOS_DEBUG") == "1"


def dbg(msg):
    if debug:
        print(msg, file=sys.stderr)


def pick_devicectl():
    try:
        out = subprocess.check_output(
            ["xcrun", "devicectl", "list", "devices", "--json-output", "-"],
            stderr=subprocess.DEVNULL,
            timeout=60,
        )
        data = json.loads(out.decode())
        devices = (data.get("result") or {}).get("devices") or []
        dbg(f"devicectl: {len(devices)} device row(s)")
        for d in devices:
            ident = d.get("identifier")
            if not ident:
                continue
            hp = d.get("hardwareProperties") or {}
            plat = (hp.get("platform") or "").strip()
            name = (hp.get("marketingName") or "").lower()
            # Prefer explicit iOS hardware rows from devicectl.
            if plat.lower() == "ios" or "iphone" in name or "ipad" in name:
                dbg(f"devicectl picked: {ident} ({hp.get('marketingName') or plat})")
                return ident
    except Exception as exc:
        dbg(f"devicectl parse failed: {exc}")
    return None


def pick_showdestinations():
    try:
        proc = subprocess.run(
            [
                "xcodebuild",
                "-showdestinations",
                "-scheme",
                scheme,
                "-project",
                os.path.join(root, project),
            ],
            cwd=root,
            capture_output=True,
            text=True,
            timeout=120,
        )
        lines = ((proc.stdout or "") + "\n" + (proc.stderr or "")).splitlines()
        dbg(f"showdestinations: {len(lines)} line(s), stderr={(proc.stderr or '')[:200]!r}")
    except Exception as exc:
        dbg(f"showdestinations failed: {exc}")
        return None

    id_re = re.compile(r"id:([^,}\]]+)")
    for line in lines:
        if "platform:iOS" not in line:
            continue
        if "Simulator" in line:
            continue
        low = line.lower()
        if "placeholder" in low or "dvtiphoneplaceholder" in low:
            continue
        m = id_re.search(line)
        if not m:
            continue
        udid = m.group(1).strip().strip("'")
        # Real devices look like hyphenated IDs; placeholders use colons / long tokens.
        if re.fullmatch(r"[0-9A-Fa-f-]{20,}", udid):
            dbg(f"showdestinations picked: {udid}")
            return udid
    return None


def pick_xctrace():
    """Parses `xcrun xctrace list devices` physical section (often lists iPhone before Xcode adds showdestinations)."""
    try:
        out = subprocess.check_output(
            ["xcrun", "xctrace", "list", "devices"],
            stderr=subprocess.DEVNULL,
            timeout=60,
            text=True,
        )
    except Exception as exc:
        dbg(f"xctrace failed: {exc}")
        return None

    lines = out.splitlines()
    in_devices = False
    udid_re = re.compile(r"\(([0-9A-Fa-f]{8}-(?:[0-9A-Fa-f]{4}-){3}[0-9A-Fa-f]{12})\)\s*$")
    skip = re.compile(r"Simulator|MacBook|Mac mini|Mac Studio|iMac|Mac Pro", re.I)
    for line in lines:
        s = line.strip()
        if s == "== Devices ==":
            in_devices = True
            continue
        if s == "== Simulators ==":
            break
        if not in_devices:
            continue
        if skip.search(line):
            continue
        m = udid_re.search(line)
        if m:
            udid = m.group(1)
            dbg(f"xctrace picked: {udid} ({line.strip()})")
            return udid
    dbg("xctrace: no hardware row matched")
    return None


for picker in (pick_devicectl, pick_xctrace, pick_showdestinations):
    udid = picker()
    if udid:
        print(udid)
        sys.exit(0)

sys.exit(1)
PY
}

build_for_device() {
  echo "==> xcodebuild build scheme=${SCHEME} sdk=iphoneos"
  local -a extra=()
  if [[ -n "${DEVELOPMENT_TEAM:-}" ]]; then
    extra+=(DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM")
  fi
  xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Debug \
    -sdk iphoneos \
    -destination 'generic/platform=iOS' \
    -derivedDataPath "$DERIVED" \
    "${extra[@]}" \
    CODE_SIGN_STYLE=Automatic \
    build
}

install_and_maybe_launch() {
  local udid="$1"
  local app="$DERIVED/Build/Products/Debug-iphoneos/${SCHEME}.app"
  if [[ ! -d "$app" ]]; then
    echo "error: built app not found at $app" >&2
    return 1
  fi

  if ! have_devicectl; then
    echo "error: xcrun devicectl not available (need Xcode 15+)." >&2
    echo "Install/build from Xcode (Product → Destination → your iPhone → Run) or upgrade Xcode." >&2
    return 1
  fi

  echo "==> Install → device ${udid}"
  xcrun devicectl device install app --device "$udid" "$app" --timeout 600

  if [[ "$LAUNCH" == true ]]; then
    echo "==> Launch ${BUNDLE_ID}"
    xcrun devicectl device process launch --device "$udid" "$BUNDLE_ID" --timeout 120 || true
  fi
}

install_once() {
  local udid
  if ! udid="$(pick_physical_device_udid)"; then
    echo "error: No physical iOS device found." >&2
    echo "Try:" >&2
    echo "  • Unlock iPhone; tap Trust on the phone; open Xcode → Window → Devices and Simulators — wait until the device shows Ready." >&2
    echo "  • Run from bash (avoids some zsh hook errors):  bash ./scripts/install-ios-device.sh" >&2
    echo "  • Paste UDID from Xcode Devices list:  IOS_DEVICE_UDID='XXXXXXXX-…' bash ./scripts/install-ios-device.sh" >&2
    echo "  • Discovery debug:  INSTALL_IOS_DEBUG=1 bash ./scripts/install-ios-device.sh" >&2
    return 1
  fi

  echo "==> Device: ${udid}"
  rm -rf "$DERIVED"
  build_for_device
  install_and_maybe_launch "$udid"
  echo "==> Done"
}

watch_loop() {
  echo "==> Watching for a physical iOS device (Ctrl+C to stop). Plug in or wake your iPhone."
  local saw_device=false
  while true; do
    local udid=""
    if udid="$(pick_physical_device_udid 2>/dev/null)" && [[ -n "$udid" ]]; then
      if [[ "$saw_device" == false ]]; then
        saw_device=true
        echo "==> Detected device ${udid}"
        set +e
        install_once || echo "warn: install failed; fix signing/errors above. Will retry after unplug/replug." >&2
        set -e
      fi
    else
      saw_device=false
    fi
    sleep 4
  done
}

if [[ "$WATCH" == true ]]; then
  watch_loop
else
  install_once
fi
