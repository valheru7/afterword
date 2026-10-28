"""`afterword config`: show and change settings without editing config.toml by hand.

The macOS app's Settings window uses these commands too, so Python stays the only place that
knows the config's keys, types, defaults and file format. Changes go through tomlkit, which
keeps the user's comments and formatting.
"""

import json
import os
import tempfile
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import asdict, fields, is_dataclass
from pathlib import Path
from typing import TYPE_CHECKING, Any, get_type_hints

from afterword.config import SUMMARIZER_PROVIDERS, Config, JoplinConfig, config_file
from afterword.exporters import EXPORTERS
from afterword.templates import load_templates

if TYPE_CHECKING:
    import tomlkit


class ConfigError(Exception):
    pass


# MARK: show


def effective_config(config: Config) -> dict[str, Any]:
    """The config with defaults filled in, as JSON-friendly values (paths as expanded strings)."""
    return json.loads(json.dumps(asdict(config), default=str))


def flattened(values: dict[str, Any], prefix: str = "") -> list[tuple[str, Any]]:
    """{"joplin": {"url": …}} → [("joplin.url", …)], the same dotted keys `config set` takes."""
    pairs = []
    for name, value in values.items():
        if isinstance(value, dict):
            pairs.extend(flattened(value, prefix=f"{prefix}{name}."))
        else:
            pairs.append((f"{prefix}{name}", value))
    return pairs


# MARK: set


def settable_keys() -> list[str]:
    keys = []
    for name, kind in get_type_hints(Config).items():
        if is_dataclass(kind):
            keys.extend(f"{name}.{field.name}" for field in fields(kind))
        else:
            keys.append(name)
    return keys


def set_value(key: str, text: str, path: Path | None = None) -> Any:
    """Parses `text` for `key`'s type, validates it and writes it to the config file.
    Returns the stored value."""
    kind = field_type(key)
    value = parse_value(key, text, kind)
    validate(key, value)

    tomlkit = import_tomlkit()
    # Follow a symlinked config.toml (e.g. one kept in a dotfiles repo) so the new file replaces
    # the real one, and the link stays a link.
    path = (path or config_file()).resolve()
    document = read_document(path)
    *section, name = key.split(".")
    table = document
    if section:
        if section[0] not in document:
            document[section[0]] = tomlkit.table()
        table = document[section[0]]
    table[name] = value
    write_atomically(path, tomlkit.dumps(document))
    return value


def field_type(key: str) -> Any:
    """The Config field's type for a dotted key like `template` or `joplin.token`."""
    parts = key.split(".")
    hints = get_type_hints(Config)
    kind = hints.get(parts[0])
    if kind is None or len(parts) > 2:
        raise unknown_key(key)

    if is_dataclass(kind):
        if len(parts) == 1:
            options = ", ".join(f"{key}.{field.name}" for field in fields(kind))
            raise ConfigError(f"{key} is a section. Set one of its keys: {options}")
        kind = get_type_hints(kind).get(parts[1])
        if kind is None:
            raise unknown_key(key)
        return kind

    if len(parts) == 2:
        raise unknown_key(key)
    return kind


def unknown_key(key: str) -> ConfigError:
    return ConfigError(f"Unknown setting {key!r}. Settings: {', '.join(settable_keys())}")


def parse_value(key: str, text: str, kind: Any) -> Any:
    if kind is bool:
        if text not in ("true", "false"):
            raise ConfigError(f"{key} is true or false, not {text!r}.")
        return text == "true"
    if kind is Path:
        if not text.strip():
            raise ConfigError(f"{key} needs a folder path.")
        return text  # Stored as typed (e.g. with ~), expanded when the config is loaded.
    if kind == list[str]:
        try:
            value = json.loads(text)
        except json.JSONDecodeError:
            value = None
        if not isinstance(value, list) or not all(isinstance(item, str) for item in value):
            raise ConfigError(f'{key} is a list of strings, written as a JSON array: \'["a", "b"]\'')
        return value
    if kind is str:
        return text
    raise ConfigError(f"{key} can't be set from the command line.")


def validate(key: str, value: Any) -> None:
    match key:
        case "template":
            names = sorted(load_templates())
            if value not in names:
                raise ConfigError(f"No template named {value!r}. Templates: {', '.join(names)}")
        case "summarizer.provider":
            if value not in SUMMARIZER_PROVIDERS:
                raise ConfigError(f"Unknown summarizer {value!r}. Use {', '.join(SUMMARIZER_PROVIDERS)}.")
        case "exporters":
            unknown = [name for name in value if name not in EXPORTERS]
            if unknown:
                raise ConfigError(f"Unknown exporter {unknown[0]!r}. Exporters: {', '.join(EXPORTERS)}")
        case "whisper_model":
            if not value.strip():
                raise ConfigError("whisper_model can't be empty. The default is large-v3-turbo-q5_0.")
        case "language":
            if not value.strip():
                raise ConfigError("language can't be empty. Use a code like en, or auto to detect it.")
        case "joplin.url":
            if not value.startswith(("http://", "https://")):
                raise ConfigError("joplin.url should start with http:// (usually http://localhost:41184).")


def import_tomlkit():
    """Imported only when changing settings, so the rest of the CLI (recording above all) keeps
    working in an install made before tomlkit was a dependency."""
    try:
        import tomlkit
    except ImportError as error:
        raise ConfigError(
            "Changing settings needs the tomlkit package. Reinstall Afterword from its folder: "
            "uv tool install --editable . --reinstall"
        ) from error
    return tomlkit


def read_document(path: Path) -> "tomlkit.TOMLDocument":
    tomlkit = import_tomlkit()
    if not path.exists():
        return tomlkit.document()
    try:
        return tomlkit.parse(path.read_text(encoding="utf-8"))  # TOML is always UTF-8.
    except tomlkit.exceptions.ParseError as error:
        raise ConfigError(f"{path} isn't valid TOML ({error}). Fix it by hand first.") from error


def write_atomically(path: Path, text: str) -> None:
    """Writes to a temporary file next to the config and renames it over the old one, so a
    crash never leaves half a config. The file stays readable only by you (0600) because it
    can hold the Joplin token."""
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary = tempfile.mkstemp(dir=path.parent, prefix=".config-", suffix=".toml")
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as file:
            file.write(text)
            file.flush()
            os.fsync(file.fileno())
        os.chmod(temporary, 0o600)
        os.replace(temporary, path)
    except BaseException:
        Path(temporary).unlink(missing_ok=True)
        raise


# MARK: test-joplin


class RefuseRedirects(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None  # urllib then raises the 3xx as an HTTPError instead of following it.


def joplin_only_opener() -> urllib.request.OpenerDirector:
    """Talks only to the URL it's given: no proxy from the environment, no following redirects."""
    return urllib.request.build_opener(urllib.request.ProxyHandler({}), RefuseRedirects())


def check_joplin(config: JoplinConfig, timeout: float = 5) -> tuple[bool, str]:
    """Checks that Joplin's Web Clipper answers at `config.url` and accepts the token.
    Makes no network calls except to that URL."""
    if not config.token:
        return False, "No Joplin token set. Copy it from Joplin → Settings → Web Clipper → Advanced options."

    base_url = config.url.rstrip("/")
    opener = joplin_only_opener()
    try:
        with opener.open(f"{base_url}/ping", timeout=timeout) as response:
            reply = response.read().decode(errors="replace")
    except (OSError, ValueError):  # URLError and HTTPError are OSErrors; ValueError is a malformed URL.
        return False, f"Couldn't reach Joplin at {base_url}. Is Joplin open with the Web Clipper service on?"
    if "JoplinClipperServer" not in reply:
        return False, f"Something answered at {base_url}, but it isn't Joplin's Web Clipper."

    # The same endpoint the exporter lists notebooks with; a bad token gets 403.
    query = urllib.parse.urlencode({"token": config.token, "limit": 1})
    try:
        with opener.open(f"{base_url}/folders?{query}", timeout=timeout):
            pass
    except urllib.error.HTTPError as error:
        if error.code in (401, 403):
            return False, "Joplin is running, but it rejected the token. Copy it again from the Web Clipper settings."
        return False, f"Joplin returned {error.code} when listing notebooks."
    except OSError:
        return False, f"Joplin at {base_url} stopped answering. Try again."
    return True, f"Connected to Joplin at {base_url}."
