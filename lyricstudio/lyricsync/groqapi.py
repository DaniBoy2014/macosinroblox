"""Groq-hosted Whisper: the same word timestamps, seconds instead of minutes.

Uses whisper-large-v3-turbo through Groq's OpenAI-compatible audio endpoint.
The key comes from the GROQ_API_KEY environment variable, `~/.lyricsync/groq_key.txt`
(outside the repo, the safe place), or a `.groq_key.txt` next to the project
(git-ignored). No key = the local engine is used.
"""

from __future__ import annotations

import json
import os
import time
import urllib.error
import urllib.request
import uuid
from pathlib import Path
from typing import Any

from .transcribe import Word, _SYMBOLS_ONLY, _covered_seconds, _dedupe, uncovered_spans

API_URL = "https://api.groq.com/openai/v1/audio/transcriptions"
MODEL = "whisper-large-v3-turbo"
KEY_FILES = (
    Path.home() / ".lyricsync" / "groq_key.txt",
    Path(__file__).resolve().parent.parent / ".groq_key.txt",
)
MAX_UPLOAD_BYTES = 24 * 1024 * 1024  # free tier caps files at 25MB


class GroqError(RuntimeError):
    pass


def find_key() -> str | None:
    key = (os.environ.get("GROQ_API_KEY") or "").strip()
    for path in KEY_FILES:
        if key:
            break
        try:
            key = path.read_text(encoding="utf-8").strip()
        except OSError:
            key = ""
    if not key or "paste-your" in key:
        return None
    return key


def available() -> bool:
    return find_key() is not None


def _multipart(fields: list[tuple[str, str]], file_name: str, file_bytes: bytes) -> tuple[bytes, str]:
    boundary = uuid.uuid4().hex
    chunks: list[bytes] = []
    for name, value in fields:
        chunks.append(
            (f"--{boundary}\r\nContent-Disposition: form-data; "
             f'name="{name}"\r\n\r\n{value}\r\n').encode("utf-8"))
    chunks.append(
        (f"--{boundary}\r\nContent-Disposition: form-data; name=\"file\"; "
         f'filename="{file_name}"\r\nContent-Type: application/octet-stream\r\n\r\n'
         ).encode("utf-8"))
    chunks.append(file_bytes)
    chunks.append(f"\r\n--{boundary}--\r\n".encode("utf-8"))
    return b"".join(chunks), boundary


def transcribe_groq(
    audio_path: str | Path,
    *,
    original_path: str | Path | None = None,
    language: str | None = None,
    initial_prompt: str | None = None,
    total_duration: float | None = None,
    rescue_min: float = 10.0,
) -> tuple[list[Word], dict[str, Any]]:
    """Return (words, meta) shaped exactly like transcribe.transcribe()."""
    key = find_key()
    if not key:
        raise GroqError("no Groq API key found")

    path = Path(audio_path)
    upload_note = ""
    if path.stat().st_size > MAX_UPLOAD_BYTES and original_path is not None:
        # separated vocal stems are uncompressed wav - too big for the API,
        # so send the original compressed file instead
        path = Path(original_path)
        upload_note = " (original file - the vocal stem is over the upload cap)"
    if path.stat().st_size > MAX_UPLOAD_BYTES:
        raise GroqError(f"{path.name} is over the API upload limit "
                        f"({path.stat().st_size // 1_000_000}MB > 24MB)")

    fields = [
        ("model", MODEL),
        ("response_format", "verbose_json"),
        ("timestamp_granularities[]", "word"),
        ("timestamp_granularities[]", "segment"),
        ("temperature", "0"),
    ]
    if language:
        fields.append(("language", language))
    if initial_prompt:
        fields.append(("prompt", initial_prompt))

    body, boundary = _multipart(fields, path.name, path.read_bytes())
    request = urllib.request.Request(
        API_URL, data=body, method="POST",
        headers={
            "Authorization": f"Bearer {key}",
            "Content-Type": f"multipart/form-data; boundary={boundary}",
            "User-Agent": "lyricsync/1.0",
            "Accept": "application/json",
        })

    data = None
    for attempt in (1, 2):
        try:
            with urllib.request.urlopen(request, timeout=180) as response:
                data = json.loads(response.read().decode("utf-8"))
            break
        except urllib.error.HTTPError as exc:
            detail = ""
            try:
                detail = json.loads(exc.read().decode("utf-8"))["error"]["message"]
            except Exception:
                pass
            if exc.code == 429 and attempt == 1:
                wait = min(30.0, float(exc.headers.get("retry-after") or 10))
                time.sleep(wait)
                continue
            if exc.code == 401:
                raise GroqError("Groq rejected the API key (401) - check ~/.lyricsync/groq_key.txt") from exc
            raise GroqError(f"Groq HTTP {exc.code}: {detail or exc.reason}") from exc
        except urllib.error.URLError as exc:
            raise GroqError(f"could not reach Groq: {exc.reason}") from exc
    if data is None:
        raise GroqError("Groq kept rate-limiting the request (429)")

    words: list[Word] = []
    for w in data.get("words") or []:
        text = str(w.get("word") or "").strip()
        if not text or _SYMBOLS_ONLY.match(text):
            continue
        words.append(Word(start=float(w["start"]), end=float(w["end"]), text=text))
    words = _dedupe(words)

    total = total_duration or float(data.get("duration") or 0.0)
    meta: dict[str, Any] = {
        "language": data.get("language") or language or "?",
        "language_probability": 1.0,
        "model": f"groq/{MODEL}{upload_note}",
        "device": "groq-api",
        "rescued": 0,
        "coverage": round(_covered_seconds(words) / total, 3) if total else 0.0,
        "silent_spans": uncovered_spans(words, total, minimum=rescue_min) if total else [],
    }
    return words, meta
