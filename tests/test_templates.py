from afterword.templates import load_templates, parse_template


def test_parse_reads_header_and_body():
    template = parse_template("---\nname: standup\ndescription: Daily standup.\n---\nList blockers.\n", fallback_name="x")

    assert template.name == "standup"
    assert template.description == "Daily standup."
    assert template.instructions == "List blockers."


def test_parse_without_header_uses_the_file_name():
    template = parse_template("Just summarize it.", fallback_name="plain")

    assert template.name == "plain"
    assert template.instructions == "Just summarize it."


def test_builtin_templates_load():
    templates = load_templates()

    assert {"job-interview", "meeting", "one-on-one"} <= templates.keys()
    assert all(template.instructions for template in templates.values())


def test_user_template_replaces_builtin_with_the_same_name(tmp_path):
    (tmp_path / "my-meeting.md").write_text("---\nname: meeting\ndescription: Mine.\n---\nShort notes only.\n")

    templates = load_templates(user_dir=tmp_path)

    assert templates["meeting"].description == "Mine."
    assert "job-interview" in templates
