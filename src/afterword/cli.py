"""The `afterword` command."""

import argparse
import shutil
import sys
from pathlib import Path

from afterword.capture import CaptureError, record_until_stopped
from afterword.config import Config, load_config
from afterword.exporters.joplin import JoplinError
from afterword.pipeline import process_session
from afterword.session import TYPED_NOTES_FILE, Session, Track
from afterword.summarize import SummaryError
from afterword.templates import load_templates
from afterword.transcribe import TranscriptionError

CONSENT_REMINDER = """\
Before you start: ask everyone if it's OK to record. Many places require everyone's
consent. Something like: "Mind if I record so I can focus on you instead of my notes?"
If anyone says no, use --mic-only to record just yourself.
(Turn this reminder off with `consent_reminder = false` in the config.)
"""


def main() -> None:
    parser = argparse.ArgumentParser(prog="afterword", description="Record a call, transcribe it locally, and write notes.")
    commands = parser.add_subparsers(dest="command", required=True)

    record = commands.add_parser("record", help="record a call, then write notes when you press Ctrl+C")
    add_session_arguments(record)
    record.add_argument("--mic-only", action="store_true", help="record only your microphone (if someone declines recording)")
    record.add_argument("--no-process", action="store_true", help="just record; run `afterword process` later")

    import_command = commands.add_parser("import", help="write notes from an existing recording")
    import_command.add_argument("audio", type=Path, help="audio or video file of the whole conversation")
    add_session_arguments(import_command)

    process = commands.add_parser("process", help="(re)write notes for a recorded session")
    process.add_argument("session", type=Path, help="session folder")
    process.add_argument("--template", help="use a different template than the one recorded")

    commands.add_parser("templates", help="list note templates")

    arguments = parser.parse_args()
    config = load_config()
    try:
        match arguments.command:
            case "record":
                run_record(arguments, config)
            case "import":
                run_import(arguments, config)
            case "process":
                run_process(arguments, config)
            case "templates":
                run_templates()
    except (CaptureError, TranscriptionError, SummaryError, JoplinError, KeyError) as error:
        sys.exit(f"afterword: {error}")


def add_session_arguments(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--title", default="Untitled conversation", help='e.g. "Acme – hiring manager"')
    parser.add_argument("--with", dest="participants", action="append", default=[], metavar="NAME",
                        help="someone on the call (repeat for each person)")
    parser.add_argument("--template", help="note template (see `afterword templates`)")


def run_record(arguments: argparse.Namespace, config: Config) -> None:
    if config.consent_reminder:
        print(CONSENT_REMINDER)
    session = Session.create(config.sessions_dir, arguments.title, arguments.template or config.template, arguments.participants)
    print(f"Session folder: {session.directory}")
    print(f"Jot anything you want included in {session.directory / TYPED_NOTES_FILE}\n")

    session.tracks = record_until_stopped(session.directory, include_call_audio=not arguments.mic_only)
    session.save()
    print("\nStopped recording.")

    if arguments.no_process:
        print(f"Write notes later with: afterword process {session.directory}")
        return
    process_session(session, config)


def run_import(arguments: argparse.Namespace, config: Config) -> None:
    if not arguments.audio.exists():
        sys.exit(f"afterword: {arguments.audio} doesn't exist")
    session = Session.create(config.sessions_dir, arguments.title, arguments.template or config.template, arguments.participants)
    copied = session.directory / f"recording{arguments.audio.suffix.lower()}"
    shutil.copy2(arguments.audio, copied)
    # One mixed recording can't tell speakers apart, so everyone is "Speaker" and the
    # summarizer works out who's who from context.
    session.tracks = [Track(speaker="Speaker", file=copied.name)]
    session.save()
    process_session(session, config)


def run_process(arguments: argparse.Namespace, config: Config) -> None:
    session = Session.load(arguments.session)
    if arguments.template:
        session.template = arguments.template
        session.save()
    process_session(session, config)


def run_templates() -> None:
    for template in sorted(load_templates().values(), key=lambda template: template.name):
        print(f"{template.name:16} {template.description}")


if __name__ == "__main__":
    main()
