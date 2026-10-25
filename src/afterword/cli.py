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


OVERVIEW = """\
usage: afterword <command> [options]

Record a call, transcribe it locally, and write notes.

commands:
  record [options]               record a call, then write notes when you press Ctrl+C
  import FILE [options]          write notes from an existing recording
  process SESSION_DIR [options]  (re)write notes for a recorded session
  templates                      list note templates

options:
  --title TITLE      e.g. "Acme – hiring manager"
  --with NAME        someone on the call (repeat for each person)
  --template NAME    note template (default: {default_template}, from your config)
  --mic-only         record: only your microphone (if someone declines recording)
  --no-process       record: just record; run `afterword process` later

`afterword <command> --help` shows which options each command takes.
"""


class OverviewHelp(argparse.Action):
    """`afterword --help`: one short page covering every command, with each option listed once."""

    def __init__(self, option_strings, dest, default_template: str, **kwargs):
        super().__init__(option_strings, dest, nargs=0, help="show this help and exit", **kwargs)
        self.default_template = default_template

    def __call__(self, parser, namespace, values, option_string=None):
        print(OVERVIEW.format(default_template=self.default_template), end="")
        parser.exit()


def main() -> None:
    config = load_config()
    template_help = f"note template (default: {config.template}, from your config; see `afterword templates`)"

    parser = argparse.ArgumentParser(prog="afterword", usage="afterword <command> [options]", add_help=False)
    parser.add_argument("-h", "--help", action=OverviewHelp, default_template=config.template)
    commands = parser.add_subparsers(dest="command", required=True, metavar="<command>")

    record = add_command(commands, "record", "record a call, then write notes when you press Ctrl+C")
    add_session_arguments(record, template_help)
    record.add_argument("--mic-only", action="store_true", help="record only your microphone (if someone declines recording)")
    record.add_argument("--no-process", action="store_true", help="just record; run `afterword process` later")

    import_command = add_command(commands, "import", "write notes from an existing recording")
    import_command.add_argument("audio", type=Path, metavar="FILE", help="audio or video file of the whole conversation")
    add_session_arguments(import_command, template_help)

    process = add_command(commands, "process", "(re)write notes for a recorded session")
    process.add_argument("session", type=Path, metavar="SESSION_DIR", help="session folder")
    process.add_argument("--template", metavar="NAME", help="use a different template than the one recorded")

    add_command(commands, "templates", "list note templates")

    arguments = parser.parse_args()
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


def add_command(commands: argparse._SubParsersAction, name: str, summary: str) -> argparse.ArgumentParser:
    return commands.add_parser(name, prog=f"afterword {name}", help=summary, description=summary)


def add_session_arguments(parser: argparse.ArgumentParser, template_help: str) -> None:
    parser.add_argument("--title", default="Untitled conversation", help='e.g. "Acme – hiring manager"')
    parser.add_argument("--with", dest="participants", action="append", default=[], metavar="NAME",
                        help="someone on the call (repeat for each person)")
    parser.add_argument("--template", metavar="NAME", help=template_help)


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
