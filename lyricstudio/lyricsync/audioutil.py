"""Audio probing and Roblox asset-id parsing."""

from __future__ import annotations

import json
import re
import shutil
import subprocess
from pathlib import Path

AUDIO_SUFFIXES = {".mp3", ".wav", ".ogg", ".flac", ".m4a", ".aac", ".opus", ".wma", ".mp4", ".webm"}


class AudioError(RuntimeError):
    pass


def parse_sound_id(raw: str | int) -> int:
    """Accept 6910191685, rbxassetid://6910191685, or a roblox.com asset/library URL."""
    if isinstance(raw, int):
        if raw <= 0:
            raise ValueError("sound id must be positive")
        return raw

    text = str(raw).strip()
    if text.isdigit():
        return int(text)

    patterns = (
        r"rbxassetid://(\d+)",
        r"[?&]id=(\d+)",
        r"/asset/?\?[^ ]*id=(\d+)",
        r"/(?:library|catalog|asset-?sounds?)/(\d+)",
        r"/(\d{5,})",
    )
    for pattern in patterns:
        m = re.search(pattern, text, re.IGNORECASE)
        if m:
            return int(m.group(1))

    digits = re.findall(r"\d{4,}", text)
    if digits:
        return int(max(digits, key=len))

    raise ValueError(f"could not find a Roblox sound id in {raw!r}")


def probe_duration(path: str | Path) -> float:
    """Length of the audio file in seconds (full float precision, like the sample file)."""
    path = Path(path)
    if not path.exists():
        raise AudioError(f"audio file not found: {path}")

    try:
        import av

        with av.open(str(path)) as container:
            if container.duration:
                return container.duration / av.time_base
            for stream in container.streams:
                if stream.type == "audio" and stream.duration and stream.time_base:
                    return float(stream.duration * stream.time_base)
    except Exception:
        pass

    ffprobe = shutil.which("ffprobe")
    if ffprobe:
        try:
            out = subprocess.run(
                [ffprobe, "-v", "quiet", "-print_format", "json", "-show_format", str(path)],
                capture_output=True,
                text=True,
                check=True,
            ).stdout
            value = json.loads(out).get("format", {}).get("duration")
            if value:
                return float(value)
        except Exception:
            pass

    raise AudioError(
        f"could not read the duration of {path.name}. Is it a valid audio file?"
    )


def fingerprint(path: str | Path) -> str:
    """Cheap identity for cache keys: size + mtime, no need to hash whole songs."""
    st = Path(path).stat()
    return f"{st.st_size}-{int(st.st_mtime)}"


def format_timestamp(seconds: float) -> str:
    seconds = max(0.0, float(seconds))
    minutes, secs = divmod(seconds, 60)
    return f"{int(minutes):02d}:{secs:06.3f}"
