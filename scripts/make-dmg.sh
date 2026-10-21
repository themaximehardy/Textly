#!/usr/bin/env bash
# Builds Textly.app (Release, Apple Silicon + Intel) and packs it into dist/Textly-<version>.dmg
#
#   scripts/make-dmg.sh         signed ad hoc (no Apple certificate needed)
#   scripts/make-dmg.sh --dev   signed with your own Apple Development certificate (Xcode settings)
#
# Signed with a Developer ID and notarised by Apple when these are set (GitHub Actions sets them from secrets):
#   SIGN_IDENTITY      e.g. "Developer ID Application: Max Hardy (ABCDE12345)", in an unlocked keychain
#   NOTARY_KEY_PATH    path to the App Store Connect API key (.p8)
#   NOTARY_KEY_ID      its Key ID
#   NOTARY_ISSUER_ID   its Issuer ID
set -euo pipefail
cd "$(dirname "$0")/.."

BUILD_DIR="$PWD/build"
DIST_DIR="$PWD/dist"
MODE=adhoc
if [[ -n "${SIGN_IDENTITY:-}" ]]; then MODE=developer-id; fi
if [[ "${1:-}" == "--dev" ]]; then MODE=dev; fi

SIGN_ARGS=(CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO "CODE_SIGN_IDENTITY=" "DEVELOPMENT_TEAM=")
if [[ "$MODE" == dev ]]; then SIGN_ARGS=(); fi

rm -rf "$BUILD_DIR"
mkdir -p "$DIST_DIR"

echo "Building Textly…"
xcodebuild -project Textly.xcodeproj -target Textly -configuration Release \
  SYMROOT="$BUILD_DIR" ONLY_ACTIVE_ARCH=NO ${SIGN_ARGS[@]+"${SIGN_ARGS[@]}"} -quiet build

APP="$BUILD_DIR/Release/Textly.app"
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")

notarize() {
  # Sends a file to Apple's notary service and waits for the answer (usually 1 to 5 minutes).
  xcrun notarytool submit "$1" \
    --key "$NOTARY_KEY_PATH" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID" \
    --wait --timeout 30m
}

case "$MODE" in
  adhoc)
    echo "Signing ad hoc…"
    codesign --force --deep --options runtime --timestamp=none --sign - "$APP"
    ;;
  developer-id)
    echo "Signing with $SIGN_IDENTITY…"
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
    ;;
esac
codesign --verify --deep --strict --verbose=2 "$APP"

if [[ "$MODE" == developer-id && -n "${NOTARY_KEY_PATH:-}" ]]; then
  echo "Notarising the app…"
  ZIP="$BUILD_DIR/Textly-notarize.zip"
  ditto -c -k --keepParent "$APP" "$ZIP"
  notarize "$ZIP"
  xcrun stapler staple "$APP"
  spctl --assess --type execute --verbose=2 "$APP"
fi

STAGING=$(mktemp -d)
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

DMG="$DIST_DIR/Textly-$VERSION.dmg"
rm -f "$DMG"
hdiutil create -volname "Textly $VERSION" -srcfolder "$STAGING" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGING"

if [[ "$MODE" == developer-id ]]; then
  codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"
  if [[ -n "${NOTARY_KEY_PATH:-}" ]]; then
    echo "Notarising the disk image…"
    notarize "$DMG"
    xcrun stapler staple "$DMG"
    spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
  fi
fi

echo "Created $DMG ($MODE)"
