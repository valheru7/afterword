#!/bin/sh
# Runs Afterword.app's own copy of the `afterword` command, for use in Terminal. To use it as
# `afterword`, link it onto your PATH:
#   ln -s /Applications/Afterword.app/Contents/Resources/afterword ~/.local/bin/afterword
resources="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
helpers="$(dirname "$resources")/Helpers"
PATH="$helpers:$PATH" AFTERWORD_CAPTURE_BIN="$helpers/afterword-capture" \
    exec "$resources/python/bin/python3" -I -B -X utf8 -m afterword.cli "$@"
