import hashlib
import io
import os
import subprocess
import time

import pytest

from afterword import transcribe
from afterword.transcribe import TranscriptionError, ensure_model, model_path


class FakeResponse(io.BytesIO):
    def __init__(self, data: bytes):
        super().__init__(data)
        self.headers = {"Content-Length": str(len(data))}


@pytest.fixture
def cache(tmp_path, monkeypatch):
    monkeypatch.setenv("XDG_CACHE_HOME", str(tmp_path))
    return tmp_path


def serve(monkeypatch, data: bytes) -> list[str]:
    requested = []

    def fake_urlopen(url, timeout=None):
        requested.append(url)
        assert timeout == transcribe.DOWNLOAD_TIMEOUT_SECONDS
        return FakeResponse(data)

    monkeypatch.setattr(transcribe.urllib.request, "urlopen", fake_urlopen)
    return requested


def test_downloads_once_with_progress_and_reuses_the_file(cache, monkeypatch, capsys):
    data = b"x" * 3_000_000
    requested = serve(monkeypatch, data)

    path = ensure_model("tiny")
    ensure_model("tiny")

    assert path == model_path("tiny") == cache / "afterword" / "models" / "ggml-tiny.bin"
    assert path.read_bytes() == data
    assert requested == ["https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.bin"]
    output = capsys.readouterr().out
    assert "Downloading Whisper model tiny (3 MB, first time only)" in output
    assert "100% of 3 MB" in output


def test_a_known_model_with_the_wrong_checksum_is_thrown_away(cache, monkeypatch):
    serve(monkeypatch, b"not the real model")
    monkeypatch.setitem(transcribe.KNOWN_MODEL_SHA256, "tiny", hashlib.sha256(b"the real model").hexdigest())

    with pytest.raises(TranscriptionError, match="damaged"):
        ensure_model("tiny")

    assert list(model_path("tiny").parent.iterdir()) == []


def test_a_failed_download_leaves_nothing_behind(cache, monkeypatch):
    def unreachable(url, timeout=None):
        raise OSError("no network")

    monkeypatch.setattr(transcribe.urllib.request, "urlopen", unreachable)

    with pytest.raises(TranscriptionError, match="Couldn't download"):
        ensure_model("tiny")

    assert list((cache / "afterword" / "models").iterdir()) == []


def test_an_interrupted_download_leaves_nothing_behind(cache, monkeypatch):
    class InterruptedResponse(FakeResponse):
        def read(self, size=-1):
            raise KeyboardInterrupt  # Ctrl+C, or the app stopping the CLI, mid-download.

    monkeypatch.setattr(transcribe.urllib.request, "urlopen", lambda url, timeout=None: InterruptedResponse(b"x" * 10))

    with pytest.raises(KeyboardInterrupt):
        ensure_model("tiny")

    assert list(model_path("tiny").parent.iterdir()) == []


def finished_process_id() -> int:
    """The PID of a process that has already exited, so nothing is running with it."""
    process = subprocess.Popen(["true"])
    process.wait()
    return process.pid


def test_a_part_left_by_a_dead_process_is_removed(cache, monkeypatch):
    models = model_path("tiny").parent
    models.mkdir(parents=True)
    stale = models / f"ggml-tiny.bin.{finished_process_id()}.part"
    stale.write_bytes(b"half a model")
    serve(monkeypatch, b"model")

    ensure_model("tiny")

    assert not stale.exists()


def test_a_part_another_running_download_is_writing_is_left_alone(cache, monkeypatch):
    models = model_path("tiny").parent
    models.mkdir(parents=True)
    in_progress = models / f"ggml-tiny.bin.{os.getppid()}.part"  # A process that's surely running.
    in_progress.write_bytes(b"half a model")
    serve(monkeypatch, b"model")

    ensure_model("tiny")

    assert in_progress.exists()


def test_a_part_older_than_a_day_is_removed_even_if_its_pid_is_in_use(cache, monkeypatch):
    models = model_path("tiny").parent
    models.mkdir(parents=True)
    old = models / f"ggml-tiny.bin.{os.getppid()}.part"
    old.write_bytes(b"half a model")
    two_days_ago = time.time() - 2 * 24 * 60 * 60
    os.utime(old, (two_days_ago, two_days_ago))
    serve(monkeypatch, b"model")

    ensure_model("tiny")

    assert not old.exists()
