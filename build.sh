#!/bin/zsh
# Builds BabjiFlow.app into ./build using SwiftPM (no Xcode required).
set -euo pipefail
cd "$(dirname "$0")"
CONFIG=${1:-release}
./Vendor/fetch-nemo.sh
echo "▸ swift build -c $CONFIG"
swift build -c "$CONFIG" --product BabjiFlow 2>&1 | grep -v "^\[" || true
BIN=".build/$CONFIG/BabjiFlow"
[ -x "$BIN" ] || { echo "build failed"; exit 1; }
APP="build/BabjiFlow.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/BabjiFlow"
cp Resources/Info.plist "$APP/Contents/Info.plist"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp -R Resources/Babji "$APP/Contents/Resources/Babji"
cp -R Resources/Scenes "$APP/Contents/Resources/Scenes"
# SwiftPM resource bundles (FluidAudio ships one)
for b in .build/$CONFIG/*.bundle; do [ -d "$b" ] && cp -R "$b" "$APP/Contents/Resources/"; done
# Sign with the stable local identity (see sign-setup.sh) so permission grants survive rebuilds;
# fall back to ad-hoc.
if security find-identity -v -p codesigning 2>/dev/null | grep -q "Babji Flow Dev"; then
  # Explicit designated requirement pinned to the cert so TCC treats every rebuild as the same app.
  HASH=$(security find-identity -v -p codesigning | grep "Babji Flow Dev" | awk '{print $2}' | head -1)
  codesign --force --deep --sign "Babji Flow Dev" --identifier com.babji.flow \
    --requirements "=designated => identifier \"com.babji.flow\" and certificate leaf = H\"$HASH\"" "$APP" 2>&1 | grep -v "replacing existing" || true
else
  ./sign-setup.sh >/dev/null 2>&1 && codesign --force --deep --sign "Babji Flow Dev" --identifier com.babji.flow "$APP" 2>/dev/null \
    || codesign --force --deep --sign - --identifier com.babji.flow "$APP" >/dev/null 2>&1 || true
fi
echo "✓ $APP"
