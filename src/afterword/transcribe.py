"""Local speech-to-text with whisper.cpp. Audio never leaves the computer."""

import json
import re
import shutil
import subprocess
import tempfile
import urllib.request
import wave
from pathlib import Path

from afterword.config import cache_dir
from afterword.transcript import Segment

WHISPER_MODEL_URL = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-{name}.bin"

# Each track is quiet whenever the other side is talking. In long silences Whisper invents
# words ("Thank you.") and stretches real segments back to the start of the silence. So
# each segment is trimmed to the part that has sound in it, and dropped if nothing's left.
# (whisper.cpp's built-in VAD avoids the made-up words, but it shifts timestamps by seconds,
# which scrambles the order of "Me" and "Them" in the transcript.)
SILENCE_THRESHOLD_DB = -35
MIN_SILENCE_SECONDS = 1.0
MIN_SPEECH_SECONDS = 0.1


class TranscriptionError(Exception):
    pass


def transcribe_track(audio: Path, speaker: str, offset_seconds: float, model: str, language: str) -> list[Segment]:
    """Transcribes one audio file. Segment times are shifted by `offset_seconds` so every
    track shares the session's clock."""
    whisper = require_tool("whisper-cli", install_hint="brew install whisper-cpp")
    model_path = ensure_model(f"ggml-{model}.bin", WHISPER_MODEL_URL.format(name=model))

    with tempfile.TemporaryDirectory() as work_dir:
        wav = Path(work_dir) / "audio.wav"
        convert_to_whisper_wav(audio, wav)
        output_prefix = Path(work_dir) / "transcript"
        command = [
            whisper,
            "--model", str(model_path),
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
        if not text:
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


def ensure_model(filename: str, url: str) -> Path:
    """Downloads a model into the cache the first time it's needed."""
    path = cache_dir() / "models" / filename
    if path.exists():
        return path

    path.parent.mkdir(parents=True, exist_ok=True)
    print(f"Downloading {filename} (first run only)…", flush=True)
    partial = path.with_suffix(".part")
    urllib.request.urlretrieve(url, partial)
    partial.rename(path)
    return path


def require_tool(name: str, install_hint: str) -> str:
    path = shutil.which(name)
    if path is None:
        raise TranscriptionError(f"Couldn't find `{name}`. Install it with: {install_hint}")
    return path
