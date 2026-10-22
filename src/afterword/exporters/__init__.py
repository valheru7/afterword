"""Optional extra destinations for notes. The markdown file in notes_dir is always written;
exporters listed in the config's `exporters` also get a copy.

To add one: write a module with `export(note, config)` and register it in EXPORTERS."""

from collections.abc import Callable

from afterword.config import Config
from afterword.note import Note


def export_to_joplin(note: Note, config: Config) -> str:
    from afterword.exporters.joplin import export
    return export(note, config.joplin)


# Each exporter returns a short description of where the note went.
EXPORTERS: dict[str, Callable[[Note, Config], str]] = {
    "joplin": export_to_joplin,
}
