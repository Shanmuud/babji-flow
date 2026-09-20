#!/bin/zsh
# Run on an Apple Silicon Mac to produce the native app distribution.
set -euo pipefail
cd "$(dirname "$0")"
[[ "$(uname -s)" == Darwin && "$(uname -m)" == arm64 ]] || { echo "Build the Mac package on an Apple Silicon Mac."; exit 1; }
./build.sh
VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist 2>/dev/null || echo '0.1.0')
STAGE=$(mktemp -d "${TMPDIR:-/tmp}/babji-dmg.XXXXXX")
ditto build/BabjiFlow.app "$STAGE/BabjiFlow.app"
ln -s /Applications "$STAGE/Applications"
mkdir -p build/releases
hdiutil create -volname "Babji Flow" -srcfolder "$STAGE" -ov -format UDZO "build/releases/BabjiFlow-${VERSION}-macos-arm64.dmg"
echo "Mac DMG created. Public distribution signing and notarization are separate release steps."
