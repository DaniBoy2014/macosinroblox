"""Align a hand-corrected lyrics file to Whisper's word timings.

Whisper is good at *when* words are sung and only okay at *what* the words are.
So the best workflow is: run once, fix the text in a .txt file (one lyric line per
line), then re-run with --lyrics-file. The wording and the line breaks come from
your file; the timings still come from the audio.
"""

from __future__ import annotations

import difflib
import re

from .lines import LineOptions, LyricLine, _clean
from .transcribe import Word

_SECTION = re.compile(r"^\s*[\[\{].*[\]\}]\s*$")          # [Chorus], [Verse 2]
_TOKEN = re.compile(r"[0-9a-z\u00c0-\u024f']+")


def normalize(text: str) -> str:
    text = text.lower().replace("\u2019", "'")
    return "".join(_TOKEN.findall(text))


def tokenize(line: str) -> list[str]:
    return [t for t in (normalize(p) for p in line.split()) if t]


def read_lyrics_file(path) -> list[str]:
    """One lyric line per text line. Blank lines and [Section] markers are ignored."""
    raw = open(path, "r", encoding="utf-8-sig").read().splitlines()
    return [ln.strip() for ln in raw if ln.strip() and not _SECTION.match(ln) and not ln.lstrip().startswith("#")]


def align_reference(ref_lines: list[str], words: list[Word], opts: LineOptions | None = None) -> list[LyricLine]:
    opts = opts or LineOptions()
    if not words:
        raise ValueError("no transcribed words to align against")
    if not ref_lines:
        return []

    ref_tokens: list[tuple[int, str]] = []
    for index, line in enumerate(ref_lines):
        for token in tokenize(line):
            ref_tokens.append((index, token))
    if not ref_tokens:
        return []

    hyp_tokens = [normalize(w.text) for w in words]
    matcher = difflib.SequenceMatcher(a=[t for _, t in ref_tokens], b=hyp_tokens, autojunk=False)

    mapping: dict[int, int] = {}
    for tag, i1, i2, j1, j2 in matcher.get_opcodes():
        if tag == "equal":
            for k in range(i2 - i1):
                mapping[i1 + k] = j1 + k
        elif tag == "replace":
            n, m = i2 - i1, j2 - j1
            for k in range(n):
                if m:
                    mapping[i1 + k] = j1 + min(m - 1, int(k * m / n))

    spans: list[tuple[float, float] | None] = [None] * len(ref_lines)
    for line_index in range(len(ref_lines)):
        hits = [mapping[i] for i, (li, _) in enumerate(ref_tokens) if li == line_index and i in mapping]
        if hits:
            spans[line_index] = (words[min(hits)].start, words[max(hits)].end)

    _fill_gaps(spans, words)

    out: list[LyricLine] = []
    previous_end = 0.0
    for line, span in zip(ref_lines, spans):
        start, end = span  # type: ignore[misc]
        start = max(start, previous_end)
        end = max(end, start + 0.25)
        previous_end = end
        text = _clean(line, opts.punctuation, opts.capitalize)
        if text:
            out.append(LyricLine(text=text, start=start, end=end, words=[]))
    return out


def _fill_gaps(spans: list[tuple[float, float] | None], words: list[Word]) -> None:
    """Interpolate lines that matched nothing (a mis-heard ad-lib, a shouted line)."""
    first, last = words[0].start, words[-1].end
    known = [i for i, s in enumerate(spans) if s is not None]
    if not known:
        step = (last - first) / max(1, len(spans))
        for i in range(len(spans)):
            spans[i] = (first + i * step, first + (i + 1) * step)
        return

    for i in range(len(spans)):
        if spans[i] is not None:
            continue
        before = max((k for k in known if k < i), default=None)
        after = min((k for k in known if k > i), default=None)
        low = spans[before][1] if before is not None else first  # type: ignore[index]
        high = spans[after][0] if after is not None else last    # type: ignore[index]
        if high <= low:
            high = low + 0.5
        run = [j for j in range(i, len(spans)) if spans[j] is None and (after is None or j < after)]
        share = (high - low) / max(1, len(run))
        for offset, j in enumerate(run):
            spans[j] = (low + offset * share, low + (offset + 1) * share)


def coverage(ref_lines: list[str], words: list[Word]) -> float:
    """Rough share of reference words Whisper also heard - a sanity score for the align."""
    ref = [t for line in ref_lines for t in tokenize(line)]
    hyp = [normalize(w.text) for w in words]
    if not ref:
        return 0.0
    matcher = difflib.SequenceMatcher(a=ref, b=hyp, autojunk=False)
    matched = sum(block.size for block in matcher.get_matching_blocks())
    return matched / len(ref)
