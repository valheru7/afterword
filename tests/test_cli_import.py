import sys
from pathlib import Path

import pytest

from afterword import cli
from afterword.session import Session, Track


def test_import_prints_its_session_folder_first(tmp_path, monkeypatch, capsys):
    # The macOS app reads this line to offer "Write Notes Again" if the notes fail.
    config_home = tmp_path / "config"
    (config_home / "afterword").mkdir(parents=True)
    (config_home / "afterword" / "config.toml").write_text(f'sessions_dir = "{tmp_path / "sessions"}"\n')
    monkeypatch.setenv("XDG_CONFIG_HOME", str(config_home))
    monkeypatch.setattr(cli, "process_session", lambda session, config: None)
    recording = tmp_path / "memo.m4a"
    recording.write_bytes(b"audio")
    monkeypatch.setattr(sys, "argv", ["afterword", "import", str(recording), "--title", "Memo"])

    cli.main()

    first_line = capsys.readouterr().out.splitlines()[0]
    assert first_line.startswith("Session folder: ")
    session_dir = Path(first_line.removeprefix("Session folder: "))
    assert session_dir.parent == tmp_path / "sessions"
    assert (session_dir / "recording.m4a").read_bytes() == b"audio"


def use_sessions_dir(tmp_path, monkeypatch) -> Path:
    config_home = tmp_path / "config"
    (config_home / "afterword").mkdir(parents=True)
    (config_home / "afterword" / "config.toml").write_text(f'sessions_dir = "{tmp_path / "sessions"}"\n')
    monkeypatch.setenv("XDG_CONFIG_HOME", str(config_home))
    return tmp_path / "sessions"


def recorded_session(sessions_dir: Path) -> Session:
    """A two-track session, as `afterword record` leaves it when the notes step fails."""
    session = Session.create(sessions_dir, "Acme call", "job-interview", ["Dana Lee"])
    for name in ("mic.m4a", "system.m4a"):
        (session.directory / name).write_bytes(b"audio")
    session.tracks = [Track("Me", "mic.m4a"), Track("Them", "system.m4a", 0.15)]
    session.save()
    return session


def test_importing_a_session_folder_rewrites_its_notes_like_process(tmp_path, monkeypatch, capsys):
    sessions_dir = use_sessions_dir(tmp_path, monkeypatch)
    session = recorded_session(sessions_dir)
    processed = []
    monkeypatch.setattr(cli, "process_session", lambda session, config: processed.append(session))
    monkeypatch.setattr(sys, "argv", ["afterword", "import", str(session.directory)])

    cli.main()

    # The session itself is processed: its Me/Them tracks and template, no new session folder.
    assert [(s.directory, s.tracks, s.template) for s in processed] == [
        (session.directory, session.tracks, "job-interview")
    ]
    assert list(sessions_dir.iterdir()) == [session.directory]
    assert capsys.readouterr().out.splitlines()[0] == f"Session folder: {session.directory}"


def test_importing_a_session_folder_with_a_template_saves_it(tmp_path, monkeypatch):
    session = recorded_session(use_sessions_dir(tmp_path, monkeypatch))
    processed = []
    monkeypatch.setattr(cli, "process_session", lambda session, config: processed.append(session.template))
    monkeypatch.setattr(sys, "argv", ["afterword", "import", str(session.directory), "--template", "meeting"])

    cli.main()

    assert processed == ["meeting"]
    assert Session.load(session.directory).template == "meeting"


def test_importing_a_session_folder_says_title_and_with_dont_apply(tmp_path, monkeypatch, capsys):
    session = recorded_session(use_sessions_dir(tmp_path, monkeypatch))
    processed = []
    monkeypatch.setattr(cli, "process_session", lambda session, config: processed.append(session))
    monkeypatch.setattr(sys, "argv", ["afterword", "import", str(session.directory), "--title", "Other", "--with", "Sam"])

    cli.main()

    assert processed[0].title == "Acme call"
    assert processed[0].participants == ["Dana Lee"]
    assert "don't apply to a session folder" in capsys.readouterr().out


@pytest.mark.parametrize("command", ["import", "process"])
def test_a_folder_that_isnt_a_session_gets_a_clear_error(tmp_path, monkeypatch, command):
    sessions_dir = use_sessions_dir(tmp_path, monkeypatch)
    folder = tmp_path / "Downloads"
    folder.mkdir()
    (folder / "memo.m4a").write_bytes(b"audio")
    monkeypatch.setattr(cli, "process_session", lambda session, config: pytest.fail("shouldn't process"))
    monkeypatch.setattr(sys, "argv", ["afterword", command, str(folder)])

    with pytest.raises(SystemExit) as exit_info:
        cli.main()

    message = str(exit_info.value.code)
    assert "isn't an Afterword session folder" in message
    assert str(sessions_dir) in message
    assert not sessions_dir.exists()  # Nothing was created for it.
