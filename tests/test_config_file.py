import io
import json
import stat
import sys
import threading
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path

import pytest

from afterword import cli
from afterword.config import Config, JoplinConfig, load_config
from afterword.config_file import ConfigError, check_joplin, effective_config, set_value


def test_effective_config_fills_in_defaults_and_expands_paths(tmp_path):
    path = tmp_path / "config.toml"
    path.write_text('notes_dir = "~/My Notes"\n[summarizer]\nprovider = "ollama"\n')

    values = effective_config(load_config(path))

    assert values["notes_dir"] == str(Path.home() / "My Notes")
    assert values["summarizer"] == {"provider": "ollama", "model": ""}
    assert values["template"] == Config().template
    assert values["joplin"]["url"] == JoplinConfig().url


def test_set_keeps_comments_and_other_settings(tmp_path):
    path = tmp_path / "config.toml"
    path.write_text('# my settings\ntemplate = "meeting"  # usual one\nlanguage = "en"\n')

    set_value("template", "job-interview", path)

    text = path.read_text()
    assert "# my settings" in text
    assert "# usual one" in text
    assert load_config(path).template == "job-interview"
    assert load_config(path).language == "en"


def test_set_creates_the_folder_file_and_section_readable_only_by_you(tmp_path):
    path = tmp_path / "afterword" / "config.toml"

    set_value("joplin.notebook", "Interviews", path)

    assert load_config(path).joplin.notebook == "Interviews"
    assert stat.S_IMODE(path.stat().st_mode) == 0o600
    assert [file.name for file in path.parent.iterdir()] == ["config.toml"]  # no temp files left


def test_new_top_level_setting_does_not_land_inside_a_table(tmp_path):
    path = tmp_path / "config.toml"
    path.write_text('[joplin]\nnotebook = "Work"\n')

    set_value("language", "auto", path)

    config = load_config(path)
    assert config.language == "auto"
    assert config.joplin.notebook == "Work"


def test_set_through_a_symlink_updates_the_real_file_and_keeps_the_link(tmp_path):
    real = tmp_path / "dotfiles" / "afterword.toml"
    real.parent.mkdir()
    real.write_text('# kept in dotfiles\ntemplate = "meeting"\n')
    link = tmp_path / "config.toml"
    link.symlink_to(real)

    set_value("language", "auto", link)

    assert link.is_symlink()
    assert "# kept in dotfiles" in real.read_text()
    assert load_config(link).language == "auto"
    assert sorted(file.name for file in real.parent.iterdir()) == ["afterword.toml"]


def test_set_writes_utf8_whatever_the_locale(tmp_path):
    path = tmp_path / "config.toml"

    set_value("joplin.notebook", "Entretiens – été", path)

    assert "Entretiens – été" in path.read_bytes().decode("utf-8")
    assert load_config(path).joplin.notebook == "Entretiens – été"


def test_set_types_values_by_field(tmp_path):
    path = tmp_path / "config.toml"

    set_value("consent_reminder", "false", path)
    set_value("exporters", '["joplin"]', path)
    set_value("after_note", '["~/bin/file-note", "echo done"]', path)
    set_value("sessions_dir", "~/Calls", path)

    config = load_config(path)
    assert config.consent_reminder is False
    assert config.exporters == ["joplin"]
    assert config.after_note == ["~/bin/file-note", "echo done"]
    assert config.sessions_dir == Path.home() / "Calls"


@pytest.mark.parametrize(
    ("key", "value", "message"),
    [
        ("colour", "blue", "Unknown setting"),
        ("joplin.colour", "blue", "Unknown setting"),
        ("template.name", "x", "Unknown setting"),
        ("joplin", "x", "is a section"),
        ("consent_reminder", "nope", "true or false"),
        ("exporters", "joplin", "JSON array"),
        ("after_note", "[1, 2]", "JSON array"),
        ("exporters", '["notion"]', "Unknown exporter"),
        ("summarizer.provider", "gpt", "Unknown summarizer"),
        ("template", "no-such-template", "No template named"),
        ("notes_dir", " ", "folder path"),
        ("joplin.url", "localhost:41184", "http://"),
        ("whisper_model", " ", "can't be empty"),
        ("language", "", "can't be empty"),
    ],
)
def test_set_rejects_bad_keys_and_values_without_writing(tmp_path, key, value, message):
    path = tmp_path / "config.toml"

    with pytest.raises(ConfigError, match=message):
        set_value(key, value, path)

    assert not path.exists()


def test_set_refuses_to_overwrite_a_broken_file(tmp_path):
    path = tmp_path / "config.toml"
    path.write_text("template = \n")

    with pytest.raises(ConfigError, match="isn't valid TOML"):
        set_value("template", "meeting", path)

    assert path.read_text() == "template = \n"


def run_cli(monkeypatch, capsys, *arguments: str) -> tuple[int, str, str]:
    monkeypatch.setattr(sys, "argv", ["afterword", *arguments])
    status, message = 0, ""
    try:
        cli.main()
    except SystemExit as exit:
        # sys.exit("afterword: …") carries the message; Python prints it to stderr on exit.
        if isinstance(exit.code, str):
            status, message = 1, exit.code
        else:
            status = exit.code or 0
    captured = capsys.readouterr()
    return status, captured.out, captured.err + message


def test_cli_set_then_show_json(tmp_path, monkeypatch, capsys):
    monkeypatch.setenv("XDG_CONFIG_HOME", str(tmp_path))

    assert run_cli(monkeypatch, capsys, "config", "set", "summarizer.model", "qwen3:32b")[0] == 0
    status, output, _ = run_cli(monkeypatch, capsys, "config", "show", "--json")

    assert status == 0
    assert json.loads(output)["summarizer"]["model"] == "qwen3:32b"
    assert (tmp_path / "afterword" / "config.toml").exists()


def test_cli_show_hides_the_token_unless_json(tmp_path, monkeypatch, capsys):
    monkeypatch.setenv("XDG_CONFIG_HOME", str(tmp_path))
    run_cli(monkeypatch, capsys, "config", "set", "joplin.token", "secret-token")

    _, text, _ = run_cli(monkeypatch, capsys, "config", "show")
    _, as_json, _ = run_cli(monkeypatch, capsys, "config", "show", "--json")

    assert "secret-token" not in text
    assert "joplin.token = (set)" in text
    assert json.loads(as_json)["joplin"]["token"] == "secret-token"


def test_cli_set_with_a_bad_value_fails_with_a_message(tmp_path, monkeypatch, capsys):
    monkeypatch.setenv("XDG_CONFIG_HOME", str(tmp_path))

    status, _, errors = run_cli(monkeypatch, capsys, "config", "set", "summarizer.provider", "gpt")

    assert status == 1
    assert "Unknown summarizer" in errors


def test_cli_set_reads_the_value_from_stdin_with_a_dash(tmp_path, monkeypatch, capsys):
    monkeypatch.setenv("XDG_CONFIG_HOME", str(tmp_path))
    monkeypatch.setattr(sys, "stdin", io.StringIO("secret-token\n"))

    status, _, _ = run_cli(monkeypatch, capsys, "config", "set", "joplin.token", "-")

    assert status == 0
    assert load_config(tmp_path / "afterword" / "config.toml").joplin.token == "secret-token"


def test_a_broken_config_gives_a_clear_error_instead_of_a_traceback(tmp_path, monkeypatch, capsys):
    monkeypatch.setenv("XDG_CONFIG_HOME", str(tmp_path))
    (tmp_path / "afterword").mkdir()
    (tmp_path / "afterword" / "config.toml").write_text("template = \n")

    status, _, errors = run_cli(monkeypatch, capsys, "config", "set", "template", "meeting")

    assert status == 1
    assert "config.toml isn't valid TOML" in errors


# MARK: test-joplin, against a fake Web Clipper on localhost


class FakeJoplin(BaseHTTPRequestHandler):
    token = "good-token"

    def do_GET(self):
        if self.path == "/ping":
            self.reply(200, b"JoplinClipperServer")
        elif self.path.startswith("/folders") and f"token={self.token}" in self.path:
            self.reply(200, b'{"items": [], "has_more": false}')
        else:
            self.reply(403, b'{"error": "Invalid token"}')

    def reply(self, status: int, body: bytes):
        self.send_response(status)
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *arguments):
        pass  # Keep test output quiet.


@pytest.fixture
def joplin_url():
    server = HTTPServer(("127.0.0.1", 0), FakeJoplin)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    yield f"http://127.0.0.1:{server.server_port}"
    server.shutdown()
    server.server_close()


def test_joplin_check_passes_with_a_good_token(joplin_url):
    connected, message = check_joplin(JoplinConfig(token="good-token", url=joplin_url))

    assert connected
    assert "Connected" in message


def test_joplin_check_reports_a_rejected_token(joplin_url):
    connected, message = check_joplin(JoplinConfig(token="wrong", url=joplin_url))

    assert not connected
    assert "rejected the token" in message


def test_joplin_check_reports_when_nothing_is_listening(joplin_url):
    server_gone = "http://127.0.0.1:9"  # The discard port; nothing answers HTTP there.

    connected, message = check_joplin(JoplinConfig(token="good-token", url=server_gone), timeout=2)

    assert not connected
    assert "Couldn't reach Joplin" in message


def test_joplin_check_needs_a_token_and_makes_no_request():
    connected, message = check_joplin(JoplinConfig(token="", url="http://192.0.2.1"))

    assert not connected
    assert "No Joplin token" in message
