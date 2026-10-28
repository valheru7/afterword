"""Local speech-to-text with whisper.cpp. Audio never leaves the computer."""

import hashlib
import json
import os
import re
import shutil
import subprocess
import tempfile
import time
import urllib.request
import wave
from pathlib import Path

from afterword.config import cache_dir
from afterword.transcript import Segment

WHISPER_MODEL_URL = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-{name}.bin"
# SHA-256 of models we know, checked after downloading (Hugging Face lists it as the file's
# "x-linked-etag"). Other models are downloaded without a check.
KNOWN_MODEL_SHA256 = {
    # The ones the Settings window offers.
    "base": "60ed5bc3dd14eea856493d334349b405782ddcaf0028d4b5df4088345fba2efe",
    "small": "1be3a9b2063867b937e64e2ec7483364a79917e157fa98c5d94b5c1fffea987b",
    "large-v3-turbo-q5_0": "394221709cd5ad1f40c46e6031ca61bce88931e6e088c188294c6d5a55ffa7e2",
    "large-v3-turbo": "1fc70f774d38eb169993ac391eea357ef47c88757ef72ee5943879b7e8e2bc69",
}
# A stalled connection gives up after this long instead of hanging the transcription forever.
DOWNLOAD_TIMEOUT_SECONDS = 60
# A partial download this old is abandoned even if a process with its PID is running (PIDs
# get reused). An active download keeps touching its file, so it never looks this old.
ABANDONED_DOWNLOAD_SECONDS = 24 * 60 * 60

# Each track is quiet whenever the other side is talking. In long silences Whisper invents
# words ("Thank you.") and stretches real segments back to the start of the silence. So
# each segment is trimmed to the part that has sound in it, and dropped if nothing's left.
# (whisper.cpp's built-in VAD avoids the made-up words, but it shifts timestamps by seconds,
# which scrambles the order of "Me" and "Them" in the transcript.)
SILENCE_THRESHOLD_DB = -35
MIN_SILENCE_SECONDS = 1.0
MIN_SPEECH_SECONDS = 0.1


# Whisper learned partly from subtitled video, so in near-silence it sometimes "hears" a
# subtitle credit, like "Transcription by CastingWords". Only whole segments that are one of
# these known credits are dropped, so real speech that mentions captions or Amara is kept.
SUBTITLE_CREDIT = re.compile(
    r"^(transcription|transcribed|transcript|subtitles|captions|captioning)( provided| created)? by "
    r"(castingwords|(the )?amara\.?org( community)?)\.?$",
    re.IGNORECASE,
)


def is_subtitle_credit(text: str) -> bool:
    return SUBTITLE_CREDIT.match(text.strip()) is not None


def drop_subtitle_credits(segments: list[Segment]) -> list[Segment]:
    return [segment for segment in segments if not is_subtitle_credit(segment.text)]


class TranscriptionError(Exception):
    pass


def transcribe_track(audio: Path, speaker: str, offset_seconds: float, model: str, language: str) -> list[Segment]:
    """Transcribes one audio file. Segment times are shifted by `offset_seconds` so every
    track shares the session's clock."""
    whisper = require_tool("whisper-cli", install_hint="brew install whisper-cpp")
    model_file = ensure_model(model)

    with tempfile.TemporaryDirectory() as work_dir:
        wav = Path(work_dir) / "audio.wav"
        convert_to_whisper_wav(audio, wav)
        output_prefix = Path(work_dir) / "transcript"
        command = [
            whisper,
            "--model", str(model_file),
            "--file", str(wav),
            "--language", language,
            "--output-json",
            "--output-file", str(output_prefix),
            "--no-prints",
            "--suppress-nst",
        ]
        result = subprocess.run(command, capture_output=True, text=True)
        if result.returncode != 0:
            raise TranscriptionError(f"whisper-cli failed on {audio.name}:\n{result.stderr.strip()}")
        whisper_json = json.loads(output_prefix.with_suffix(".json").read_text())
        silences = find_silences(wav)
        with wave.open(str(wav)) as audio_file:
            duration = audio_file.getnframes() / audio_file.getframerate()
        # Whisper works in 30-second windows and can report segments past the end of the file.
        silences.append((duration, float("inf")))

    segments = []
    for segment in parse_whisper_json(whisper_json, speaker, offset_seconds=0.0):
        trimmed = trim_to_speech(segment, silences)
        if trimmed is not None:
            segments.append(shift(trimmed, offset_seconds))
    return segments


def parse_whisper_json(whisper_json: dict, speaker: str, offset_seconds: float) -> list[Segment]:
    segments = []
    for item in whisper_json.get("transcription", []):
        text = item["text"].strip()
        if not text or is_subtitle_credit(text):
            continue
        # whisper.cpp reports offsets in milliseconds.
        start = item["offsets"]["from"] / 1000 + offset_seconds
        end = item["offsets"]["to"] / 1000 + offset_seconds
        segments.append(Segment(speaker, start, end, text))
    return segments


def find_silences(wav: Path) -> list[tuple[float, float]]:
    """Silent stretches of the file as (start, end) seconds, from ffmpeg's silencedetect."""
    ffmpeg = require_tool("ffmpeg", install_hint="brew install ffmpeg")
    command = [
        ffmpeg, "-hide_banner", "-nostats", "-i", str(wav),
        "-af", f"silencedetect=noise={SILENCE_THRESHOLD_DB}dB:d={MIN_SILENCE_SECONDS}",
        "-f", "null", "-",
    ]
    output = subprocess.run(command, capture_output=True, text=True).stderr
    starts = [float(value) for value in re.findall(r"silence_start: ([\d.]+)", output)]
    ends = [float(value) for value in re.findall(r"silence_end: ([\d.]+)", output)]
    # A file that ends in silence has one more start than end.
    if len(ends) < len(starts):
        ends.append(float("inf"))
    return list(zip(starts, ends))


def trim_to_speech(segment: Segment, silences: list[tuple[float, float]]) -> Segment | None:
    """Narrows a segment to the span that isn't silent, or returns None if it's all silence."""
    sounding: list[tuple[float, float]] = []
    cursor = segment.start
    for silence_start, silence_end in silences:
        if silence_end <= cursor or silence_start >= segment.end:
            continue
        if silence_start > cursor:
            sounding.append((cursor, silence_start))
        cursor = max(cursor, silence_end)
    if cursor < segment.end:
        sounding.append((cursor, segment.end))

    if sum(end - start for start, end in sounding) < MIN_SPEECH_SECONDS:
        return None
    return Segment(segment.speaker, sounding[0][0], sounding[-1][1], segment.text)


def shift(segment: Segment, seconds: float) -> Segment:
    return Segment(segment.speaker, segment.start + seconds, segment.end + seconds, segment.text)


def convert_to_whisper_wav(source: Path, destination: Path) -> None:
    """whisper.cpp wants 16 kHz mono 16-bit WAV."""
    ffmpeg = require_tool("ffmpeg", install_hint="brew install ffmpeg")
    command = [
        ffmpeg, "-hide_banner", "-loglevel", "error", "-y",
        "-i", str(source),
        "-ar", "16000", "-ac", "1", "-c:a", "pcm_s16le",
        str(destination),
    ]
    result = subprocess.run(command, capture_output=True, text=True)
    if result.returncode != 0:
        raise TranscriptionError(f"ffmpeg couldn't read {source.name}:\n{result.stderr.strip()}")


def model_path(model: str) -> Path:
    """Where a Whisper model lives once downloaded, shared by the CLI and the macOS app."""
    return cache_dir() / "models" / f"ggml-{model}.bin"


def ensure_model(model: str) -> Path:
    """Downloads a model into the cache the first time it's needed, printing progress."""
    path = model_path(model)
    if path.exists():
        return path

    path.parent.mkdir(parents=True, exist_ok=True)
    remove_abandoned_downloads(path)
    # Named per process: the macOS app can be downloading the model while a recording's
    # transcription starts the same download. Whichever finishes first is kept.
    partial = path.with_name(f"{path.name}.{os.getpid()}.part")
    url = WHISPER_MODEL_URL.format(name=model)
    try:
        try:
            with urllib.request.urlopen(url, timeout=DOWNLOAD_TIMEOUT_SECONDS) as response, partial.open("wb") as file:
                size = int(response.headers.get("Content-Length") or 0)
                download_with_progress(response, file, size, label=f"Whisper model {model}")
        except OSError as error:
            raise TranscriptionError(f"Couldn't download the Whisper model {model!r} from {url}: {error}") from error

        expected = KNOWN_MODEL_SHA256.get(model)
        if expected and file_sha256(partial) != expected:
            raise TranscriptionError(f"The downloaded Whisper model {model!r} was damaged. Try again.")
        partial.replace(path)
    finally:
        # Whatever stopped the download (an error, Ctrl+C, the app quitting), don't leave
        # hundreds of MB behind. After a successful replace() there's nothing to remove.
        partial.unlink(missing_ok=True)
    return path


def remove_abandoned_downloads(path: Path) -> None:
    """Deletes partial downloads of `path` left by a process that was killed before its own
    cleanup could run: ones whose process is gone, or that are over a day old."""
    prefix = f"{path.name}."
    for part in path.parent.glob(f"{prefix}*.part"):
        pid_text = part.name.removeprefix(prefix).removesuffix(".part")
        try:
            age = time.time() - part.stat().st_mtime
        except FileNotFoundError:
            continue  # Its own process just finished or cleaned up.
        abandoned = age > ABANDONED_DOWNLOAD_SECONDS or not pid_text.isdigit() or not process_is_running(int(pid_text))
        if abandoned:
            part.unlink(missing_ok=True)


def process_is_running(pid: int) -> bool:
    # On Windows os.kill(pid, 0) would terminate the process rather than check on it, so there
    # only the age rule applies.
    if os.name == "nt":
        return True
    try:
        os.kill(pid, 0)  # Signal 0 checks that the process exists without touching it.
    except ProcessLookupError:
        return False
    except PermissionError:
        return True  # It exists but belongs to someone else.
    return True


def download_with_progress(response, file, size: int, label: str) -> None:
    """Copies a download to `file`, printing a line every 5% (the macOS app shows the latest)."""
    megabytes = size / 1_000_000
    print(f"Downloading {label} ({megabytes:.0f} MB, first time only)…", flush=True)
    copied = 0
    last_reported = 0
    while chunk := response.read(1 << 20):
        file.write(chunk)
        copied += len(chunk)
        percent = copied * 100 // size if size else 0
        if percent >= last_reported + 5:
            last_reported = percent - percent % 5
            print(f"Downloading {label}: {last_reported}% of {megabytes:.0f} MB", flush=True)


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as file:
        while chunk := file.read(1 << 20):
            digest.update(chunk)
    return digest.hexdigest()


def require_tool(name: str, install_hint: str) -> str:
    path = shutil.which(name)
    if path is None:
        raise TranscriptionError(f"Couldn't find `{name}`. Install it with: {install_hint}")
    return path
