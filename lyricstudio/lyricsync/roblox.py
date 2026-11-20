"""Build the Roblox lyrics document.

Shape (matches the in-game format exactly):

    {"SoundId":6910191685,
     "Lyrics":[{"RightAligned":false,"Line":"...","Id":"L1",
                "TimeStart":1.067,"TimeEnd":5.397,"Adlibs":[]}, ...,
               {"RightAligned":false,"Line":"Written By X\nSynced By @X",
                "Id":"CERTIFICATION","TimeStart":50.941,"TimeEnd":59.488072562358279,
                "Adlibs":[]}],
     "Unsynced":false}

Two rules taken from real files: every line's TimeEnd is the next line's TimeStart
(the overlay always has exactly one active line), and the certification entry runs
from the last lyric until the raw, unrounded end of the audio.
"""

from __future__ import annotations

import json
from typing import Any

from .lines import LyricLine

CERTIFICATION_ID = "CERTIFICATION"
DEFAULT_CERTIFICATION = "Written By {written_by}\nSynced By @{synced_by}"


def certification_text(written_by: str, synced_by: str | None = None, template: str | None = None) -> str:
    synced_by = (synced_by or written_by).lstrip("@")
    template = template or DEFAULT_CERTIFICATION
    return template.replace("\n", "\n").format(written_by=written_by.lstrip("@"), synced_by=synced_by)


def build_document(
    sound_id: int,
    lines: list[LyricLine],
    duration: float,
    *,
    written_by: str,
    synced_by: str | None = None,
    certification_template: str | None = None,
    offset: float = 0.0,
    decimals: int = 3,
    chain: bool = True,
    align_mode: str = "none",  # none | alternate | all
    unsynced: bool = False,
    include_certification: bool = True,
    gap_threshold: float = 0.0,
    lead_in: float | None = None,
) -> dict[str, Any]:
    """Assemble the document.

    `gap_threshold` (seconds) turns instrumental breaks longer than that into blank
    GAP entries, so the overlay clears instead of holding the last line through a solo.
    """
    if not lines:
        raise ValueError("no lyric lines to write")

    times = _timeline(lines, duration, offset=offset, decimals=decimals, lead_in=lead_in)

    # (text, start, end, is_gap), in play order, with instrumental breaks made explicit.
    items: list[tuple[str, float, float, bool]] = []
    for index, (line, (start, end)) in enumerate(zip(lines, times)):
        items.append((line.text, start, end, False))
        if gap_threshold > 0 and index + 1 < len(times):
            next_start = times[index + 1][0]
            if next_start - end >= gap_threshold:
                items.append(("", end, next_start, True))

    if chain:
        # Hold every entry on screen until the next one starts.
        for i in range(len(items) - 1):
            text, start, _, is_gap = items[i]
            next_start = items[i + 1][1]
            items[i] = (text, start, max(next_start, start + 10 ** -decimals), is_gap)

    entries: list[dict[str, Any]] = []
    lyric_number = 0
    for position, (text, start, end, is_gap) in enumerate(items, start=1):
        if is_gap:
            entry_id = f"GAP_{position}"  # gaps are numbered by their slot in the list
        else:
            lyric_number += 1
            entry_id = f"L{lyric_number}"
        entries.append(
            {
                "RightAligned": False if is_gap else _right_aligned(align_mode, lyric_number),
                "Line": text,
                "Id": entry_id,
                "TimeStart": start,
                "TimeEnd": end,
                "Adlibs": [],
            }
        )

    if include_certification:
        last_end = entries[-1]["TimeEnd"]
        end_of_track = duration if duration > last_end + 0.05 else last_end + 5.0
        entries.append(
            {
                "RightAligned": False,
                "Line": certification_text(written_by, synced_by, certification_template),
                "Id": CERTIFICATION_ID,
                "TimeStart": last_end,
                "TimeEnd": end_of_track,
                "Adlibs": [],
            }
        )

    return {"SoundId": int(sound_id), "Lyrics": entries, "Unsynced": bool(unsynced)}


def _right_aligned(mode: str, index: int) -> bool:
    """`alternate` puts every second line on the right, the way duet overlays do."""
    if mode == "all":
        return True
    if mode == "alternate":
        return index % 2 == 0
    return False


def _timeline(
    lines: list[LyricLine],
    duration: float,
    *,
    offset: float,
    decimals: int,
    lead_in: float | None,
) -> list[tuple[float, float]]:
    ceiling = duration if duration > 0 else lines[-1].end + 5.0
    times: list[tuple[float, float]] = []
    for line in lines:
        start = min(max(0.0, line.start + offset), ceiling)
        end = min(max(start + 0.05, line.end + offset), ceiling)
        times.append((round(start, decimals), round(end, decimals)))

    # Force monotonic order in case a merge or an alignment nudged things backwards.
    for i in range(1, len(times)):
        start, end = times[i]
        previous_start, previous_end = times[i - 1]
        if start < previous_start:
            start = previous_start
        times[i] = (start, max(end, start + 10 ** -decimals))

    if lead_in is not None and times:
        start, end = times[0]
        times[0] = (round(max(0.0, min(start, lead_in)), decimals), end)

    return times


def dumps(document: dict[str, Any], *, pretty: bool = False, ascii_only: bool = False) -> str:
    if pretty:
        return json.dumps(document, indent=2, ensure_ascii=ascii_only)
    return json.dumps(document, separators=(",", ":"), ensure_ascii=ascii_only)


def preview(document: dict[str, Any], limit: int = 0) -> str:
    """Human-readable table of the document, for eyeballing the sync."""
    rows = []
    entries = document["Lyrics"]
    shown = entries if limit <= 0 else entries[:limit]
    for entry in shown:
        start, end = entry["TimeStart"], entry["TimeEnd"]
        label = entry["Line"].replace("\n", " / ") or "- instrumental -"
        rows.append(f"  {entry['Id']:>13}  {_clock(start)} -> {_clock(end)}  {label}")
    if limit and len(entries) > limit:
        rows.append(f"  ... {len(entries) - limit} more")
    return "\n".join(rows)


def _clock(seconds: float) -> str:
    minutes, secs = divmod(max(0.0, float(seconds)), 60)
    return f"{int(minutes):d}:{secs:06.3f}"
