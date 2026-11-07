#!/bin/bash
# Build and install this local fork onto the USB-connected HarmonyOS device.
# macOS + DevEco Studio. This script is local-only and is NOT part of the upstream PR.
set -euo pipefail

usage() {
  printf '%s\n' \
    'Usage: scripts/dev-install.sh [options]' \
    '  (default)        fast ArkTS-only rebuild, then install' \
    '  --full           rebuild the Go core first via scripts/build.sh' \
    '  --launch         start EntryAbility after installing' \
    '  --no-install     build only, do not push to the device' \
    '  -h, --help       show this help'
}

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEV="${DEVECO_STUDIO_HOME:-/Applications/DevEco-Studio.app/Contents}"
HDC="$DEV/sdk/default/openharmony/toolchains/hdc"
HAP="$ROOT/entry/build/default/outputs/default/entry-default-signed.hap"

FULL=0
DO_INSTALL=1
LAUNCH=0
for arg in "$@"; do
  case "$arg" in
    --full) FULL=1 ;;
    --no-install) DO_INSTALL=0 ;;
    --launch) LAUNCH=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $arg" >&2; usage >&2; exit 2 ;;
  esac
done

[[ -d "$DEV/sdk" ]] || { echo "DevEco Studio SDK not found at $DEV. Set DEVECO_STUDIO_HOME." >&2; exit 1; }
[[ -x "$HDC" ]] || { echo "hdc not found at $HDC" >&2; exit 1; }
[[ -f "$ROOT/build-profile.json5" ]] || {
  echo 'Missing build-profile.json5; copy build-profile.example.json5 and configure signing.' >&2
  exit 1
}

# Never hardcode the bundle name: read it from AppScope/app.json5.
BUNDLE="$(python3 - "$ROOT/AppScope/app.json5" <<'PY'
import re, sys
m = re.search(r'"bundleName"\s*:\s*"([^"]+)"', open(sys.argv[1], encoding='utf-8').read())
print(m.group(1) if m else '')
PY
)"
[[ -n "$BUNDLE" ]] || { echo 'Could not read bundleName from AppScope/app.json5' >&2; exit 1; }

if (( DO_INSTALL )); then
  target="$("$HDC" list targets 2>/dev/null | awk 'NF && $0 !~ /^\[Empty\]/ { print $1; exit }' || true)"
  [[ -n "$target" ]] || { echo 'No device connected. Enable USB debugging and reconnect.' >&2; exit 1; }
  printf 'Device: %s\n' "$target"
fi
printf 'Bundle: %s\n' "$BUNDLE"

if (( FULL )); then
  echo '== full build (Go core + HAP) =='
  "$ROOT/scripts/build.sh"
else
  [[ -f "$ROOT/entry/libs/arm64-v8a/libtailscale_go.so" ]] || {
    echo 'Native library missing. Run scripts/dev-install.sh --full once.' >&2
    exit 1
  }
  mkdir -p "$ROOT/.tooling/node_modules/@ohos"
  ln -sfn "$DEV/tools/hvigor/hvigor" "$ROOT/.tooling/node_modules/@ohos/hvigor"
  ln -sfn "$DEV/tools/hvigor/hvigor-ohos-plugin" "$ROOT/.tooling/node_modules/@ohos/hvigor-ohos-plugin"
  export JAVA_HOME="$DEV/jbr/Contents/Home"
  export PATH="$JAVA_HOME/bin:$DEV/tools/node/bin:$PATH"
  export DEVECO_SDK_HOME="$DEV/sdk"
  export OHOS_SDK_HOME="$DEV/sdk"
  export HVIGOR_USER_HOME="$ROOT/.hvigor-user"
  unset NODE_PATH
  echo '== fast build (ArkTS only) =='
  ( cd "$ROOT" && node "$DEV/tools/hvigor/bin/hvigorw.js" \
      --mode module -p module=entry@default -p product=default \
      -p buildMode=debug -p debuggable=true assembleHap --no-daemon )
fi

[[ -f "$HAP" ]] || { echo "HAP not produced: $HAP" >&2; exit 1; }
printf 'HAP: %s\n' "$HAP"

if (( DO_INSTALL )); then
  "$HDC" install -r "$HAP"
  echo 'Installed.'
  if (( LAUNCH )); then
    "$HDC" shell "aa start -b $BUNDLE -a EntryAbility"
  fi
fi

cat <<'EOF'

Next: finish Tailscale login in the app, tap Connect, and accept the system VPN dialog.
Note: this HAP is signed with a debug certificate/profile bound to ONE device UDID,
so it cannot be published or installed on other devices. See docs/local-fork.md.
EOF
