#!/bin/sh
# Builds the Afterword menu bar app as build/Afterword.app, with everything it needs inside:
#
#   Contents/MacOS/Afterword        the menu bar app
#   Contents/Resources/python/      Python with afterword and its dependencies
#   Contents/Resources/afterword    runs that copy from Terminal (see the README)
#   Contents/Resources/licenses/    notices for everything bundled
#   Contents/Helpers/               whisper-cli, ffmpeg and afterword-capture
#
# bundle-tools.sh builds the bundled parts (several minutes the first time, seconds after).
# A menu bar app needs a bundle for its Info.plist (no Dock icon, and the microphone and system
# audio permission strings), and SwiftPM only builds the bare executable, so this assembles one.
# It's ad-hoc signed, which is enough to run it on the Mac that built it; release-app.sh signs
# it for other Macs.
set -eu

cd "$(dirname "$0")"

./bundle-tools.sh

swift build -c release
binary="$(swift build -c release --show-bin-path)/Afterword"

app="build/Afterword.app"
contents="$app/Contents"
rm -rf "$app"
mkdir -p "$contents/MacOS" "$contents/Resources" "$contents/Helpers"
cp "$binary" "$contents/MacOS/Afterword"
cp Info.plist "$contents/Info.plist"
# ditto keeps Python's symlinks (bin/python3 → python3.13) as symlinks.
ditto build/bundle/python "$contents/Resources/python"
ditto build/bundle/licenses "$contents/Resources/licenses"
cp afterword-shim.sh "$contents/Resources/afterword"
cp build/bundle/bin/whisper-cli build/bundle/bin/ffmpeg build/bundle/bin/afterword-capture "$contents/Helpers/"

./sign-app.sh "$app" -

echo "Built $(pwd)/$app ($(du -sh "$app" | cut -f 1))"
