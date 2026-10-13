#!/usr/bin/env bash
# Builds dist/Atmospherics-<version>.dmg, for downloading from GitHub: the Mac app archived for
# Apple Silicon and Intel, signed with your Developer ID, notarized by Apple and stapled. Then signs
# it for Sparkle and writes dist/appcast.xml, the update feed, to attach to the release with it:
#   NOTES=notes.md ./scripts/package-mac.sh  # full release (NOTES: the release notes, optional)
#   ./scripts/package-mac.sh --no-notarize   # signed, not notarized (quick local check)
#   gh release create v<version> dist/Atmospherics-<version>.dmg dist/appcast.xml --notes-file notes.md
# Every release needs its appcast.xml: the app reads the feed from the latest release.
# The Sparkle key is in the login keychain as "atmospherics" (made with Sparkle's generate_keys
# --account atmospherics; back it up with generate_keys --account atmospherics -x <file>).
# Needs: the Developer ID certificate in your keychain, and a notarytool profile for the team
# (xcrun notarytool store-credentials <name> --apple-id … --team-id S3RY6Q3EW2). NOTARY_PROFILE
# picks it (default "onramp", the one Onramp's releases use); IDENTITY overrides the certificate.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IDENTITY="${IDENTITY:-Developer ID Application: Timothy Wheeler (S3RY6Q3EW2)}"
PROFILE="${NOTARY_PROFILE:-onramp}"
NOTARIZE=1; [ "${1:-}" = "--no-notarize" ] && NOTARIZE=0
DIST="$ROOT/dist"
ARCHIVE="$DIST/AtmosphericsMac.xcarchive"
PACKAGES="$ROOT/build/SourcePackages"
SPARKLE="$PACKAGES/artifacts/sparkle/Sparkle/bin"
step() { printf '\n==> %s\n' "$1"; }

step "Archive (Apple Silicon + Intel)"
rm -rf "$DIST" && mkdir -p "$DIST"
xcodebuild -project "$ROOT/Atmospherics.xcodeproj" -scheme AtmosphericsMac -configuration Release \
  -destination 'generic/platform=macOS' -archivePath "$ARCHIVE" -clonedSourcePackagesDirPath "$PACKAGES" \
  -allowProvisioningUpdates archive \
  > "$DIST/archive.log" 2>&1 || { tail -30 "$DIST/archive.log"; exit 1; }

step "Export, signed with your Developer ID"
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist "$ROOT/scripts/ExportOptions-DeveloperID.plist" \
  -exportPath "$DIST/export" -allowProvisioningUpdates > "$DIST/export.log" 2>&1 || { tail -30 "$DIST/export.log"; exit 1; }
APP="$DIST/export/Atmospherics.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")"
DMG="$DIST/Atmospherics-$VERSION.dmg"
lipo -info "$APP/Contents/MacOS/Atmospherics"
codesign --verify --strict --deep --verbose=2 "$APP"

# The app is notarized and stapled on its own too, so it opens offline once it's copied out.
if [ "$NOTARIZE" = 1 ]; then
  step "Notarize the app (Apple, usually 1-5 minutes)"
  ditto -c -k --keepParent "$APP" "$DIST/notarize.zip"
  xcrun notarytool submit "$DIST/notarize.zip" --keychain-profile "$PROFILE" --wait
  xcrun stapler staple "$APP"
  rm -f "$DIST/notarize.zip"
fi

step "Make the DMG"
STAGE="$DIST/dmg"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -quiet -volname "Atmospherics" -srcfolder "$STAGE" -fs HFS+ -format UDZO -imagekey zlib-level=9 -ov "$DMG"
rm -rf "$STAGE"
codesign --force --timestamp --sign "$IDENTITY" "$DMG"

if [ "$NOTARIZE" = 1 ]; then
  step "Notarize the DMG"
  xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
  xcrun stapler staple "$DMG"
  step "Gatekeeper check"
  spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
  spctl --assess --type execute --verbose=2 "$APP"
fi

# Signed last, once stapling has finished changing the DMG.
step "Sign the update and write its feed"
SIGNED="$("$SPARKLE/sign_update" --account atmospherics "$DMG")"
SIGNATURE="$(sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p' <<< "$SIGNED")"
LENGTH="$(sed -n 's/.*length="\([0-9]*\)".*/\1/p' <<< "$SIGNED")"
python3 -I "$ROOT/scripts/appcast.py" "$VERSION" "$BUILD" "$DMG" "$SIGNATURE" "$LENGTH" ${NOTES:+"$NOTES"} > "$DIST/appcast.xml"
"$SPARKLE/sign_update" --account atmospherics --verify "$DMG" "$SIGNATURE"

step "Done: $DMG ($(du -h "$DMG" | cut -f1)) and $DIST/appcast.xml"
