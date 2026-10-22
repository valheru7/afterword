"""The finished note: a plain markdown file with a small YAML header, readable by Obsidian,
Joplin's importer, or any text editor."""

import json
from dataclasses import dataclass
from pathlib import Path

from afterword.session import Session


@dataclass(frozen=True)
class Note:
    title: str
    body: str  # markdown, without the header
    tags: list[str]
    path: Path

    def markdown(self, session: Session) -> str:
        header = [
            "---",
            f"title: {yaml_string(self.title)}",
            f"date: {session.started_at.isoformat(timespec='minutes')}",
            f"template: {session.template}",
            f"participants: {json.dumps(session.participants)}",
            f"tags: {json.dumps(self.tags)}",
            f"session: {yaml_string(str(session.directory))}",
            "---",
        ]
        return "\n".join(header) + f"\n\n# {self.title}\n\n{self.body.strip()}\n"


def build_note(session: Session, summary: str, transcript: str, notes_dir: Path) -> Note:
    body = f"{summary.strip()}\n\n## Transcript\n\n{transcript.strip()}"
    tags = ["afterword", session.template]
    return Note(title=session.title, body=body, tags=tags, path=notes_dir / f"{session.name}.md")


def write_note(note: Note, session: Session) -> None:
    note.path.parent.mkdir(parents=True, exist_ok=True)
    note.path.write_text(note.markdown(session))


def yaml_string(value: str) -> str:
    # A JSON string is also a valid YAML string, quotes and escapes included.
    return json.dumps(value)
