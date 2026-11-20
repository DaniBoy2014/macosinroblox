"""Locate the NVIDIA CUDA libraries that pip installs, so CTranslate2 can load them.

On Windows the `nvidia-cublas-cu12` / `nvidia-cudnn-cu12` wheels drop their DLLs in
site-packages instead of anywhere on PATH, and CTranslate2 silently falls back to
"cannot load cudnn64_9.dll" unless the directories are registered first. Importing
this module before faster_whisper fixes that.
"""

from __future__ import annotations

import os
import sys

_prepared: list[str] | None = None


def enable_cuda_libraries() -> list[str]:
    """Register pip-installed CUDA DLL directories. Returns the dirs that were added."""
    global _prepared
    if _prepared is not None:
        return _prepared

    added: list[str] = []
    try:
        import nvidia  # noqa: F401  (namespace package created by the nvidia-* wheels)
    except ImportError:
        _prepared = added
        return added

    roots = [p for p in getattr(nvidia, "__path__", [])]
    for root in roots:
        for sub in sorted(os.listdir(root)) if os.path.isdir(root) else []:
            for leaf in ("bin", "lib"):
                d = os.path.join(root, sub, leaf)
                if not os.path.isdir(d):
                    continue
                has_lib = any(f.endswith((".dll", ".so", ".so.9", ".so.12")) for f in os.listdir(d))
                if not has_lib:
                    continue
                if sys.platform == "win32":
                    try:
                        os.add_dll_directory(d)
                    except OSError:
                        continue
                    os.environ["PATH"] = d + os.pathsep + os.environ.get("PATH", "")
                else:
                    os.environ["LD_LIBRARY_PATH"] = d + os.pathsep + os.environ.get("LD_LIBRARY_PATH", "")
                added.append(d)

    _prepared = added
    return added


def cuda_device_count() -> int:
    """Number of usable CUDA devices (0 when CTranslate2 has no GPU support)."""
    enable_cuda_libraries()
    try:
        import ctranslate2

        return int(ctranslate2.get_cuda_device_count())
    except Exception:
        return 0
