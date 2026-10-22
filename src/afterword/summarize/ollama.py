"""Summarize with a local model through Ollama: free, offline, nothing leaves the computer.
Quality depends a lot on the model; bigger models write noticeably better notes."""

import json
import urllib.error
import urllib.request

from afterword.summarize import SYSTEM_PROMPT, SummaryError, SummaryRequest

DEFAULT_MODEL = "qwen3:14b"
OLLAMA_CHAT_URL = "http://localhost:11434/api/chat"


def summarize_with_ollama(request: SummaryRequest, model: str) -> str:
    body = {
        "model": model or DEFAULT_MODEL,
        "stream": False,
        # Reasoning models would otherwise put their thinking into the notes.
        "think": False,
        "messages": [
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": request.user_prompt()},
        ],
        # Ollama's default context window would silently cut off a long transcript.
        "options": {"num_ctx": 65536},
    }
    http_request = urllib.request.Request(
        OLLAMA_CHAT_URL,
        data=json.dumps(body).encode(),
        headers={"Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(http_request) as response:
            reply = json.load(response)
    except urllib.error.URLError as error:
        raise SummaryError(f"Couldn't reach Ollama at {OLLAMA_CHAT_URL}. Is it running? ({error.reason})") from error

    text = reply.get("message", {}).get("content", "").strip()
    if not text:
        raise SummaryError("Ollama returned an empty summary.")
    return text
