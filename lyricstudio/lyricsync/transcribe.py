"""Speech-to-text with faster-whisper (local, free, no API key).

Two passes run here. The main pass transcribes the whole track. Then any stretch of
audio it left uncovered is re-transcribed on its own with much more permissive
settings - Whisper routinely drops the last chorus of a song because a repeated outro
trips its anti-repetition filter, or because the voice-activity filter clips the tail.
Rescued segments are checked before they are kept, so instrumental sections do not
fill up with "thanks for watching".
"""

from __future__ import annotations

import re
import sys
from dataclasses import dataclass, asdict
from pathlib import Path
from typing import Any, Iterable

from . import gpu

# Ordered best -> lightest. Anything faster-whisper accepts also works (incl. HF repo ids).
MODELS = (
    "large-v3",
    "large-v3-turbo",
    "distil-large-v3",
    "medium",
    "small",
    "base",
    "tiny",
)

SAMPLE_RATE = 16000
CONTEXT_PAD = 1.0      # seconds of audio decoded either side of a hole, for context only
EDGE_TOLERANCE = 0.3   # how far outside the hole a rescued word may still be kept

# Things Whisper says when it is listening to music or silence rather than words.
HALLUCINATIONS = {
    "thank you", "thanks for watching", "thank you for watching", "thanks for listening",
    "subscribe", "please subscribe", "like and subscribe", "bye", "bye bye", "goodbye",
    "you", "the end", "amen", "music", "outro", "intro", "silence", "applause",
    "instrumental", "copyright", "all rights reserved",
}

_SYMBOLS_ONLY = re.compile(r"^[\W_]+$", re.UNICODE)


@dataclass
class Word:
    start: float
    end: float
    text: str
    probability: float = 1.0

    def to_dict(self) -> dict:
        return asdict(self)

    @staticmethod
    def from_dict(d: dict) -> "Word":
        return Word(
            start=float(d["start"]),
            end=float(d["end"]),
            text=str(d["text"]),
            probability=float(d.get("probability", 1.0)),
        )


@dataclass
class Backend:
    device: str
    compute_type: str
    model: str

    def describe(self) -> str:
        where = "GPU (CUDA)" if self.device == "cuda" else "CPU"
        return f"{self.model} on {where} [{self.compute_type}]"


def pick_backend(model: str | None = None, device: str = "auto") -> Backend:
    """Choose the heaviest setup the machine can actually run."""
    if device == "auto":
        device = "cuda" if gpu.cuda_device_count() > 0 else "cpu"

    if device == "cuda":
        compute_type = "float16"
        default_model = "large-v3"
    else:
        compute_type = "int8"
        default_model = "medium"

    return Backend(device=device, compute_type=compute_type, model=model or default_model)


def load_model(backend: Backend):
    gpu.enable_cuda_libraries()
    from faster_whisper import WhisperModel

    try:
        return WhisperModel(backend.model, device=backend.device, compute_type=backend.compute_type)
    except Exception as exc:
        if backend.device != "cuda":
            raise
        print(f"  ! CUDA unavailable ({exc.__class__.__name__}: {exc}); falling back to CPU", file=sys.stderr)
        backend.device, backend.compute_type = "cpu", "int8"
        return WhisperModel(backend.model, device="cpu", compute_type="int8")


def transcribe(
    audio_path: str | Path,
    backend: Backend,
    *,
    language: str | None = None,
    initial_prompt: str | None = None,
    beam_size: int = 5,
    vad: bool = True,
    total_duration: float | None = None,
    progress: bool = True,
    rescue: bool = True,
    rescue_min: float = 10.0,
    compression_threshold: float = 3.0,
    no_speech_threshold: float = 0.5,
) -> tuple[list[Word], dict[str, Any]]:
    """Return every recognised word with its start/end time, plus some metadata."""
    model = load_model(backend)

    words, info = _run(
        model,
        str(audio_path),
        language=language,
        initial_prompt=initial_prompt,
        beam_size=beam_size,
        vad=vad,
        compression_threshold=compression_threshold,
        no_speech_threshold=no_speech_threshold,
        progress=progress,
        total=total_duration or 0.0,
    )

    total = total_duration or getattr(info, "duration", 0.0) or 0.0
    meta: dict[str, Any] = {
        "language": getattr(info, "language", language or "?"),
        "language_probability": round(float(getattr(info, "language_probability", 0.0) or 0.0), 3),
        "model": backend.model,
        "device": backend.device,
        "rescued": 0,
    }

    if rescue and total > 0:
        spans = uncovered_spans(words, total, minimum=rescue_min)
        if spans:
            found = _rescue(
                model,
                audio_path,
                spans,
                language=meta["language"] if meta["language"] != "?" else language,
                beam_size=beam_size,
                progress=progress,
            )
            if found:
                words = sorted(words + found, key=lambda w: w.start)
            meta["rescued"] = len(found)
            meta["rescue_spans"] = [(round(a, 1), round(b, 1)) for a, b in spans]

    words = _dedupe(words)
    meta["coverage"] = round(_covered_seconds(words) / total, 3) if total else 0.0
    meta["silent_spans"] = uncovered_spans(words, total, minimum=rescue_min) if total else []
    return words, meta


def _run(
    model,
    audio,
    *,
    language: str | None,
    initial_prompt: str | None,
    beam_size: int,
    vad: bool,
    compression_threshold: float,
    no_speech_threshold: float,
    progress: bool,
    total: float,
    offset: float = 0.0,
    keep: Any = None,
    vad_parameters: dict | None = None,
    hallucination_threshold: float | None = 2.0,
    label: str = "transcribing",
) -> tuple[list[Word], Any]:
    segments, info = model.transcribe(
        audio,
        language=language,
        beam_size=beam_size,
        word_timestamps=True,
        # Lyrics repeat by design; keeping the previous text in context makes Whisper
        # loop on choruses, so we deliberately turn that off.
        condition_on_previous_text=False,
        vad_filter=vad,
        vad_parameters=vad_parameters or {"min_silence_duration_ms": 500, "speech_pad_ms": 400},
        # Instrumental breaks are where Whisper invents "Thanks for watching!" lines.
        hallucination_silence_threshold=hallucination_threshold if vad else None,
        # A chorus sung six times is repetitive on purpose - the stock 2.4 throws those
        # segments away, which is exactly how the last 30 seconds of a song go missing.
        compression_ratio_threshold=compression_threshold,
        no_speech_threshold=no_speech_threshold,
        initial_prompt=initial_prompt,
        temperature=[0.0, 0.2, 0.4, 0.6, 0.8, 1.0],
    )

    words: list[Word] = []
    for segment in segments:
        if keep is not None and not keep(segment):
            continue
        for w in segment.words or []:
            text = w.word.strip()
            if not text or _SYMBOLS_ONLY.match(text):
                continue
            words.append(
                Word(
                    start=float(w.start) + offset,
                    end=float(w.end) + offset,
                    text=text,
                    probability=float(getattr(w, "probability", 1.0) or 1.0),
                )
            )
        if progress and total:
            pct = min(100.0, (segment.end + offset) / total * 100.0)
            print(f"\r  {label}... {pct:5.1f}%  ({len(words)} words)", end="", file=sys.stderr, flush=True)
    if progress:
        print(f"\r  {label}... 100.0%  ({len(words)} words)          ", file=sys.stderr, flush=True)
    return words, info


def _rescue(
    model,
    audio_path: str | Path,
    spans: list[tuple[float, float]],
    *,
    language: str | None,
    beam_size: int,
    progress: bool,
) -> list[Word]:
    """Re-listen to the stretches the main pass left empty."""
    try:
        from faster_whisper.audio import decode_audio

        audio = decode_audio(str(audio_path), sampling_rate=SAMPLE_RATE)
    except Exception as exc:  # pragma: no cover - depends on the decoder
        print(f"  ! second pass skipped ({exc.__class__.__name__}: {exc})", file=sys.stderr)
        return []

    duration = len(audio) / SAMPLE_RATE
    recovered: list[Word] = []
    for start, end in spans:
        # Decode a little wider than the hole so a word sitting right on the boundary is
        # not cut mid-syllable. The padding is context only - anything heard inside it
        # belongs to the neighbouring line and is dropped below.
        context_start = max(0.0, start - CONTEXT_PAD)
        context_end = min(duration, end + CONTEXT_PAD)
        chunk = audio[int(context_start * SAMPLE_RATE):int(context_end * SAMPLE_RATE)]
        if len(chunk) < SAMPLE_RATE:
            continue
        if progress:
            print(f"  second pass over {_clock(start)}-{_clock(end)}...", file=sys.stderr, flush=True)
        found, _ = _run(
            model,
            chunk,
            language=language,
            initial_prompt=None,
            beam_size=beam_size,
            vad=True,
            # A quiet or heavily produced vocal reads as "not speech" at the stock 0.5.
            vad_parameters={"threshold": 0.2, "min_silence_duration_ms": 1000, "speech_pad_ms": 400},
            hallucination_threshold=None,
            compression_threshold=10.0,
            no_speech_threshold=0.8,
            progress=False,
            total=0.0,
            offset=context_start,
            keep=_plausible,
            label="rescuing",
        )
        inside = [w for w in found if start - EDGE_TOLERANCE <= (w.start + w.end) / 2 <= end + EDGE_TOLERANCE]
        if progress:
            print(f"    recovered {len(inside)} words", file=sys.stderr, flush=True)
        recovered.extend(inside)
    return recovered


def _plausible(segment) -> bool:
    """Reject the things Whisper says when there is nothing to hear."""
    if float(getattr(segment, "no_speech_prob", 0.0) or 0.0) > 0.7:
        return False
    if float(getattr(segment, "avg_logprob", 0.0) or 0.0) < -1.0:
        return False
    text = re.sub(r"[^\w\s']", "", segment.text or "").strip().lower()
    if not text or text in HALLUCINATIONS:
        return False
    return True


def uncovered_spans(words: list[Word], duration: float, minimum: float = 10.0) -> list[tuple[float, float]]:
    """Stretches of at least `minimum` seconds with no recognised words in them."""
    if duration <= 0:
        return []
    if not words:
        return [(0.0, duration)] if duration >= minimum else []

    spans: list[tuple[float, float]] = []
    if words[0].start >= minimum:
        spans.append((0.0, words[0].start))
    for a, b in zip(words, words[1:]):
        if b.start - a.end >= minimum:
            spans.append((a.end, b.start))
    tail = duration - words[-1].end
    if tail >= minimum:
        spans.append((words[-1].end, duration))
    return spans


def _covered_seconds(words: list[Word]) -> float:
    if not words:
        return 0.0
    total, current_start, current_end = 0.0, words[0].start, words[0].end
    for word in words[1:]:
        if word.start > current_end:
            total += current_end - current_start
            current_start, current_end = word.start, word.end
        else:
            current_end = max(current_end, word.end)
    return total + (current_end - current_start)


def _clock(seconds: float) -> str:
    minutes, secs = divmod(max(0.0, float(seconds)), 60)
    return f"{int(minutes)}:{int(secs):02d}"


def _dedupe(words: Iterable[Word]) -> list[Word]:
    """Drop zero-length artefacts and force timestamps to move forward."""
    cleaned: list[Word] = []
    for w in sorted(words, key=lambda x: (x.start, x.end)):
        if w.end < w.start:
            w.end = w.start
        if cleaned:
            previous = cleaned[-1]
            if w.start < previous.start:
                w.start = previous.start
            # the same word heard twice, once per pass
            if w.text.lower() == previous.text.lower() and abs(w.start - previous.start) < 0.25:
                continue
        cleaned.append(w)
    return cleaned
