#!/bin/sh
# Builds the Afterword menu bar app and wraps it in build/Afterword.app.
#
# A menu bar app needs a bundle for its Info.plist (no Dock icon, and the microphone and system
# audio permission strings), and SwiftPM only builds the bare executable, so this assembles one.
# It's ad-hoc signed, which is enough to run it on the Mac that built it.
set -eu

cd "$(dirname "$0")"

swift build -c release
binary="$(swift build -c release --show-bin-path)/Afterword"

app="build/Afterword.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp "$binary" "$app/Contents/MacOS/Afterword"
cp Info.plist "$app/Contents/Info.plist"

codesign --force --sign - "$app"

echo "Built $(pwd)/$app"
