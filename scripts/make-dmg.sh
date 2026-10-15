#!/usr/bin/env bash
# Builds Textly.app (Release, Apple Silicon + Intel) and packs it into dist/Textly-<version>.dmg
#
#   scripts/make-dmg.sh         ad-hoc signed, same as the GitHub release
#   scripts/make-dmg.sh --dev   signed with your own Apple Development certificate
set -euo pipefail
cd "$(dirname "$0")/.."

BUILD_DIR="$PWD/build"
DIST_DIR="$PWD/dist"
SIGN_ARGS=(CODE_SIGN_STYLE=Manual "CODE_SIGN_IDENTITY=-" "CODE_SIGN_IDENTITY[sdk=macosx*]=-" "DEVELOPMENT_TEAM=")
if [[ "${1:-}" == "--dev" ]]; then SIGN_ARGS=(); fi

rm -rf "$BUILD_DIR"
mkdir -p "$DIST_DIR"

echo "Building Textly…"
xcodebuild -project Textly.xcodeproj -target Textly -configuration Release \
  SYMROOT="$BUILD_DIR" ONLY_ACTIVE_ARCH=NO ${SIGN_ARGS[@]+"${SIGN_ARGS[@]}"} -quiet build

APP="$BUILD_DIR/Release/Textly.app"
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
codesign --verify --deep --strict "$APP"

STAGING=$(mktemp -d)
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

DMG="$DIST_DIR/Textly-$VERSION.dmg"
rm -f "$DMG"
hdiutil create -volname "Textly $VERSION" -srcfolder "$STAGING" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGING"

echo "Created $DMG"
