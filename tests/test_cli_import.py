import sys
from pathlib import Path

from afterword import cli


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
