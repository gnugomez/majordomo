#!/bin/sh
# Assembles a runnable Majordomo.app from the SPM build:
#   scripts/bundle.sh [--debug]
# Output: dist/Majordomo.app, signed with $CODESIGN_IDENTITY when set
# (ad-hoc otherwise). $MACOS_PROVISION_PROFILE, when it points at a
# provisioning profile, is embedded and unlocks the time-sensitive
# notification entitlement.
set -eu

cd "$(dirname "$0")/.."

CONFIG=release
if [ "${1:-}" = "--debug" ]; then
  CONFIG=debug
fi

swift build -c "$CONFIG"

BIN=".build/$CONFIG/Majordomo"
BUNDLE=".build/$CONFIG/Majordomo_Majordomo.bundle"
APP="dist/Majordomo.app"
VERSION=$(cat version.txt)

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN" "$APP/Contents/MacOS/Majordomo"
# The SPM resource bundle (tray icons) rides along; Bundle.module finds it
# in Contents/Resources.
cp -R "$BUNDLE" "$APP/Contents/Resources/"
cp assets/appicon.icns "$APP/Contents/Resources/appicon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleExecutable</key><string>Majordomo</string>
  <key>CFBundleIconFile</key><string>appicon</string>
  <key>CFBundleIdentifier</key><string>dev.majordomo.app</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>Majordomo</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION:-0.0.0}</string>
  <key>CFBundleVersion</key><string>${VERSION:-0.0.0}</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSSupportsAutomaticGraphicsSwitching</key><true/>
</dict>
</plist>
PLIST

# Apple restricts the time-sensitive notification entitlement: it counts
# only when the signature is backed by a provisioning profile granting it,
# and an app carrying it without one is killed at launch. So the
# entitlement rides along with the profile and never on its own — an
# ad-hoc or self-signed build simply delivers Urgent banners at the normal
# level.
PROFILE="${MACOS_PROVISION_PROFILE:-}"
if [ -n "$PROFILE" ]; then
  if [ ! -f "$PROFILE" ]; then
    echo "MACOS_PROVISION_PROFILE is set but $PROFILE does not exist" >&2
    exit 1
  fi
  cp "$PROFILE" "$APP/Contents/embedded.provisionprofile"
  codesign --force --sign "${CODESIGN_IDENTITY:--}" \
    --entitlements macos/Majordomo.entitlements "$APP"
  echo "Signed with $PROFILE; time-sensitive notifications enabled"
else
  codesign --force --sign "${CODESIGN_IDENTITY:--}" "$APP"
fi

echo "Built $APP"
echo "Run it with: open $APP"
