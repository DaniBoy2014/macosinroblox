"""Small persistent config so you only type your username once."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

CONFIG_DIR = Path.home() / ".lyricsync"
CONFIG_PATH = CONFIG_DIR / "config.json"

DEFAULTS: dict[str, Any] = {
    "username": "",
    "model": "",           # empty = auto-pick based on hardware
    "separate": "auto",    # auto | always | never
    "api_url": "",         # Masters API base url for `lyricsync publish`
    "publish_key": "",     # optional x-masters-key header for publishing
    "macos_workspace": "", # executor workspace holding coolui_music (empty = find Real's)
    "macos_category": "",  # Lyric Studio's last "Add to macOS" category
}


def load() -> dict[str, Any]:
    data = dict(DEFAULTS)
    if CONFIG_PATH.exists():
        try:
            stored = json.loads(CONFIG_PATH.read_text(encoding="utf-8"))
            if isinstance(stored, dict):
                data.update({k: v for k, v in stored.items() if k in DEFAULTS})
        except (OSError, json.JSONDecodeError):
            pass
    return data


def save(**changes: Any) -> dict[str, Any]:
    # Keeps keys it doesn't know (another copy of lyricsync may use them)
    stored: dict[str, Any] = {}
    if CONFIG_PATH.exists():
        try:
            loaded = json.loads(CONFIG_PATH.read_text(encoding="utf-8"))
            if isinstance(loaded, dict):
                stored = loaded
        except (OSError, json.JSONDecodeError):
            pass
    stored = {**DEFAULTS, **stored}
    stored.update({k: v for k, v in changes.items() if k in DEFAULTS and v is not None})
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    CONFIG_PATH.write_text(json.dumps(stored, indent=2), encoding="utf-8")
    return load()
