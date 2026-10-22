from pathlib import Path

from afterword.capture.macos import tracks_from_manifest
from afterword.config import load_config
from afterword.note import build_note
from afterword.session import Session, Track, slugify


def test_manifest_start_times_become_offsets_from_the_earliest_track():
    manifest = {
        "tracks": [
            {"role": "me", "file": "mic.m4a", "start_seconds": 1000.10},
            {"role": "them", "file": "system.m4a", "start_seconds": 1000.25},
        ]
    }

    tracks = tracks_from_manifest(manifest)

    assert tracks == [Track("Me", "mic.m4a", 0.0), Track("Them", "system.m4a", 0.15)]


def test_manifest_skips_tracks_that_never_got_audio():
    manifest = {"tracks": [{"role": "me", "file": "mic.m4a", "start_seconds": None}]}

    assert tracks_from_manifest(manifest) == []


def test_session_round_trips_through_session_json(tmp_path):
    session = Session.create(tmp_path, "Acme – hiring manager", "job-interview", ["Dana Lee"])
    session.tracks = [Track("Me", "mic.m4a", 0.0)]
    session.save()

    loaded = Session.load(session.directory)

    assert loaded.title == "Acme – hiring manager"
    assert loaded.participants == ["Dana Lee"]
    assert loaded.tracks == session.tracks
    assert loaded.directory.name.endswith("-acme-hiring-manager")


def test_slugify_falls_back_when_nothing_is_left():
    assert slugify("!!!") == "session"


def test_note_markdown_has_header_title_summary_and_transcript(tmp_path):
    session = Session.create(tmp_path, 'Acme "round 2"', "meeting", [])

    note = build_note(session, "## Summary\nWent well.", "[00:00:01] Me: Hi.", notes_dir=tmp_path / "notes")
    markdown = note.markdown(session)

    assert markdown.startswith("---\ntitle: \"Acme \\\"round 2\\\"\"\n")
    assert "\n# Acme \"round 2\"\n\n## Summary\nWent well.\n\n## Transcript\n\n[00:00:01] Me: Hi.\n" in markdown
    assert note.path == tmp_path / "notes" / f"{session.name}.md"


def test_config_defaults_without_a_file(tmp_path):
    config = load_config(tmp_path / "missing.toml")

    assert config.template == "meeting"
    assert config.summarizer.provider == "anthropic"


def test_config_reads_nested_tables(tmp_path):
    path = tmp_path / "config.toml"
    path.write_text(
        'template = "job-interview"\nnotes_dir = "~/Notes"\nexporters = ["joplin"]\n'
        '[summarizer]\nprovider = "ollama"\n[joplin]\ntoken = "abc"\nnotebook = "Interviews"\n'
    )

    config = load_config(path)

    assert config.template == "job-interview"
    assert config.notes_dir == Path.home() / "Notes"
    assert config.summarizer.provider == "ollama"
    assert config.joplin.notebook == "Interviews"
    assert config.exporters == ["joplin"]
