#!/usr/bin/env bash
set -euo pipefail

# Known-good iOS recovery sequence for Harmony User App.
# Uses existing Runner.app artifact and avoids IPA profile verification issues.

BUNDLE_ID="com.harmonybyintent.harmonyUserApp"
DEVICE_ID="${1:-00008110-0014749A3E39401E}"
APP_PATH="${2:-$PWD/build/ios/iphoneos/Runner.app}"

echo "[1/6] Device: $DEVICE_ID"

if ! xcrun devicectl list devices | grep -F "$DEVICE_ID" >/dev/null 2>&1 \
  && ! xcrun xcdevice list | grep -F "$DEVICE_ID" >/dev/null 2>&1; then
  echo "Device not visible: $DEVICE_ID"
  echo "Check cable, trust pairing, and Developer Mode."
  exit 1
fi

if [[ ! -d "$APP_PATH" ]]; then
  echo "Runner.app not found at: $APP_PATH"
  echo "Create it once with: flutter run -d $DEVICE_ID"
  exit 1
fi

echo "[2/6] Clearing stuck host-side iOS deploy processes (best effort)"
pkill -f "devicectl device (install|process launch|uninstall)" >/dev/null 2>&1 || true
pkill -f "flutter run -d $DEVICE_ID" >/dev/null 2>&1 || true

echo "[3/6] Checking lock state"
xcrun devicectl device info lockState --device "$DEVICE_ID" --timeout 20 >/dev/null

echo "[4/6] Uninstalling existing app (best effort)"
xcrun devicectl device uninstall app --device "$DEVICE_ID" "$BUNDLE_ID" --timeout 60 >/dev/null 2>&1 || true

echo "[5/6] Installing Runner.app"
xcrun devicectl device install app --device "$DEVICE_ID" "$APP_PATH"

echo "[6/6] Launching app"
xcrun devicectl device process launch --device "$DEVICE_ID" --terminate-existing "$BUNDLE_ID" >/dev/null

echo "Recovery complete: installed and launched $BUNDLE_ID on $DEVICE_ID"
