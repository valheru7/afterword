"""Sends notes to Joplin through its local Web Clipper API.

Turn it on in Joplin → Settings → Web Clipper → Enable Web Clipper Service, then copy the
authorization token from "Advanced options" into `[joplin] token` in the config."""

import json
import urllib.error
import urllib.parse
import urllib.request

from afterword.config import JoplinConfig
from afterword.note import Note


class JoplinError(Exception):
    pass


def export(note: Note, config: JoplinConfig) -> str:
    if not config.token:
        raise JoplinError("Set `token` under [joplin] in the config (Joplin → Settings → Web Clipper).")
    joplin = JoplinClient(config.url, config.token)
    notebook_id = joplin.find_or_create_notebook(config.notebook)
    note_id = joplin.post("/notes", {"title": note.title, "body": note.body, "parent_id": notebook_id})["id"]
    for tag in note.tags:
        tag_id = joplin.find_or_create_tag(tag)
        joplin.post(f"/tags/{tag_id}/notes", {"id": note_id})
    return f"Joplin notebook “{config.notebook}”"


class JoplinClient:
    def __init__(self, base_url: str, token: str):
        self.base_url = base_url.rstrip("/")
        self.token = token

    def find_or_create_notebook(self, title: str) -> str:
        for folder in self.get_all("/folders"):
            if folder["title"] == title:
                return folder["id"]
        return self.post("/folders", {"title": title})["id"]

    def find_or_create_tag(self, title: str) -> str:
        # Joplin stores tag titles in lowercase.
        title = title.lower()
        for tag in self.get_all("/tags"):
            if tag["title"] == title:
                return tag["id"]
        return self.post("/tags", {"title": title})["id"]

    def get_all(self, path: str) -> list[dict]:
        """Joplin pages list results; walk every page."""
        items: list[dict] = []
        page = 1
        while True:
            response = self.request("GET", path, query={"page": page})
            items.extend(response["items"])
            if not response.get("has_more"):
                return items
            page += 1

    def post(self, path: str, body: dict) -> dict:
        return self.request("POST", path, body=body)

    def request(self, method: str, path: str, query: dict | None = None, body: dict | None = None) -> dict:
        params = urllib.parse.urlencode({"token": self.token, **(query or {})})
        http_request = urllib.request.Request(
            f"{self.base_url}{path}?{params}",
            method=method,
            data=json.dumps(body).encode() if body is not None else None,
            headers={"Content-Type": "application/json"},
        )
        try:
            with urllib.request.urlopen(http_request) as response:
                return json.load(response)
        except urllib.error.HTTPError as error:
            raise JoplinError(f"Joplin returned {error.code} for {method} {path}. Check the token.") from error
        except urllib.error.URLError as error:
            raise JoplinError(
                f"Couldn't reach Joplin at {self.base_url}. Is Joplin open with the Web Clipper service on?"
            ) from error
