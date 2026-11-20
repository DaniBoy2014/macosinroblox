"""Group timed words into display-sized lyric lines."""

from __future__ import annotations

import re
from dataclasses import dataclass, field

from .transcribe import Word

SENTENCE_END = (".", "?", "!", "\u2026")
CLAUSE_END = (",", ";", ":", "\u2014")

# Words no lyric line should end on when the break was forced by width alone.
DANGLING = {
    "a", "an", "and", "as", "at", "be", "but", "by", "for", "from", "he", "her", "his", "i",
    "if", "in", "into", "is", "it", "its", "my", "no", "of", "on", "or", "our", "she", "so",
    "than", "that", "the", "their", "them", "then", "they", "this", "to", "up", "was", "we",
    "were", "when", "will", "with", "you", "your",
}


@dataclass
class LyricLine:
    text: str
    start: float
    end: float
    words: list[Word] = field(default_factory=list)

    @property
    def duration(self) -> float:
        return self.end - self.start


@dataclass
class LineOptions:
    max_chars: int = 42
    max_duration: float = 7.0
    gap_split: float = 0.7
    min_words: int = 2
    min_duration: float = 0.9
    punctuation: str = "soft"  # keep | soft | strip
    capitalize: bool = False


def group_words(words: list[Word], opts: LineOptions | None = None) -> list[LyricLine]:
    """Split the word stream where a singer would actually breathe."""
    opts = opts or LineOptions()
    if not words:
        return []

    groups: list[list[Word]] = []
    current: list[Word] = []

    for word in words:
        if current:
            gap = word.start - current[-1].end
            width = len(_join(current)) + 1 + len(word.text)
            span = word.end - current[0].start
            prev = current[-1].text

            big_enough = len(current) >= opts.min_words
            should_break = (
                (gap >= opts.gap_split and (big_enough or gap >= opts.gap_split * 2))
                or (width > opts.max_chars and big_enough)
                or (span > opts.max_duration and big_enough)
                or (prev.endswith(SENTENCE_END) and width > opts.max_chars * 0.5)
                or (prev.endswith(CLAUSE_END) and width > opts.max_chars * 0.8)
            )
            if should_break:
                groups.append(current)
                current = []
        current.append(word)

    if current:
        groups.append(current)

    groups = _merge_runts(groups, opts)
    groups = _fix_dangling(groups, opts)
    return [
        LyricLine(text=_clean(_join(g), opts.punctuation, opts.capitalize), start=g[0].start, end=g[-1].end, words=list(g))
        for g in groups
        if _clean(_join(g), opts.punctuation, opts.capitalize)
    ]


def _merge_runts(groups: list[list[Word]], opts: LineOptions) -> list[list[Word]]:
    """Fold one-word / blink-length lines into whichever neighbour is closest in time."""
    if len(groups) < 2:
        return groups

    changed = True
    while changed and len(groups) > 1:
        changed = False
        for i, group in enumerate(groups):
            duration = group[-1].end - group[0].start
            runt = duration < opts.min_duration or len(group) < max(1, opts.min_words - 1)
            if not runt:
                continue

            prev_gap = group[0].start - groups[i - 1][-1].end if i > 0 else float("inf")
            next_gap = groups[i + 1][0].start - group[-1].end if i + 1 < len(groups) else float("inf")

            # A single stray word is worth a slightly over-wide line; anything
            # bigger has to fit inside --max-chars or it stays where it is.
            limit = int(opts.max_chars * 1.15) if len(group) == 1 else opts.max_chars

            target = None
            if prev_gap <= next_gap and i > 0 and len(_join(groups[i - 1] + group)) <= limit:
                target = i - 1
            elif i + 1 < len(groups) and len(_join(group + groups[i + 1])) <= limit:
                target = i + 1
            elif i > 0 and len(_join(groups[i - 1] + group)) <= limit:
                target = i - 1

            if target is None:
                continue
            if target < i:
                groups[target] = groups[target] + group
            else:
                groups[target] = group + groups[target]
            del groups[i]
            changed = True
            break
    return groups


def _fix_dangling(groups: list[list[Word]], opts: LineOptions) -> list[list[Word]]:
    """Push a trailing "in" / "the" / "and" down to the next line where it belongs.

    A width-forced break lands wherever the character budget runs out, which regularly
    leaves a line ending on a preposition. Only words that are still close in time to
    the next line may move - never across a real pause.
    """
    limit = int(opts.max_chars * 1.15)
    for i in range(len(groups) - 1):
        for _ in range(2):
            if len(groups[i]) < 2:
                break
            word = groups[i][-1]
            bare = word.text.strip().strip('"“”.,;:!?').lower()
            if bare not in DANGLING:
                break
            if word.text.strip().endswith(SENTENCE_END + CLAUSE_END):
                break
            if groups[i + 1][0].start - word.end > opts.gap_split:
                break
            if len(_join([word] + groups[i + 1])) > limit:
                break
            groups[i + 1] = [word] + groups[i + 1]
            groups[i] = groups[i][:-1]
    return [g for g in groups if g]


def _join(words: list[Word]) -> str:
    return " ".join(w.text for w in words).strip()


def _clean(text: str, mode: str, capitalize: bool = False) -> str:
    text = re.sub(r"\s+", " ", text).strip()
    text = text.replace(" ,", ",").replace(" .", ".").replace(" '", "'")
    if mode == "strip":
        text = re.sub(r"[.,;:!?\"\u201c\u201d\u2026]", "", text)
    elif mode == "soft":
        # Lyric overlays read better without trailing full stops; questions keep theirs.
        text = text.rstrip(" .,;:\u2026")
    text = re.sub(r"\s+", " ", text).strip()
    if capitalize and text:
        text = text[0].upper() + text[1:]
    return text


def rebalance(lines: list[LyricLine], opts: LineOptions) -> list[LyricLine]:
    """Second pass: break any line that is still too wide, at its widest internal gap."""
    out: list[LyricLine] = []
    for line in lines:
        if len(line.text) <= opts.max_chars * 1.35 or len(line.words) < 4:
            out.append(line)
            continue
        best_i, best_gap = None, -1.0
        for i in range(1, len(line.words)):
            gap = line.words[i].start - line.words[i - 1].end
            centred = 1.0 - abs(i - len(line.words) / 2) / len(line.words)
            score = gap + centred * 0.15
            if score > best_gap:
                best_i, best_gap = i, score
        if best_i is None:
            out.append(line)
            continue
        left, right = line.words[:best_i], line.words[best_i:]
        out.append(LyricLine(_clean(_join(left), opts.punctuation, opts.capitalize), left[0].start, left[-1].end, left))
        out.append(LyricLine(_clean(_join(right), opts.punctuation, opts.capitalize), right[0].start, right[-1].end, right))
    return out
