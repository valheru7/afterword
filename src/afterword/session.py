"""A session is one recorded conversation: a folder holding the audio tracks, the
transcript, the summary, and session.json describing it."""

import json
import re
from dataclasses import asdict, dataclass, field
from datetime import datetime
from pathlib import Path

SESSION_FILE = "session.json"
TYPED_NOTES_FILE = "notes.md"


class SessionError(Exception):
    pass


@dataclass
class Track:
    """One audio file. `speaker` is "Me" for your microphone and "Them" for call audio."""

    speaker: str
    file: str
    # Seconds from the start of the session to the track's first sample, so tracks that
    # started a few milliseconds apart still line up in the transcript.
    offset_seconds: float = 0.0


@dataclass
class Session:
    directory: Path
    title: str
    template: str
    started_at: datetime
    participants: list[str] = field(default_factory=list)
    tracks: list[Track] = field(default_factory=list)

    @classmethod
    def create(cls, sessions_dir: Path, title: str, template: str, participants: list[str]) -> "Session":
        started_at = datetime.now().astimezone()
        name = f"{started_at:%Y-%m-%d-%H%M}-{slugify(title)}"
        directory = sessions_dir / name
        number = 2
        while directory.exists():  # Two sessions with the same title in the same minute.
            directory = sessions_dir / f"{name}-{number}"
            number += 1
        directory.mkdir(parents=True)
        session = cls(directory, title, template, started_at, participants)
        session.save()
        return session

    @classmethod
    def load(cls, directory: Path) -> "Session":
        raw = json.loads((directory / SESSION_FILE).read_text())
        return cls(
            directory=directory,
            title=raw["title"],
            template=raw["template"],
            started_at=datetime.fromisoformat(raw["started_at"]),
            participants=raw.get("participants", []),
            tracks=[checked_track(Track(**track), directory) for track in raw.get("tracks", [])],
        )

    def save(self) -> None:
        raw = asdict(self)
        del raw["directory"]
        raw["started_at"] = self.started_at.isoformat()
        (self.directory / SESSION_FILE).write_text(json.dumps(raw, indent=2) + "\n")

    @property
    def name(self) -> str:
        return self.directory.name

    def typed_notes(self) -> str:
        """Anything you typed into notes.md during the call."""
        path = self.directory / TYPED_NOTES_FILE
        return path.read_text().strip() if path.exists() else ""


def checked_track(track: Track, directory: Path) -> Track:
    """A track's file must be inside its session folder. session.json is a plain file anyone can
    edit (or hand you), and transcribing reads the file and writes a cache next to it."""
    file = Path(track.file)
    if file.is_absolute() or ".." in file.parts:
        raise SessionError(f"{directory / 'session.json'} names a track outside its folder: {track.file}")
    return track


def slugify(text: str) -> str:
    slug = re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")
    return slug[:60] or "session"
