"""Session folder → transcript → summary → note → exporters and hooks.

Each step saves its output in the session folder, and `process` reuses saved transcripts,
so re-running with a different template or summarizer doesn't transcribe again."""

import json
import os
import subprocess
from dataclasses import asdict

from afterword.config import Config
from afterword.exporters import EXPORTERS
from afterword.note import Note, build_note, write_note
from afterword.session import Session, Track
from afterword.summarize import SummaryRequest, summarize
from afterword.templates import get_template
from afterword.transcribe import TranscriptionError, transcribe_track
from afterword.transcript import Segment, format_transcript, merge_tracks

TRANSCRIPT_FILE = "transcript.md"
SUMMARY_FILE = "summary.md"


def process_session(session: Session, config: Config) -> Note:
    template = get_template(session.template)
    transcript = transcribe_session(session, config)
    if not transcript and not session.typed_notes():
        raise TranscriptionError(
            "No speech was found in the recording. Check that macOS allowed microphone and "
            "system audio recording for your terminal app, and that the right mic is selected."
        )

    print(f"Writing notes with the “{template.name}” template ({config.summarizer.provider})…", flush=True)
    request = SummaryRequest(
        title=session.title,
        date=f"{session.started_at:%A, %B %-d, %Y at %-I:%M %p}",
        participants=session.participants,
        typed_notes=session.typed_notes(),
        transcript=transcript,
        template=template,
    )
    summary = summarize(request, config.summarizer)
    (session.directory / SUMMARY_FILE).write_text(summary + "\n")

    note = build_note(session, summary, transcript, config.notes_dir)
    write_note(note, session)
    print(f"Saved {note.path}", flush=True)

    for name in config.exporters:
        exporter = EXPORTERS.get(name)
        if exporter is None:
            print(f"Skipping unknown exporter {name!r}. Available: {', '.join(EXPORTERS)}", flush=True)
            continue
        destination = exporter(note, config)
        print(f"Sent to {destination}", flush=True)

    run_after_note_hooks(note, session, config)
    return note


def transcribe_session(session: Session, config: Config) -> str:
    tracks: list[list[Segment]] = []
    for track in session.tracks:
        tracks.append(transcribe_track_cached(session, track, config))
    transcript = format_transcript(merge_tracks(tracks))
    (session.directory / TRANSCRIPT_FILE).write_text(transcript + "\n")
    return transcript


def transcribe_track_cached(session: Session, track: Track, config: Config) -> list[Segment]:
    cache = session.directory / f"{track.file}.segments.json"
    if cache.exists():
        return [Segment(**segment) for segment in json.loads(cache.read_text())]

    print(f"Transcribing {track.speaker} ({track.file})…", flush=True)
    segments = transcribe_track(
        session.directory / track.file,
        speaker=track.speaker,
        offset_seconds=track.offset_seconds,
        model=config.whisper_model,
        language=config.language,
    )
    cache.write_text(json.dumps([asdict(segment) for segment in segments], indent=1))
    return segments


def run_after_note_hooks(note: Note, session: Session, config: Config) -> None:
    environment = {
        **os.environ,
        "AFTERWORD_NOTE": str(note.path),
        "AFTERWORD_SESSION_DIR": str(session.directory),
        "AFTERWORD_TITLE": session.title,
    }
    for command in config.after_note:
        result = subprocess.run(command, shell=True, env=environment)
        if result.returncode != 0:
            print(f"after_note hook failed (exit {result.returncode}): {command}", flush=True)
