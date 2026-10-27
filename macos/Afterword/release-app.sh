#!/bin/sh
# Builds Afterword.app for a GitHub release: signed with a Developer ID, notarized by Apple and
# zipped, so it opens on other Macs without Gatekeeper blocking it. For your own Mac,
# make-app.sh is enough.
#
# One-time setup (needs an Apple Developer Program membership):
#   1. Create a "Developer ID Application" certificate (developer.apple.com → Certificates)
#      and install it in your login keychain. `security find-identity -v -p codesigning`
#      shows its full name.
#   2. Save notary credentials in the keychain, using an app-specific password from
#      account.apple.com:
#        xcrun notarytool store-credentials afterword-notary \
#          --apple-id you@example.com --team-id TEAMID
#
# Then: DEVELOPER_ID="Developer ID Application: Your Name (TEAMID)" macos/Afterword/release-app.sh
set -eu

: "${DEVELOPER_ID:?Set DEVELOPER_ID to your 'Developer ID Application: Name (TEAMID)' identity}"
notary_profile="${NOTARY_PROFILE:-afterword-notary}"

cd "$(dirname "$0")"
./make-app.sh

app="build/Afterword.app"
# Notarization requires the hardened runtime. Under it, a microphone prompt for the recorder
# the app starts is only allowed if the app has the audio-input entitlement.
codesign --force --options runtime --timestamp --entitlements Afterword.entitlements \
    --sign "$DEVELOPER_ID" "$app"
codesign --verify --strict --verbose=2 "$app"

version="$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$app/Contents/Info.plist")"
zip="build/Afterword-$version.zip"
rm -f "$zip"
ditto -c -k --keepParent "$app" "$zip"
xcrun notarytool submit "$zip" --keychain-profile "$notary_profile" --wait

# Stapling attaches Apple's ticket to the app so Gatekeeper can check it offline. The zip
# that was uploaded doesn't have it, so zip the stapled app again.
xcrun stapler staple "$app"
rm "$zip"
ditto -c -k --keepParent "$app" "$zip"
spctl --assess --type execute --verbose "$app"

echo "Ready to attach to a GitHub release: $(pwd)/$zip"
