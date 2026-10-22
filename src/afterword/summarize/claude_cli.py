"""Summarize with the Claude Code CLI (`claude -p`), which uses a Claude subscription
instead of a separate API key."""

import shutil
import subprocess
import tempfile

from afterword.summarize import SYSTEM_PROMPT, SummaryError, SummaryRequest


def summarize_with_claude_cli(request: SummaryRequest, model: str) -> str:
    claude = shutil.which("claude")
    if claude is None:
        raise SummaryError("Couldn't find the `claude` command. Install Claude Code, or use another summarizer.")

    command = [claude, "--print", "--system-prompt", SYSTEM_PROMPT]
    if model:
        command += ["--model", model]
    # Run from an empty directory so no project's CLAUDE.md or settings leak into the notes.
    with tempfile.TemporaryDirectory() as empty_dir:
        result = subprocess.run(command, input=request.user_prompt(), capture_output=True, text=True, cwd=empty_dir)
    if result.returncode != 0:
        raise SummaryError(f"`claude` failed:\n{result.stderr.strip() or result.stdout.strip()}")

    text = result.stdout.strip()
    if not text:
        raise SummaryError("`claude` returned an empty summary.")
    return text
