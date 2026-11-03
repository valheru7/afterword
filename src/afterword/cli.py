"""The `afterword` command."""

import argparse
import json
import shutil
import sys
import tomllib
from pathlib import Path

from afterword.capture import CaptureError, record_until_stopped
from afterword.config import Config, config_file, load_config
from afterword.config_file import ConfigError, check_joplin, effective_config, flattened, set_value
from afterword.exporters.joplin import JoplinError
from afterword.pipeline import process_session
from afterword.session import SESSION_FILE, TYPED_NOTES_FILE, Session, SessionError, Track
from afterword.summarize import SummaryError
from afterword.templates import load_templates
from afterword.transcribe import TranscriptionError, ensure_model, model_path

UNTITLED = "Untitled conversation"

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
  import FILE [options]          write notes from an existing recording, or from a session
                                 folder (the same as `process`)
  process SESSION_DIR [options]  (re)write notes for a recorded session
  templates                      list note templates
  download-model [--check]       download the Whisper model now instead of on first use
  config show [--json]           show settings, defaults included
  config set KEY VALUE           change a setting, e.g. config set summarizer.provider ollama
  config test-joplin             check Joplin is reachable and the token works

options:
  --title TITLE      e.g. "Acme – hiring manager"
  --with NAME        someone on the call (repeat for each person)
  --template NAME    note template: {template_names}
  --mic-only         record: only your microphone (if someone declines recording)
  --no-process       record: just record; run `afterword process` later

`afterword <command> --help` shows which options each command takes.
"""


class OverviewHelp(argparse.Action):
    """`afterword --help`: one short page covering every command, with each option listed once."""

    def __init__(self, option_strings, dest, template_names: str, **kwargs):
        super().__init__(option_strings, dest, nargs=0, help="show this help and exit", **kwargs)
        self.template_names = template_names

    def __call__(self, parser, namespace, values, option_string=None):
        print(OVERVIEW.format(template_names=self.template_names), end="")
        parser.exit()


def main() -> None:
    try:
        config = load_config()
    except tomllib.TOMLDecodeError as error:
        # Every command reads the config, so say what's wrong instead of showing a traceback.
        sys.exit(f"afterword: {config_file()} isn't valid TOML: {error}")
    template_names = describe_template_names(config.template)
    template_help = f"note template: {template_names}"

    parser = argparse.ArgumentParser(prog="afterword", usage="afterword <command> [options]", add_help=False)
    parser.add_argument("-h", "--help", action=OverviewHelp, template_names=template_names)
    commands = parser.add_subparsers(dest="command", required=True, metavar="<command>")

    record = add_command(commands, "record", "record a call, then write notes when you press Ctrl+C")
    add_session_arguments(record, template_help)
    record.add_argument("--mic-only", action="store_true", help="record only your microphone (if someone declines recording)")
    record.add_argument("--no-process", action="store_true", help="just record; run `afterword process` later")

    import_command = add_command(commands, "import", "write notes from an existing recording, or from a session folder")
    import_command.add_argument(
        "audio", type=Path, metavar="FILE",
        help="audio or video file of the whole conversation, or a session folder to write notes for again (the same as `process`)",
    )
    add_session_arguments(import_command, template_help)

    process = add_command(commands, "process", "(re)write notes for a recorded session")
    process.add_argument("session", type=Path, metavar="SESSION_DIR", help="session folder")
    process.add_argument("--template", metavar="NAME", help="use a different template than the one recorded")

    add_command(commands, "templates", "list note templates")

    download = add_command(commands, "download-model", "download the Whisper model now instead of on first use")
    download.add_argument("--check", action="store_true", help="only report whether it's downloaded (exit 1 if not)")

    config_command = add_command(commands, "config", "show or change settings")
    config_actions = config_command.add_subparsers(dest="config_action", required=True, metavar="<action>")
    show = config_actions.add_parser("show", help="show settings, defaults included")
    show.add_argument("--json", action="store_true", help="print JSON (paths expanded)")
    set_command = config_actions.add_parser(
        "set",
        help="change a setting",
        description=(
            'Change a setting. Lists are JSON arrays, e.g. config set exporters \'["joplin"]\'. '
            "Use - as the value to read it from stdin, e.g. for joplin.token."
        ),
    )
    set_command.add_argument("key", metavar="KEY", help="e.g. template, notes_dir, summarizer.provider, joplin.token")
    set_command.add_argument("value", metavar="VALUE", help="the value, or - to read it from stdin (for tokens)")
    config_actions.add_parser("test-joplin", help="check Joplin is reachable and the token works")

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
            case "config":
                run_config(arguments, config)
            case "download-model":
                run_download_model(arguments, config)
    except (CaptureError, TranscriptionError, SummaryError, JoplinError, ConfigError, SessionError, KeyError) as error:
        sys.exit(f"afterword: {error}")


def describe_template_names(default: str) -> str:
    """e.g. "interview-recap, job-interview (default), meeting, one-on-one"."""
    names = sorted(load_templates())
    return ", ".join(f"{name} (default)" if name == default else name for name in names)


def add_command(commands: argparse._SubParsersAction, name: str, summary: str) -> argparse.ArgumentParser:
    return commands.add_parser(name, prog=f"afterword {name}", help=summary, description=summary)


def add_session_arguments(parser: argparse.ArgumentParser, template_help: str) -> None:
    parser.add_argument("--title", default=UNTITLED, help='e.g. "Acme – hiring manager"')
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
    process_session(session, reload_config(config))


def reload_config(startup_config: Config) -> Config:
    """The config as it is now. A call can last an hour, and the notes writer or exporters
    may have been changed in Settings meanwhile; the notes should use what's set when they're
    written, not what was set when recording started."""
    try:
        return load_config()
    except tomllib.TOMLDecodeError as error:
        # Don't lose the recording's notes over a half-edited file: keep the settings it started with.
        print(f"afterword: {config_file()} isn't valid TOML ({error}); using the settings from when recording started.")
        return startup_config


def run_import(arguments: argparse.Namespace, config: Config) -> None:
    if not arguments.audio.exists():
        sys.exit(f"afterword: {arguments.audio} doesn't exist")
    if arguments.audio.is_dir():
        import_session_folder(arguments, config)
        return
    session = Session.create(config.sessions_dir, arguments.title, arguments.template or config.template, arguments.participants)
    # Same line as `record` prints, so the macOS app knows where to retry from if this fails.
    print(f"Session folder: {session.directory}", flush=True)
    copied = session.directory / f"recording{arguments.audio.suffix.lower()}"
    shutil.copy2(arguments.audio, copied)
    # One mixed recording can't tell speakers apart, so everyone is "Speaker" and the
    # summarizer works out who's who from context.
    session.tracks = [Track(speaker="Speaker", file=copied.name)]
    session.save()
    process_session(session, config)


def import_session_folder(arguments: argparse.Namespace, config: Config) -> None:
    """`import` given a session folder does what `process` does, rather than erroring and
    pointing there: "import" is the word people reach for (it's the macOS app's menu item), and
    it's clear what they meant. Importing the folder's audio as one mixed recording instead
    would lose the Me/Them split its separate tracks keep."""
    if arguments.participants or arguments.title != UNTITLED:
        print("afterword: --title and --with don't apply to a session folder; it keeps the ones it was recorded with.")
    # Same line as importing a file prints, so the macOS app knows where to retry from.
    print(f"Session folder: {arguments.audio}", flush=True)
    rewrite_notes(arguments.audio, arguments.template, config)


def run_process(arguments: argparse.Namespace, config: Config) -> None:
    rewrite_notes(arguments.session, arguments.template, config)


def rewrite_notes(session_dir: Path, template: str | None, config: Config) -> None:
    """Writes a recorded session's notes again, reusing its saved transcripts. `template`
    replaces the one it was recorded with; None keeps it."""
    if not (session_dir / SESSION_FILE).is_file():
        raise SessionError(
            f"{session_dir} isn't an Afterword session folder: it has no {SESSION_FILE}. "
            f"Session folders are in {config.sessions_dir}."
        )
    session = Session.load(session_dir)
    if template:
        session.template = template
        session.save()
    process_session(session, config)


def run_templates() -> None:
    for template in sorted(load_templates().values(), key=lambda template: template.name):
        print(f"{template.name:16} {template.description}")


def run_download_model(arguments: argparse.Namespace, config: Config) -> None:
    path = model_path(config.whisper_model)
    if arguments.check:
        print(path)
        if not path.exists():
            sys.exit(1)
        return
    print(f"Ready: {ensure_model(config.whisper_model)}")


def run_config(arguments: argparse.Namespace, config: Config) -> None:
    match arguments.config_action:
        case "show":
            values = effective_config(config)
            if arguments.json:
                print(json.dumps(values, indent=2))
                return
            for key, value in flattened(values):
                # Hide the token on screen (screen shares, streams); --json, for programs, keeps it.
                shown = "(set)" if key == "joplin.token" and value else json.dumps(value, ensure_ascii=False)
                print(f"{key} = {shown}")
        case "set":
            value = arguments.value
            if value == "-":
                # Read secrets from stdin so they don't show up in `ps` or shell history.
                value = sys.stdin.read().removesuffix("\n")
            set_value(arguments.key, value)
            print(f"Set {arguments.key}.")
        case "test-joplin":
            connected, message = check_joplin(config.joplin)
            print(message)
            if not connected:
                sys.exit(1)


if __name__ == "__main__":
    main()
