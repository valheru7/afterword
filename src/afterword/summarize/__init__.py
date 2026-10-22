"""Turning a transcript into notes. The prompt is the same for every provider; providers
only differ in where the model runs."""

from dataclasses import dataclass

from afterword.config import SummarizerConfig
from afterword.templates import Template

SYSTEM_PROMPT = """\
You turn conversation transcripts into clear, accurate notes in Markdown.

The transcript comes from automatic speech recognition, so expect misheard words and \
names; fix obvious ones from context. "Me" is the person who recorded the call and will \
read these notes. "Them" is everyone else, all on one track, so tell people apart from \
context when you can. If every line is labeled "Speaker", the recording wasn't split \
by speaker; work out who is who from context.

Only write what the conversation supports. Never invent names, numbers, dates or \
commitments. If something important was unclear or inaudible, say so briefly.

Start directly with the first section heading. Don't add a title or a preamble."""


@dataclass(frozen=True)
class SummaryRequest:
    title: str
    date: str
    participants: list[str]
    typed_notes: str
    transcript: str
    template: Template

    def user_prompt(self) -> str:
        parts = [
            f"Title: {self.title}",
            f"Date: {self.date}",
            f"Participants: {', '.join(self.participants) or 'not given'}",
        ]
        if self.typed_notes:
            parts.append(f"<my_typed_notes>\n{self.typed_notes}\n</my_typed_notes>")
        parts.append(f"<transcript>\n{self.transcript}\n</transcript>")
        parts.append(f"<instructions>\n{self.template.instructions}\n</instructions>")
        return "\n\n".join(parts)


class SummaryError(Exception):
    pass


def summarize(request: SummaryRequest, config: SummarizerConfig) -> str:
    # Imported here so a provider's dependencies only load when it's used.
    match config.provider:
        case "anthropic":
            from afterword.summarize.anthropic_api import summarize_with_anthropic
            return summarize_with_anthropic(request, config.model)
        case "claude-cli":
            from afterword.summarize.claude_cli import summarize_with_claude_cli
            return summarize_with_claude_cli(request, config.model)
        case "ollama":
            from afterword.summarize.ollama import summarize_with_ollama
            return summarize_with_ollama(request, config.model)
        case other:
            raise SummaryError(f"Unknown summarizer {other!r}. Use anthropic, claude-cli or ollama.")
