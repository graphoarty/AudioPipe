#!/bin/sh
# Builds a universal (Apple silicon + Intel) Release AudioPipe.app signed with
# the Quinston Pimenta team's Developer ID, packages it as
# build/Release/AudioPipe-<version>.dmg (with an Applications shortcut), signs
# the DMG, and notarizes and staples it so it opens without Gatekeeper warnings.
#
# One-time setup:
#   1. A "Developer ID Application" certificate for team Q694HU5XXH in your
#      keychain (Xcode → Settings → Accounts → Manage Certificates → +).
#   2. Notarization credentials saved in your keychain:
#        xcrun notarytool store-credentials AudioPipe-notary \
#          --apple-id <your Apple ID email> --team-id Q694HU5XXH
#      (it asks for an app-specific password from account.apple.com).
#
# Set NOTARY_PROFILE to use another credentials profile name, or SKIP_NOTARIZE=1
# to stop after signing.
set -eu

TEAM_ID="Q694HU5XXH"
NOTARY_PROFILE="${NOTARY_PROFILE:-AudioPipe-notary}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

IDENTITY=$(security find-identity -v -p codesigning | grep "Developer ID Application" | grep "($TEAM_ID)" | head -1 | sed -E 's/.*"(.*)"/\1/' || true)
if [ -z "$IDENTITY" ]; then
  echo "No \"Developer ID Application\" certificate for team $TEAM_ID in your keychain." >&2
  echo "Create one in Xcode → Settings → Accounts → Manage Certificates → + → Developer ID Application." >&2
  exit 1
fi
echo "Signing with: $IDENTITY"

xcodegen generate
xcodebuild -project AudioPipe.xcodeproj -scheme AudioPipe -configuration Release \
  -derivedDataPath build/DerivedData ONLY_ACTIVE_ARCH=NO \
  ARCHS="arm64 x86_64" build | grep -E "error:|BUILD (SUCCEEDED|FAILED)"

APP="build/DerivedData/Build/Products/Release/AudioPipe.app"
codesign --verify --strict "$APP"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
OUT="build/Release"
STAGE="$OUT/dmg-staging"
DMG="$OUT/AudioPipe-$VERSION.dmg"
mkdir -p "$OUT"

# Submits a file to Apple's notary service and fails unless it's accepted.
notarize() {
  result=$(xcrun notarytool submit "$1" --keychain-profile "$NOTARY_PROFILE" --wait 2>&1) || true
  echo "$result" | grep -E "id:|status:" | tail -2
  if ! echo "$result" | grep -q "status: Accepted"; then
    id=$(echo "$result" | awk '/id:/{print $2; exit}')
    echo "Notarization of $1 failed. Details: xcrun notarytool log $id --keychain-profile $NOTARY_PROFILE" >&2
    exit 1
  fi
}

# Notarize and staple the app itself first, so a copy dragged into
# Applications carries its own ticket and opens even when offline.
if [ "${SKIP_NOTARIZE:-0}" != "1" ]; then
  ZIP="$OUT/AudioPipe-$VERSION-app.zip"
  ditto -c -k --keepParent "$APP" "$ZIP"
  echo "Notarizing the app…"
  notarize "$ZIP"
  rm -f "$ZIP"
  xcrun stapler staple "$APP"
fi

rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/AudioPipe.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "AudioPipe $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
rm -rf "$STAGE"
codesign --sign "$IDENTITY" --timestamp "$DMG"
echo "Built and signed $DMG"

if [ "${SKIP_NOTARIZE:-0}" = "1" ]; then
  echo "Skipping notarization (SKIP_NOTARIZE=1)."
else
  echo "Notarizing the DMG…"
  notarize "$DMG"
  xcrun stapler staple "$DMG"
  spctl --assess --type open --context context:primary-signature -v "$DMG"
  # Apple's own pre-distribution check on the app as it ships in the DMG.
  MP=$(hdiutil attach -readonly -nobrowse -noautoopen "$DMG" | awk -F'\t' '/\/Volumes\//{print $NF}')
  syspolicy_check distribution "$MP/AudioPipe.app" | grep -E "passed|failed" || true
  hdiutil detach "$MP" -quiet
fi

shasum -a 256 "$DMG"
