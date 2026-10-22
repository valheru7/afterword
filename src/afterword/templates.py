"""Templates tell the summarizer what kind of notes to write. Each is a markdown file with
a small header:

    ---
    name: job-interview
    description: You're the candidate. Questions asked, how you answered, next steps.
    ---
    (instructions for the summarizer)

Built-in templates ship in afterword/templates/. Drop your own in
~/.config/afterword/templates/ — a file with the same name replaces the built-in one.
"""

from dataclasses import dataclass
from importlib import resources
from pathlib import Path

from afterword.config import config_dir


@dataclass(frozen=True)
class Template:
    name: str
    description: str
    instructions: str


def user_templates_dir() -> Path:
    return config_dir() / "templates"


def load_templates(user_dir: Path | None = None) -> dict[str, Template]:
    templates: dict[str, Template] = {}
    builtin_dir = resources.files("afterword") / "templates"
    for file in builtin_dir.iterdir():
        if file.name.endswith(".md"):
            template = parse_template(file.read_text(), fallback_name=file.name.removesuffix(".md"))
            templates[template.name] = template

    user_dir = user_dir or user_templates_dir()
    if user_dir.is_dir():
        for file in sorted(user_dir.glob("*.md")):
            template = parse_template(file.read_text(), fallback_name=file.stem)
            templates[template.name] = template
    return templates


def get_template(name: str) -> Template:
    templates = load_templates()
    if name not in templates:
        available = ", ".join(sorted(templates))
        raise KeyError(f"No template named {name!r}. Available: {available}")
    return templates[name]


def parse_template(text: str, fallback_name: str) -> Template:
    header: dict[str, str] = {}
    body = text
    if text.startswith("---\n"):
        header_text, _, body = text[4:].partition("\n---\n")
        for line in header_text.splitlines():
            key, separator, value = line.partition(":")
            if separator:
                header[key.strip()] = value.strip()
    return Template(
        name=header.get("name", fallback_name),
        description=header.get("description", ""),
        instructions=body.strip(),
    )
