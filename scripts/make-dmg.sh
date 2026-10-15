#!/usr/bin/env bash
# Builds Textly.app (Release, Apple Silicon + Intel) and packs it into dist/Textly-<version>.dmg
#
#   scripts/make-dmg.sh         ad-hoc signed (no Apple certificate needed), same as the GitHub release
#   scripts/make-dmg.sh --dev   signed with your own Apple Development certificate (Xcode settings)
set -euo pipefail
cd "$(dirname "$0")/.."

BUILD_DIR="$PWD/build"
DIST_DIR="$PWD/dist"
# Default: build unsigned, then sign ad hoc ourselves. This avoids needing any certificate on the build machine.
ADHOC=1
SIGN_ARGS=(CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO "CODE_SIGN_IDENTITY=" "DEVELOPMENT_TEAM=")
if [[ "${1:-}" == "--dev" ]]; then ADHOC=0; SIGN_ARGS=(); fi

rm -rf "$BUILD_DIR"
mkdir -p "$DIST_DIR"

echo "Building Textly…"
xcodebuild -project Textly.xcodeproj -target Textly -configuration Release \
  SYMROOT="$BUILD_DIR" ONLY_ACTIVE_ARCH=NO ${SIGN_ARGS[@]+"${SIGN_ARGS[@]}"} -quiet build

APP="$BUILD_DIR/Release/Textly.app"
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
if [[ "$ADHOC" == 1 ]]; then
  echo "Signing ad hoc…"
  codesign --force --deep --options runtime --timestamp=none --sign - "$APP"
fi
codesign --verify --deep --strict "$APP"

STAGING=$(mktemp -d)
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

DMG="$DIST_DIR/Textly-$VERSION.dmg"
rm -f "$DMG"
hdiutil create -volname "Textly $VERSION" -srcfolder "$STAGING" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGING"

echo "Created $DMG"
