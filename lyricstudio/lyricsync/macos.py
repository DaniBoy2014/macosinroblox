"""Add a song and its synced lyrics to your macOS in Roblox Music.

Music's library is a folder tree, coolui_music in the executor's workspace on
this PC: every folder is a category with an info.json, and each song sits next
to its lyrics and cover:

    lofi/
      info.json                     title, description, ... and each song's details
      Raining Tacos.ogg
      Raining Tacos.lyrics.json     a lyricsync document; Music shows it as lyrics
      Raining Tacos.png             the song's cover

This only ever writes to this PC. Real's workspace is found by itself; for
another executor set its workspace once with
`python -m lyricsync macos --workspace PATH`.
"""

from __future__ import annotations

import json
import os
import re
import shutil
from pathlib import Path

from . import config

AUDIO_EXTENSIONS = {".mp3", ".ogg", ".wav"}
_UNSAFE = re.compile(r'[<>:"/\\|?*\x00-\x1f]')


class MacOSError(RuntimeError):
    pass


def pc_music() -> Path | None:
    """coolui_music in the executor's workspace on this PC."""
    saved = (config.load().get("macos_workspace") or "").strip()
    candidates = [Path(saved).expanduser()] if saved else []
    local = os.environ.get("LOCALAPPDATA")
    if local:
        candidates.append(Path(local) / "Real" / "workspace")
    for workspace in candidates:
        if workspace.is_dir():
            return workspace / "coolui_music"
    return None


def categories(root: Path | None = None) -> list[str]:
    """Every category folder in the library, as "lofi" or "lofi/chill"."""
    root = root or pc_music()
    if not root or not root.is_dir():
        return []
    names = {
        folder.relative_to(root).as_posix()
        for folder in root.rglob("*")
        if folder.is_dir() and not any(part.startswith(".") for part in folder.relative_to(root).parts)
    }
    return sorted(names, key=str.lower)


def safe_name(text: str) -> str:
    """A title as a file name ("AC/DC: Live?" -> "ACDC Live")."""
    name = re.sub(r"\s+", " ", _UNSAFE.sub("", text or "")).strip().rstrip(".")
    return name[:80].strip() or "Song"


def _category_parts(category: str) -> list[str]:
    parts = [part.strip() for part in (category or "").replace("\\", "/").split("/") if part.strip()]
    if not parts:
        raise MacOSError("pick a category (like lofi, or lofi/chill for one inside it)")
    for part in parts:
        if part in (".", "..") or _UNSAFE.search(part):
            raise MacOSError(f"“{part}” can't be a folder name")
    return parts


def _cover_extension(blob: bytes) -> str | None:
    if blob[:4] == b"\x89PNG":
        return ".png"
    if blob[:3] == b"\xff\xd8\xff":
        return ".jpg"
    return None


def add_song(root: Path, category: str, audio: Path, document: dict | None = None, *,
             title: str, artist: str = "", cover: bytes | None = None,
             name: str | None = None, sound_id: int | None = None) -> dict:
    """Copy `audio` (and its lyrics and cover) into `root/category`.

    Makes the category (with an info.json) if it's new, and records the song's
    title and artist in the category's info.json. Returns {"folder", "files"}.
    """
    audio = Path(audio)
    if audio.suffix.lower() not in AUDIO_EXTENSIONS:
        raise MacOSError(f"Roblox can only play mp3, ogg and wav, not {audio.suffix or 'this file'}")
    if not audio.exists():
        raise MacOSError(f"the audio file is gone: {audio}")
    parts = _category_parts(category)
    folder = Path(root).joinpath(*parts)
    folder.mkdir(parents=True, exist_ok=True)

    # The category's info.json: kept as it is, apart from this song's entry
    info_path = folder / "info.json"
    info: dict = {}
    if info_path.exists():
        try:
            info = json.loads(info_path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as exc:
            raise MacOSError(f"{info_path} isn't valid JSON, so it was left alone. Fix it first ({exc})") from exc
        if not isinstance(info, dict):
            raise MacOSError(f"{info_path} isn't a JSON object, so it was left alone")
    else:
        info = {"title": parts[-1].replace("-", " ").replace("_", " ").title(), "description": ""}

    # Already in this category (adding lyrics to a song that's there): keep its file
    if name is None and audio.resolve().parent == folder.resolve():
        name = audio.stem
    base = safe_name(name or title)
    target = folder / f"{base}{audio.suffix.lower()}"
    written = []
    if audio.resolve() != target.resolve():
        shutil.copyfile(audio, target)
    written.append(target)

    lyrics = folder / f"{base}.lyrics.json"
    if document and document.get("Lyrics"):
        lyrics.write_text(json.dumps(document, ensure_ascii=False), encoding="utf-8")
        written.append(lyrics)

    if cover:
        extension = _cover_extension(cover)
        if extension:
            picture = folder / f"{base}{extension}"
            picture.write_bytes(cover)
            written.append(picture)

    entry = {"title": title or base}
    if artist:
        entry["artist"] = artist
    if sound_id:
        entry["roblox"] = int(sound_id)
    songs = info.get("songs")
    if isinstance(songs, list):
        for item in songs:
            if isinstance(item, dict) and str(item.get("file", "")).lower() == target.name.lower():
                item.update(entry)
                break
        else:
            songs.append({"file": target.name, **entry})
    else:
        songs = songs if isinstance(songs, dict) else {}
        songs[target.name] = {**(songs.get(target.name) or {}), **entry}
    info["songs"] = songs
    info_path.write_text(json.dumps(info, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    written.append(info_path)
    return {"folder": folder, "files": written}


def add(category: str, audio: Path, document: dict | None = None, **details) -> dict:
    """add_song into this PC's coolui_music. Errors if there's no workspace."""
    root = pc_music()
    if not root:
        raise MacOSError(
            "Real's workspace isn't on this PC. For another executor, set its workspace "
            "with `python -m lyricsync macos --workspace PATH`"
        )
    return add_song(root, category, audio, document, **details)
