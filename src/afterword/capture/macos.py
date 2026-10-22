"""macOS recording through the `afterword-capture` Swift helper (macos/afterword-capture),
which uses Core Audio process taps to record call audio without a bot or virtual driver."""

import json
import os
import shutil
import signal
import subprocess
from pathlib import Path

from afterword.capture import CaptureError
from afterword.session import Track

HELPER_NAME = "afterword-capture"
# Where `swift build -c release` puts the helper when running from a clone of the repo.
REPO_HELPER = Path(__file__).parents[3] / "macos" / HELPER_NAME / ".build" / "release" / HELPER_NAME

SPEAKER_FOR_ROLE = {"me": "Me", "them": "Them"}


def find_helper() -> Path:
    if override := os.environ.get("AFTERWORD_CAPTURE_BIN"):
        return Path(override)
    if REPO_HELPER.exists():
        return REPO_HELPER
    if on_path := shutil.which(HELPER_NAME):
        return Path(on_path)
    raise CaptureError(
        f"Couldn't find {HELPER_NAME}. Build it with: swift build -c release --package-path macos/{HELPER_NAME}"
    )


def record_until_stopped(directory: Path, include_call_audio: bool) -> list[Track]:
    command = [str(find_helper()), "--out", str(directory)]
    if not include_call_audio:
        command.append("--no-system")

    helper = subprocess.Popen(command, stdout=subprocess.PIPE, text=True)
    try:
        wait_for_event(helper, "recording")
        print("Recording. Press Ctrl+C to stop.", flush=True)
        helper.wait()
    except KeyboardInterrupt:
        # Ctrl+C reaches the helper too; SIGTERM covers the case where it didn't.
        helper.send_signal(signal.SIGTERM)
        helper.wait()

    manifest_path = directory / "capture.json"
    if not manifest_path.exists():
        raise CaptureError("The recording didn't finish cleanly; no capture.json was written.")
    return tracks_from_manifest(json.loads(manifest_path.read_text()))


def wait_for_event(helper: subprocess.Popen, wanted: str) -> None:
    """Reads the helper's JSON status lines until it reports `wanted` or fails."""
    assert helper.stdout is not None
    for line in helper.stdout:
        event = json.loads(line)
        if event["event"] == wanted:
            return
        if event["event"] == "starting":
            print("Starting… (the first time, macOS asks for microphone and system audio permission)", flush=True)
        if event["event"] == "error":
            raise CaptureError(event["message"])
    raise CaptureError("The recorder exited before it started recording.")


def tracks_from_manifest(manifest: dict) -> list[Track]:
    """Converts the helper's host-clock start times into offsets from the earliest track."""
    starts = [track["start_seconds"] for track in manifest["tracks"] if track["start_seconds"] is not None]
    session_start = min(starts, default=0.0)
    tracks = []
    for track in manifest["tracks"]:
        if track["start_seconds"] is None:
            continue  # The track never received audio.
        tracks.append(
            Track(
                speaker=SPEAKER_FOR_ROLE[track["role"]],
                file=track["file"],
                offset_seconds=round(track["start_seconds"] - session_start, 3),
            )
        )
    return tracks
