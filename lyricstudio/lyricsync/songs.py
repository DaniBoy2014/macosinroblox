"""The songs/ library folder.

Layout::

    songs/
      LyricsLibrary.lua        every song in one ModuleScript (regenerated each run)
      my-song/
        my-song.json           Roblox JSON document
        my-song.lua            the ["id"] = { ... } entry on its own
        my-song.lyrics.txt     editable transcript for the second pass

The library is rebuilt from the .json files on disk, so it always matches what is
in the folder - delete a song directory and it disappears from the module.
"""

from __future__ import annotations

import json
import re
from pathlib import Path
from typing import Any

from . import luafmt

LIBRARY_NAME = "LyricsLibrary.lua"


def slugify(name: str) -> str:
    """Filesystem- and Roblox-friendly folder name."""
    slug = re.sub(r"[^\w\s-]+", "", name, flags=re.UNICODE).strip()
    slug = re.sub(r"[\s_]+", "-", slug)
    slug = re.sub(r"-{2,}", "-", slug).strip("-.")
    return slug or "song"


def song_folder(songs_dir: Path, slug: str) -> Path:
    folder = Path(songs_dir) / slug
    folder.mkdir(parents=True, exist_ok=True)
    return folder


def load_documents(songs_dir: Path) -> list[dict[str, Any]]:
    """Every valid lyrics document under songs/, newest write wins per SoundId."""
    found: dict[str, dict[str, Any]] = {}
    songs_dir = Path(songs_dir)
    if not songs_dir.is_dir():
        return []
    for path in sorted(songs_dir.glob("*/*.json")):
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError, UnicodeDecodeError):
            continue
        if not isinstance(data, dict):
            continue
        if "SoundId" not in data or not isinstance(data.get("Lyrics"), list):
            continue
        if not data["SoundId"]:
            continue  # not on Roblox, so no use in a Roblox lyrics library
        found[str(data["SoundId"])] = data
    return list(found.values())


def rebuild_library(songs_dir: Path, library_name: str = LIBRARY_NAME) -> tuple[Path, int]:
    """Regenerate the combined ModuleScript. Returns (path, song count)."""
    songs_dir = Path(songs_dir)
    songs_dir.mkdir(parents=True, exist_ok=True)
    documents = load_documents(songs_dir)
    path = songs_dir / library_name
    path.write_text(luafmt.library(documents), encoding="utf-8")
    return path, len(documents)
