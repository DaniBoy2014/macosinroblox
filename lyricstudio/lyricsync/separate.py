"""Optional vocal isolation with Demucs.

Whisper was trained on speech, not on a mixed master. Pulling the vocal stem out
first is by far the biggest accuracy win on real music - it typically turns a
half-garbled transcript into a usable one. It needs torch, so it stays optional.
"""

from __future__ import annotations

import importlib.util
import subprocess
import sys
from pathlib import Path

DEFAULT_MODEL = "htdemucs"


def available() -> bool:
    return importlib.util.find_spec("demucs") is not None


def install(cuda: bool = True) -> bool:
    """pip install demucs (plus a CUDA build of torch when a GPU is present)."""
    from . import gpu

    if cuda and gpu.cuda_device_count() > 0 and importlib.util.find_spec("torch") is None:
        print("  installing torch (CUDA build, ~2.5 GB)...")
        subprocess.run(
            [sys.executable, "-m", "pip", "install", "torch", "torchaudio",
             "--index-url", "https://download.pytorch.org/whl/cu124"],
            check=False,
        )
    print("  installing demucs...")
    result = subprocess.run([sys.executable, "-m", "pip", "install", "demucs"], check=False)
    return result.returncode == 0 and available()


def _torch_device() -> str:
    try:
        import torch

        return "cuda" if torch.cuda.is_available() else "cpu"
    except Exception:
        return "cpu"


def separate_vocals(
    audio_path: str | Path,
    work_dir: str | Path,
    *,
    model: str = DEFAULT_MODEL,
    reuse: bool = True,
) -> Path:
    """Return the path to an isolated vocal track, running Demucs if needed."""
    audio_path = Path(audio_path)
    work_dir = Path(work_dir)
    expected = work_dir / model / audio_path.stem / "vocals.wav"

    if reuse and expected.exists():
        print(f"  reusing separated vocals: {expected.name}")
        return expected

    if not available():
        raise RuntimeError("demucs is not installed - run `python -m lyricsync setup --demucs`")

    work_dir.mkdir(parents=True, exist_ok=True)
    device = _torch_device()
    print(f"  separating vocals with {model} on {device} (this is the slow part)...")
    command = [
        sys.executable, "-m", "demucs",
        "--two-stems", "vocals",
        "-n", model,
        "-o", str(work_dir),
        "--device", device,
        str(audio_path),
    ]
    result = subprocess.run(command)
    if result.returncode != 0:
        raise RuntimeError(f"demucs failed with exit code {result.returncode}")
    if not expected.exists():
        matches = sorted(work_dir.rglob("vocals.wav"))
        if not matches:
            raise RuntimeError("demucs finished but produced no vocals.wav")
        return matches[-1]
    return expected
