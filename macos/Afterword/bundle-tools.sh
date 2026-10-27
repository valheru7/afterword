#!/bin/sh
# Builds everything Afterword.app carries so it works without Homebrew, uv or a terminal:
#
#   build/bundle/python/          a relocatable Python with afterword and its locked dependencies
#   build/bundle/bin/whisper-cli  whisper.cpp, built with Metal, no dylibs
#   build/bundle/bin/ffmpeg       a small LGPL ffmpeg: decodes audio, resamples, silencedetect
#   build/bundle/bin/afterword-capture
#   build/bundle/licenses/        notices for everything above
#
# make-app.sh runs this. Downloads are pinned and checked against SHA-256 sums, and whisper.cpp
# and ffmpeg are only rebuilt when their version changes, so after the first run (several
# minutes) it takes seconds. Apple Silicon only.
set -eu

# MARK: Pinned versions

PYTHON_RELEASE="20261009"
PYTHON_VERSION="3.13.16"
PYTHON_ARCHIVE="cpython-$PYTHON_VERSION+$PYTHON_RELEASE-aarch64-apple-darwin-install_only_stripped.tar.gz"
PYTHON_SHA256="11785155d0f70e634178219c20925d8f20be00a3da4684fc4f5019dd15602ef7"
PYTHON_URL="https://github.com/astral-sh/python-build-standalone/releases/download/$PYTHON_RELEASE/$PYTHON_ARCHIVE"
# The same build's full archive, only for its licenses/ folder: the notices for OpenSSL, SQLite,
# libffi and the other libraries built into Python, which the smaller archive leaves out.
PYTHON_FULL_ARCHIVE="cpython-$PYTHON_VERSION+$PYTHON_RELEASE-aarch64-apple-darwin-pgo+lto-full.tar.zst"
PYTHON_FULL_SHA256="70025edd2ed4bf0a333677928ded047368726954253b6e428732e71e9c5a163e"
PYTHON_FULL_URL="https://github.com/astral-sh/python-build-standalone/releases/download/$PYTHON_RELEASE/$PYTHON_FULL_ARCHIVE"

WHISPER_TAG="v1.9.5"
WHISPER_COMMIT="d1be6fde11ac6e0407606b4e42fe72d34add8037"
WHISPER_REPO="https://github.com/ggml-org/whisper.cpp.git"

FFMPEG_VERSION="9.0.2"
FFMPEG_SHA256="8c3850283eb25fa026482078a04051e0be17347b09ef81a0849bec15a96e002e"
FFMPEG_URL="https://ffmpeg.org/releases/ffmpeg-$FFMPEG_VERSION.tar.xz"

# The afterword wheel is built with hatchling from wheel-build-requirements.txt, and its runtime
# dependencies come from uv.lock, both checked against hashes.

MACOS_MIN="14.4"

# MARK: Setup

here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/../.." && pwd)"
build="$here/build"
downloads="$build/downloads"
sources="$build/sources"
tools="$build/tools"    # Cached whisper-cli and ffmpeg, rebuilt only when their version changes.
bundle="$build/bundle"  # What make-app.sh copies into the app.
jobs="$(sysctl -n hw.ncpu)"

if [ "$(uname -m)" != "arm64" ]; then
    echo "bundle-tools.sh builds for Apple Silicon (arm64) only." >&2
    exit 1
fi
mkdir -p "$downloads" "$sources" "$tools"

# download URL FILE SHA256: fetches once, and refuses a file whose checksum doesn't match.
download() {
    url="$1"; file="$downloads/$2"; expected="$3"
    if [ ! -f "$file" ]; then
        echo "Downloading ${2}…"
        curl --fail --location --silent --show-error --output "$file.part" "$url"
        mv "$file.part" "$file"
    fi
    actual="$(shasum -a 256 "$file" | cut -d ' ' -f 1)"
    if [ "$actual" != "$expected" ]; then
        echo "Checksum mismatch for $2: expected $expected, got $actual" >&2
        rm -f "$file"
        exit 1
    fi
}

# options_id OPTIONS: a short hash of a build's options, so changing any of them rebuilds.
options_id() {
    printf '%s' "$1" | shasum -a 256 | cut -c 1-12
}

# MARK: whisper.cpp

# Static, so there are no dylibs to bundle and rpath-fix. The Metal shaders are embedded in the
# binary instead of loaded from a file next to it. GGML_NATIVE=OFF targets every Apple Silicon
# Mac, not just the CPU this happens to be built on. (No option contains a space, so the list is
# split on whitespace below.)
WHISPER_CMAKE_OPTIONS="
    -DCMAKE_BUILD_TYPE=Release
    -DCMAKE_OSX_DEPLOYMENT_TARGET=$MACOS_MIN
    -DCMAKE_OSX_ARCHITECTURES=arm64
    -DBUILD_SHARED_LIBS=OFF
    -DGGML_NATIVE=OFF
    -DGGML_METAL=ON
    -DGGML_METAL_EMBED_LIBRARY=ON
    -DWHISPER_BUILD_TESTS=OFF
    -DWHISPER_SDL2=OFF
    -DWHISPER_CURL=OFF
"
whisper_stamp="$tools/whisper-cli.$WHISPER_COMMIT.$(options_id "$WHISPER_CMAKE_OPTIONS")"
if [ ! -f "$whisper_stamp" ]; then
    echo "Building whisper.cpp ${WHISPER_TAG}…"
    rm -rf "$sources/whisper.cpp" "$tools"/whisper-cli*
    git clone --quiet --depth 1 --branch "$WHISPER_TAG" "$WHISPER_REPO" "$sources/whisper.cpp"
    actual="$(git -C "$sources/whisper.cpp" rev-parse HEAD)"
    if [ "$actual" != "$WHISPER_COMMIT" ]; then
        echo "whisper.cpp $WHISPER_TAG is commit $actual, expected $WHISPER_COMMIT" >&2
        exit 1
    fi
    # shellcheck disable=SC2086  # Split into separate options on purpose.
    cmake -S "$sources/whisper.cpp" -B "$sources/whisper.cpp/build" $WHISPER_CMAKE_OPTIONS \
        > "$sources/whisper-configure.log"
    cmake --build "$sources/whisper.cpp/build" --target whisper-cli -j "$jobs" > "$sources/whisper-build.log"
    cp "$sources/whisper.cpp/build/bin/whisper-cli" "$tools/whisper-cli"
    cp "$sources/whisper.cpp/LICENSE" "$tools/whisper-cli.LICENSE"
    touch "$whisper_stamp"
fi

# MARK: ffmpeg

# Only what src/afterword/transcribe.py asks of it: read the recorder's m4a files and the common
# audio and video formats `afterword import` takes, convert to 16 kHz mono WAV, and run
# silencedetect. No GPL or non-free parts (LGPL 2.1), no network, and no autodetected libraries,
# so it links nothing outside macOS itself.
FFMPEG_CONFIGURE_OPTIONS="
    --cc=clang
    --arch=arm64
    --extra-cflags=-mmacosx-version-min=$MACOS_MIN
    --extra-ldflags=-mmacosx-version-min=$MACOS_MIN
    --enable-static --disable-shared
    --disable-autodetect --disable-network --disable-doc --disable-debug
    --disable-ffplay --disable-ffprobe
    --disable-everything
    --enable-protocol=file,pipe
    --enable-demuxer=mov,matroska,ogg,mp3,wav,aiff,flac,aac,caf,w64
    --enable-parser=aac,mpegaudio,opus,vorbis,flac
    --enable-decoder=aac,aac_latm,mp3,mp3float,opus,vorbis,flac,alac
    --enable-decoder=pcm_s16le,pcm_s16be,pcm_s24le,pcm_s24be,pcm_s32le,pcm_f32le,pcm_f32be,pcm_u8
    --enable-encoder=pcm_s16le
    --enable-muxer=wav,null
    --enable-filter=abuffer,abuffersink,aformat,anull,aresample,silencedetect
"
ffmpeg_stamp="$tools/ffmpeg.$FFMPEG_VERSION.$(options_id "$FFMPEG_CONFIGURE_OPTIONS")"
if [ ! -f "$ffmpeg_stamp" ]; then
    echo "Building ffmpeg ${FFMPEG_VERSION}…"
    download "$FFMPEG_URL" "ffmpeg-$FFMPEG_VERSION.tar.xz" "$FFMPEG_SHA256"
    rm -rf "$sources/ffmpeg-$FFMPEG_VERSION" "$tools"/ffmpeg*
    tar -xf "$downloads/ffmpeg-$FFMPEG_VERSION.tar.xz" -C "$sources"
    (
        cd "$sources/ffmpeg-$FFMPEG_VERSION"
        # shellcheck disable=SC2086  # Split into separate options on purpose.
        ./configure $FFMPEG_CONFIGURE_OPTIONS > "$sources/ffmpeg-configure.log"
        make -j "$jobs" ffmpeg > "$sources/ffmpeg-build.log" 2>&1
        cp ffmpeg "$tools/ffmpeg"
        cp COPYING.LGPLv2.1 "$tools/ffmpeg.LICENSE"
    )
    touch "$ffmpeg_stamp"
fi

# MARK: afterword-capture

echo "Building afterword-capture…"
swift build -c release --package-path "$repo/macos/afterword-capture" > /dev/null
capture="$(swift build -c release --package-path "$repo/macos/afterword-capture" --show-bin-path)/afterword-capture"

# MARK: Python with afterword

# Rebuilt every time so the app always carries the current source.
echo "Installing afterword into the bundled Python…"
download "$PYTHON_URL" "$PYTHON_ARCHIVE" "$PYTHON_SHA256"
rm -rf "$bundle"
mkdir -p "$bundle/bin" "$bundle/licenses"
tar -xzf "$downloads/$PYTHON_ARCHIVE" -C "$bundle"
python="$bundle/python/bin/python3"
stdlib="$bundle/python/lib/python3.13"

# Parts of the standard library a command-line tool never uses: the test suite, Tk and IDLE,
# and the headers and static library for building extensions.
rm -rf "$stdlib/test" "$stdlib/idlelib" "$stdlib/tkinter" "$stdlib/turtledemo" "$stdlib/ensurepip" \
    "$stdlib"/lib-dynload/_tkinter* "$stdlib"/config-3.13-darwin \
    "$bundle/python/include" "$bundle/python/share" "$bundle/python/lib"/tcl* "$bundle/python/lib"/tk* \
    "$bundle/python/lib"/itcl* "$bundle/python/lib"/thread* "$bundle/python/lib/pkgconfig" \
    "$bundle/python/lib"/libtcl* "$bundle/python/lib"/libtk*
# python-build-standalone may mark itself as "externally managed"; this copy is ours to install into.
rm -f "$stdlib/EXTERNALLY-MANAGED"

requirements="$build/requirements.txt"
(cd "$repo" && uv export --quiet --frozen --no-dev --no-emit-project --no-header --output-file "$requirements")
uv pip install --quiet --no-config --python "$python" --require-hashes --requirement "$requirements"

# Build the wheel in a separate environment with hash-checked hatchling (uv's usual isolated
# build would fetch whatever hatchling it resolves), so the bundle doesn't carry hatchling.
wheel_env="$build/wheel-build-env"
rm -rf "$wheel_env" "$build/wheel"
uv venv --quiet --no-config --python "$python" "$wheel_env"
uv pip install --quiet --no-config --python "$wheel_env/bin/python" --require-hashes \
    --requirement "$here/wheel-build-requirements.txt"
uv build --quiet --no-config --wheel --no-build-isolation --python "$wheel_env/bin/python" \
    --out-dir "$build/wheel" "$repo"
uv pip install --quiet --no-config --python "$python" --no-deps --reinstall "$build/wheel"/afterword-*.whl

# pip isn't needed (uv did the installing), and the other scripts in bin/ have this build
# folder's path in their #! line. The app runs `python3 -m afterword.cli`.
rm -rf "$stdlib"/site-packages/pip "$stdlib"/site-packages/pip-*.dist-info
find "$bundle/python/bin" -mindepth 1 ! -name python3 ! -name python3.13 -exec rm -f {} +

# Compile every module now. The app runs Python with -B so it never writes __pycache__ into the
# bundle (that would break the code signature); unchecked-hash .pyc files load without
# comparing timestamps, which copying the bundle around can change.
"$python" -I -m compileall -q -j 0 --invalidation-mode unchecked-hash "$bundle/python/lib"

cp "$tools/whisper-cli" "$tools/ffmpeg" "$capture" "$bundle/bin/"

# MARK: Licenses

licenses="$bundle/licenses"
cp "$repo/LICENSE" "$licenses/afterword-GPL-3.0-or-later.txt"
download "$PYTHON_FULL_URL" "$PYTHON_FULL_ARCHIVE" "$PYTHON_FULL_SHA256"
tar -xf "$downloads/$PYTHON_FULL_ARCHIVE" -C "$bundle" python/licenses
mv "$bundle/python/licenses" "$licenses/python"
cp "$tools/whisper-cli.LICENSE" "$licenses/whisper.cpp-MIT.txt"
cp "$tools/ffmpeg.LICENSE" "$licenses/ffmpeg-LGPL-2.1-or-later.txt"
cat > "$licenses/ABOUT.txt" <<ABOUT
Afterword.app includes these programs. Each one's license is in this folder.

- Afterword (GPL-3.0-or-later): https://github.com/valheru7/afterword
- Python $PYTHON_VERSION (PSF License), from python-build-standalone $PYTHON_RELEASE:
  $PYTHON_URL
  python/ has the licenses of Python and the libraries built into it (OpenSSL, SQLite,
  libffi, zlib, bzip2, xz, expat, mpdecimal and others). It comes from the same build's
  full archive and also covers a few libraries this smaller build leaves out.
- Python packages afterword depends on: see python-packages/ (one file per package).
- whisper.cpp $WHISPER_TAG (MIT), commit $WHISPER_COMMIT: $WHISPER_REPO
- FFmpeg $FFMPEG_VERSION (LGPL-2.1-or-later), unmodified source: $FFMPEG_URL
  Built as a separate program, without GPL or non-free parts, by bundle-tools.sh in the
  Afterword repository, which has the exact configure options.
- afterword-capture: part of Afterword.
ABOUT
mkdir -p "$licenses/python-packages"
for dist_info in "$stdlib"/site-packages/*.dist-info; do
    name="$(basename "$dist_info" .dist-info)"
    for notice in "$dist_info"/licenses/* "$dist_info"/LICENSE* "$dist_info"/COPYING*; do
        [ -f "$notice" ] && cp "$notice" "$licenses/python-packages/$name-$(basename "$notice")"
    done
done

echo "Bundled tools are in $bundle ($(du -sh "$bundle" | cut -f 1))"
