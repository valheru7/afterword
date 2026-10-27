#!/bin/sh
# Signs Afterword.app from the inside out: every library and program in the bundle first, then
# the app. Signing only the app (or using --deep) would leave nested code unsigned or signed
# without the right entitlements, which notarization rejects.
#
#   sign-app.sh APP -          ad-hoc, for this Mac (make-app.sh)
#   sign-app.sh APP IDENTITY   Developer ID with the hardened runtime (release-app.sh)
#
# Entitlements, only where needed under the hardened runtime:
#   Afterword.app      audio-input: the microphone prompt for the recorder it starts.
#   afterword-capture  audio-input: it's the process that opens the microphone.
#   Python, whisper-cli, ffmpeg: none. Python loads only libraries signed here, by the same
#   identity, so it doesn't need disable-library-validation, and nothing in it generates code
#   at runtime, so it doesn't need allow-unsigned-executable-memory or allow-jit.
set -eu

app="$1"
identity="$2"
here="$(cd "$(dirname "$0")" && pwd)"

sign() {
    if [ "$identity" = "-" ]; then
        codesign --force --sign - "$@"
    else
        codesign --force --options runtime --timestamp --sign "$identity" "$@"
    fi
}

contents="$app/Contents"
python="$contents/Resources/python"
if [ -d "$python" ]; then
    # Libraries before the executable that loads them.
    find "$python" -type f \( -name "*.so" -o -name "*.dylib" \) | while read -r library; do
        sign "$library"
    done
    sign "$python/bin/python3.13"
fi
if [ -d "$contents/Helpers" ]; then
    sign "$contents/Helpers/whisper-cli"
    sign "$contents/Helpers/ffmpeg"
    sign --entitlements "$here/afterword-capture.entitlements" "$contents/Helpers/afterword-capture"
fi
sign --entitlements "$here/Afterword.entitlements" "$app"

codesign --verify --strict --deep --verbose=1 "$app"
