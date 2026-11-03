import io
import urllib.error

import pytest

from afterword.summarize import SummaryError, SummaryRequest
from afterword.summarize import ollama
from afterword.summarize.anthropic_api import summarize_with_anthropic
from afterword.templates import Template

REQUEST = SummaryRequest(
    title="Call",
    date="2026-11-02",
    participants=[],
    typed_notes="",
    transcript="[00:00] Me: Hello.",
    template=Template(name="meeting", description="", instructions="Summarize."),
)


def test_anthropic_without_a_key_explains_how_to_fix_it(tmp_path, monkeypatch):
    # A fresh Mac: no key in the environment and no `ant auth login` profile on disk.
    monkeypatch.setenv("HOME", str(tmp_path))
    for name in (
        "ANTHROPIC_API_KEY",
        "ANTHROPIC_AUTH_TOKEN",
        "ANTHROPIC_PROFILE",
        "ANTHROPIC_CONFIG_DIR",
        "ANTHROPIC_IDENTITY_TOKEN",
        "ANTHROPIC_IDENTITY_TOKEN_FILE",
    ):
        monkeypatch.delenv(name, raising=False)
    # Nothing listens here, so even if a key turned up, no request would leave the computer.
    monkeypatch.setenv("ANTHROPIC_BASE_URL", "http://127.0.0.1:9")

    with pytest.raises(SummaryError, match="No Claude API key found"):
        summarize_with_anthropic(REQUEST, model="")


def test_ollama_reports_its_own_error_instead_of_asking_if_it_is_running(monkeypatch):
    def urlopen(request):
        body = io.BytesIO(b'{"error": "model \'qwen3:14b\' not found"}')
        raise urllib.error.HTTPError(ollama.OLLAMA_CHAT_URL, 404, "Not Found", {}, body)

    monkeypatch.setattr(ollama.urllib.request, "urlopen", urlopen)

    with pytest.raises(SummaryError, match="Ollama error 404: model 'qwen3:14b' not found"):
        ollama.summarize_with_ollama(REQUEST, model="")
