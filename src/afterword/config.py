"""Settings, read from ~/.config/afterword/config.toml. Every setting has a default,
so the file is optional."""

import os
import tomllib
from dataclasses import dataclass, field
from pathlib import Path


def config_dir() -> Path:
    base = os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config"
    return Path(base) / "afterword"


def cache_dir() -> Path:
    base = os.environ.get("XDG_CACHE_HOME") or Path.home() / ".cache"
    return Path(base) / "afterword"


@dataclass
class SummarizerConfig:
    # "anthropic" (Claude API key), "claude-cli" (Claude Code subscription) or "ollama" (local, free).
    provider: str = "anthropic"
    # Empty means the provider's own default model.
    model: str = ""


@dataclass
class JoplinConfig:
    # Joplin → Settings → Web Clipper → "Advanced options" shows the token.
    token: str = ""
    notebook: str = "Afterword"
    url: str = "http://localhost:41184"


@dataclass
class Config:
    sessions_dir: Path = Path.home() / "Afterword" / "sessions"
    notes_dir: Path = Path.home() / "Afterword" / "notes"
    template: str = "meeting"
    consent_reminder: bool = True
    whisper_model: str = "large-v3-turbo-q5_0"
    language: str = "en"
    summarizer: SummarizerConfig = field(default_factory=SummarizerConfig)
    # Extra places to send each note, besides the markdown file in notes_dir. Example: ["joplin"]
    exporters: list[str] = field(default_factory=list)
    joplin: JoplinConfig = field(default_factory=JoplinConfig)
    # Shell commands run after each note is written. They get AFTERWORD_NOTE (the note's
    # path), AFTERWORD_SESSION_DIR and AFTERWORD_TITLE in their environment. This is where
    # personal integrations belong, so they never have to live in this repo.
    after_note: list[str] = field(default_factory=list)


def load_config(path: Path | None = None) -> Config:
    path = path or config_dir() / "config.toml"
    if not path.exists():
        return Config()

    with path.open("rb") as file:
        raw = tomllib.load(file)

    config = Config()
    for key in ("template", "whisper_model", "language"):
        if key in raw:
            setattr(config, key, str(raw[key]))
    if "consent_reminder" in raw:
        config.consent_reminder = bool(raw["consent_reminder"])
    if "sessions_dir" in raw:
        config.sessions_dir = Path(raw["sessions_dir"]).expanduser()
    if "notes_dir" in raw:
        config.notes_dir = Path(raw["notes_dir"]).expanduser()
    if "exporters" in raw:
        config.exporters = list(raw["exporters"])
    if "after_note" in raw:
        config.after_note = list(raw["after_note"])
    if "summarizer" in raw:
        config.summarizer = SummarizerConfig(**raw["summarizer"])
    if "joplin" in raw:
        config.joplin = JoplinConfig(**raw["joplin"])
    return config
