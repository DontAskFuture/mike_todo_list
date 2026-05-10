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
#   DEVELOPMENT_TEAM — Apple Team ID (10 characters). Needed if Signing & Capabilities has no Team in this repo.
#   IOS_DEVICE_UDID — skip discovery; use the **hardware** destination id (00008140-… from xcodebuild -showdestinations),
#                     not the Core Device pairing UUID from devicectl (0171B583-…), or xcodebuild will not match.
#   INSTALL_IOS_DEVICE_NAME — substring of the device name when several iPhones are connected (e.g. iPhone, Autumn).
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

# Prints hardware destination id for xcodebuild -destination (not the Core Device pairing UUID from devicectl).
# Order: IOS_DEVICE_UDID env → xcodebuild -showdestinations → xcrun xctrace → devicectl (last resort; often wrong for xcodebuild).
pick_physical_device_udid() {
  if [[ -n "${IOS_DEVICE_UDID:-}" ]]; then
    echo "${IOS_DEVICE_UDID}"
    return 0
  fi

  SCHEME="$SCHEME" PROJECT="$PROJECT" ROOT="$ROOT" INSTALL_IOS_DEBUG="${INSTALL_IOS_DEBUG:-}" INSTALL_IOS_DEVICE_NAME="${INSTALL_IOS_DEVICE_NAME:-}" python3 <<'PY'
import json, os, re, subprocess, sys

scheme = os.environ["SCHEME"]
project = os.environ["PROJECT"]
root = os.environ["ROOT"]
debug = os.environ.get("INSTALL_IOS_DEBUG") == "1"
want_name = os.environ.get("INSTALL_IOS_DEVICE_NAME", "").strip().lower()


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
    name_re = re.compile(r"name:([^,}\]]+)")
    candidates: list[tuple[str, str]] = []
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
        # xcodebuild destinations use hardware-style ids (e.g. 00008140-…), not Core Device pairing UUIDs (0171B583-…).
        if not re.fullmatch(r"[0-9A-Fa-f-]{20,}", udid):
            continue
        if not udid.startswith("00008"):
            dbg(f"showdestinations skip non-hardware id: {udid}")
            continue
        nm_m = name_re.search(line)
        label = (nm_m.group(1).strip() if nm_m else "").lower()
        candidates.append((udid, label))

    if want_name:
        for udid, label in candidates:
            if want_name in label:
                dbg(f"showdestinations picked (name): {udid} ({label!r})")
                return udid
        dbg(f"showdestinations: no device name containing {want_name!r} among {candidates!r}")
        return None

    if candidates:
        udid, label = candidates[0]
        dbg(f"showdestinations picked: {udid} ({label!r}); set INSTALL_IOS_DEVICE_NAME if this is the wrong iPhone")
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
        if want_name and want_name not in line.lower():
            continue
        m = udid_re.search(line)
        if m:
            udid = m.group(1)
            dbg(f"xctrace picked: {udid} ({line.strip()})")
            return udid
    dbg("xctrace: no hardware row matched")
    return None


for picker in (pick_showdestinations, pick_xctrace, pick_devicectl):
    udid = picker()
    if udid:
        print(udid)
        sys.exit(0)

sys.exit(1)
PY
}

# Reads first non-empty DEVELOPMENT_TEAM assignment from project.pbxproj (if any).
read_team_from_pbxproj() {
  PBX="$ROOT/$PROJECT/project.pbxproj" python3 <<'PY'
import os, pathlib, re
p = pathlib.Path(os.environ["PBX"])
text = p.read_text(encoding="utf-8")
for line in text.splitlines():
    if "DEVELOPMENT_TEAM" not in line:
        continue
    m = re.search(r'DEVELOPMENT_TEAM\s*=\s*"?([A-Za-z0-9]{6,})"?', line)
    if m:
        print(m.group(1))
        raise SystemExit(0)
raise SystemExit(1)
PY
}

# Sets EXPORTED_DEVELOPMENT_TEAM and exports DEVELOPMENT_TEAM, or prints help and fails.
ensure_development_team() {
  if [[ -z "${DEVELOPMENT_TEAM:-}" ]]; then
    if t="$(read_team_from_pbxproj 2>/dev/null)" && [[ -n "$t" ]]; then
      export DEVELOPMENT_TEAM="$t"
    fi
  else
    export DEVELOPMENT_TEAM
  fi

  if [[ -z "${DEVELOPMENT_TEAM:-}" ]]; then
    echo "error: No Apple Development Team set — iphoneos builds must be signed." >&2
    echo "" >&2
    echo "Do one of the following once:" >&2
    echo "  A) Xcode → open MikeTodoList → target MikeTodoList → Signing & Capabilities → Team → choose your Personal Team." >&2
    echo "     (This writes DEVELOPMENT_TEAM into MikeTodoList.xcodeproj.)" >&2
    echo "  B) Or pass your Team ID on the command line (find it below):" >&2
    echo "     DEVELOPMENT_TEAM=XXXXXXXXXX bash ./scripts/install-ios-device.sh" >&2
    echo "" >&2
    echo "Team ID locations: Xcode → Settings → Accounts → select Apple ID → Team details," >&2
    echo "  or developer.apple.com → Account → Membership." >&2
    return 1
  fi
  echo "==> Signing: DEVELOPMENT_TEAM=${DEVELOPMENT_TEAM}"
}

build_for_device() {
  local device_id="$1"
  echo "==> xcodebuild build scheme=${SCHEME} sdk=iphoneos destination=id=${device_id}"
  local -a cmd=(
    xcodebuild
    -allowProvisioningUpdates
    -project "$PROJECT"
    -scheme "$SCHEME"
    -configuration Debug
    -sdk iphoneos
    -destination "platform=iOS,id=${device_id}"
    -derivedDataPath "$DERIVED"
    CODE_SIGN_STYLE=Automatic
    build
  )
  DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" "${cmd[@]}"
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
    echo "  • Hardware destination id from \`xcodebuild -showdestinations\` (000081xx-…) or Xcode → Devices:" >&2
    echo "      IOS_DEVICE_UDID='XXXXXXXX-…' bash ./scripts/install-ios-device.sh" >&2
    echo "  • Discovery debug:  INSTALL_IOS_DEBUG=1 bash ./scripts/install-ios-device.sh" >&2
    return 1
  fi

  echo "==> Device: ${udid}"
  ensure_development_team || return 1
  rm -rf "$DERIVED"
  build_for_device "$udid"
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
