import sys

from afterword import cli


def start_recording_with(tmp_path, monkeypatch, config_text: str, config_text_after_recording: str) -> list:
    """Run `afterword record`, rewriting config.toml while it "records" (as Settings would
    mid-call), and return the configs process_session was given."""
    config_home = tmp_path / "config"
    config_path = config_home / "afterword" / "config.toml"
    config_path.parent.mkdir(parents=True)
    config_path.write_text(f'sessions_dir = "{tmp_path / "sessions"}"\nconsent_reminder = false\n{config_text}')
    monkeypatch.setenv("XDG_CONFIG_HOME", str(config_home))

    def record_until_stopped(directory, include_call_audio):
        config_path.write_text(f'sessions_dir = "{tmp_path / "sessions"}"\n{config_text_after_recording}')
        return []

    processed_with = []
    monkeypatch.setattr(cli, "record_until_stopped", record_until_stopped)
    monkeypatch.setattr(cli, "process_session", lambda session, config: processed_with.append(config))
    monkeypatch.setattr(sys, "argv", ["afterword", "record", "--title", "Call"])

    cli.main()
    return processed_with


def test_record_writes_notes_with_the_provider_chosen_during_the_call(tmp_path, monkeypatch):
    processed_with = start_recording_with(
        tmp_path,
        monkeypatch,
        config_text='[summarizer]\nprovider = "anthropic"\n',
        config_text_after_recording='[summarizer]\nprovider = "claude-cli"\n',
    )

    assert [config.summarizer.provider for config in processed_with] == ["claude-cli"]


def test_record_keeps_its_starting_settings_if_the_config_broke_during_the_call(tmp_path, monkeypatch, capsys):
    processed_with = start_recording_with(
        tmp_path,
        monkeypatch,
        config_text='[summarizer]\nprovider = "ollama"\n',
        config_text_after_recording="[summarizer\n",
    )

    assert [config.summarizer.provider for config in processed_with] == ["ollama"]
    assert "isn't valid TOML" in capsys.readouterr().out
