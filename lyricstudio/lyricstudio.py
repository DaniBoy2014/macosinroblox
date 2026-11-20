"""Lyric Studio - GUI companion for lyricsync and the Masters music player.

Put in a Roblox music id, download the audio, auto-sync lyrics with whisper,
preview them in a Masters-style player, edit lines/timings, and publish to the
Masters API (including editing lyrics that were published before).

    python lyricstudio.py
    python lyricstudio.py --selftest 9245470035   (headless network check)

Audio preview needs pygame:  python -m pip install pygame
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.request
from pathlib import Path

import tkinter as tk
from tkinter import filedialog, messagebox, ttk

try:
    import pygame

    pygame.mixer.init()
    AUDIO_OK = True
except Exception:
    AUDIO_OK = False

HERE = Path(__file__).resolve().parent
DOWNLOADS = HERE / "downloads"
CONFIG_PATH = Path.home() / ".lyricsync" / "config.json"

# Masters-ish dark theme
BG = "#0f0f0f"
BG2 = "#181818"
BG3 = "#232323"
FG = "#ffffff"
FG2 = "#9b9b9b"
ACCENT = "#ffffff"
HILIGHT = "#2e2e2e"


# ----------------------------------------------------------------- helpers


def load_config() -> dict:
    try:
        return json.loads(CONFIG_PATH.read_text(encoding="utf-8"))
    except Exception:
        return {}


# Secrets live in ~/.lyricsync (outside the repo). A copy next to this file
# also works; .gitignore keeps it out of git.
SECRETS_DIR = Path.home() / ".lyricsync"


def groq_ready() -> bool:
    if os.environ.get("GROQ_API_KEY"):
        return True
    for path in (SECRETS_DIR / "groq_key.txt", HERE / ".groq_key.txt"):
        try:
            key = path.read_text(encoding="utf-8").strip()
        except OSError:
            continue
        if key and "paste-your" not in key:
            return True
    return False


def roblox_cookie() -> str | None:
    """Optional .ROBLOSECURITY cookie so gated audio can be downloaded.

    Put the cookie value in ~/.lyricsync/roblosecurity.txt. It only ever goes
    to roblox.com hosts.
    """
    for path in (SECRETS_DIR / "roblosecurity.txt", HERE / ".roblosecurity.txt"):
        try:
            value = path.read_text(encoding="utf-8").strip()
        except OSError:
            continue
        if value:
            return value
    return None


def http_get(url: str, timeout: int = 30, auth: bool = False) -> bytes:
    headers = {"User-Agent": "LyricStudio/1.0"}
    if auth:
        cookie = roblox_cookie()
        if cookie:
            headers["Cookie"] = f".ROBLOSECURITY={cookie}"
    req = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.read()


def parse_sound_id(text: str) -> int:
    match = re.search(r"(\d{4,})", text or "")
    if not match:
        raise ValueError("that does not look like a Roblox audio id")
    return int(match.group(1))


def fetch_details(sound_id: int) -> dict:
    """Title/artist via the audio metadata the thumbnails+economy APIs expose."""
    out = {"title": "", "artist": ""}
    try:
        data = json.loads(http_get(f"https://economy.roblox.com/v2/assets/{sound_id}/details"))
        out["title"] = data.get("Name") or ""
        out["artist"] = (data.get("Creator") or {}).get("Name") or ""
    except Exception:
        pass
    return out


def discover_artist_songs(query: str, log=lambda _m: None,
                          max_ids: int = 150) -> tuple[str, list[tuple[int, str]]]:
    """Find an artist's audio catalog on Roblox.

    `query` is either an artist name, or a music id of one of their songs (in
    which case the artist name is read from that song's title/creator first).
    Returns (artist_name, [(sound_id, title), ...]) filtered to titles that
    actually mention the artist, so distributor noise is dropped.
    """
    import urllib.parse

    def audio_details(chunk: list[int]) -> list[dict]:
        """[(id, name, artist)] from the toolbox details endpoint."""
        if not chunk:
            return []
        q = ",".join(str(x) for x in chunk)
        try:
            data = json.loads(http_get(
                f"https://apis.roblox.com/toolbox-service/v1/items/details?assetIds={q}",
                timeout=20))
        except Exception:
            return []
        rows = []
        for entry in data.get("data") or []:
            asset = entry.get("asset") or {}
            ad = asset.get("audioDetails") or {}
            sid = asset.get("id")
            if sid:
                rows.append({"id": int(sid), "name": asset.get("name") or "",
                             "artist": ad.get("artist") or ""})
        return rows

    artist = (query or "").strip()
    # if they gave a music id, read the real artist from its audio metadata (the
    # uploader is often a distributor like DistrokidOfficial, not the artist)
    if re.fullmatch(r"\d{4,}", artist):
        rows = audio_details([int(artist)])
        found = rows[0]["artist"] if rows else ""
        if not found:  # fall back to a "Artist - Title" style name
            title = (fetch_details(int(artist)).get("title") or "")
            found = title.split(" - ")[0].strip() if " - " in title else title
        artist = found.strip()
        log(f"seed song {query} -> artist “{artist}”")
    if not artist:
        return "", []
    key = artist.lower()

    # keyword-search the audio catalog, then keep songs whose ARTIST metadata
    # matches (mirrors how Masters groups by AudioSearchParams.Artist). Pages
    # until it has collected max_ids matches or the results run out.
    songs: list[tuple[int, str]] = []
    seen: set[int] = set()
    cursor = ""
    scanned = 0
    for _ in range(12):
        url = ("https://apis.roblox.com/toolbox-service/v1/marketplace/3"
               f"?keyword={urllib.parse.quote(artist)}&limit=30")
        if cursor:
            url += "&cursor=" + urllib.parse.quote(cursor)
        try:
            page = json.loads(http_get(url, timeout=20))
        except Exception as exc:
            log(f"search failed: {exc}")
            break
        ids = [item["id"] for item in page.get("data", []) if item.get("id")]
        scanned += len(ids)
        for row in audio_details(ids):
            ra = row["artist"].strip().lower()
            # exact artist match, or (when the metadata artist is blank) a
            # "Artist - Title" style name
            if row["id"] not in seen and (ra == key or (not ra and key in row["name"].lower())):
                seen.add(row["id"])
                songs.append((row["id"], row["name"]))
        cursor = page.get("nextPageCursor")
        if not cursor or len(songs) >= max_ids:
            break
    songs = songs[:max_ids]
    log(f"scanned {scanned} candidate(s), {len(songs)} by “{artist}”")
    return artist, songs


def sync_one_song(app, sound_id: int, publish: bool, use_groq: bool,
                  log, prefix: str) -> bool:
    """Download + sync (+ optionally publish) a single song. Returns True on
    success. Shared by the Bulk Sync and Artist Sync windows."""
    details = fetch_details(sound_id)
    title = details["title"] or str(sound_id)
    log(f"{prefix} {title} - downloading...")
    audio = download_audio(sound_id)

    log(f"{prefix} syncing...")
    out = DOWNLOADS / f"{sound_id}.sync.json"
    cmd = [sys.executable, "-m", "lyricsync", "sync", str(audio),
           "--id", str(sound_id), "--user", app.username,
           "-o", str(out), "--format", "json", "--quiet"]
    if use_groq:
        cmd += ["--engine", "groq", "--separate", "never"]
    proc = subprocess.run(cmd, cwd=HERE, capture_output=True,
                          text=True, encoding="utf-8", errors="replace")
    if proc.returncode != 0 or not out.exists():
        tail = (proc.stderr or proc.stdout or "").strip().splitlines()
        raise RuntimeError(tail[-1] if tail else f"exit {proc.returncode}")
    doc = json.loads(out.read_text(encoding="utf-8"))
    count = len(doc.get("Lyrics") or [])
    if count == 0:
        raise RuntimeError("no lyric lines produced (instrumental?)")
    if publish:
        ok, note = api_publish(app.api_url, app.publish_key, doc)
        if not ok:
            raise RuntimeError(f"publish failed: {note}")
        log(f"{prefix} OK - {count} lines published ({note})")
    else:
        log(f"{prefix} OK - {count} lines synced (not published)")
    return True


def fetch_thumbnail(sound_id: int) -> bytes | None:
    try:
        data = json.loads(http_get(
            "https://thumbnails.roblox.com/v1/assets"
            f"?assetIds={sound_id}&size=420x420&format=Png"))
        url = data["data"][0]["imageUrl"]
        return http_get(url)
    except Exception:
        return None


def sniff_extension(blob: bytes) -> str | None:
    if blob[:4] == b"OggS":
        return ".ogg"
    if blob[:3] == b"ID3" or blob[:2] in (b"\xff\xfb", b"\xff\xf3", b"\xff\xf2"):
        return ".mp3"
    if blob[:4] == b"RIFF":
        return ".wav"
    if blob[:4] == b"fLaC":
        return ".flac"
    if len(blob) > 12 and blob[4:8] == b"ftyp":
        return ".m4a"
    return None


def validate_or_repair(path: Path) -> Path | None:
    """Make sure a cached download really is audio; un-gzip stale blobs.

    Returns the (possibly renamed) valid path, or None when the file is junk.
    """
    try:
        blob = path.read_bytes()
    except OSError:
        return None
    changed = False
    if blob[:2] == b"\x1f\x8b":
        import gzip
        try:
            blob = gzip.decompress(blob)
        except OSError:
            return None
        changed = True
    ext = sniff_extension(blob)
    if ext is None:
        return None
    target = path.with_suffix(ext)
    if changed or target != path:
        target.write_bytes(blob)
        if target != path:
            path.unlink(missing_ok=True)
    return target


def download_audio(sound_id: int) -> Path:
    """Fetch the audio file for a Roblox sound id into downloads/."""
    DOWNLOADS.mkdir(exist_ok=True)
    for ext in (".ogg", ".mp3", ".wav", ".flac", ".m4a"):
        existing = DOWNLOADS / f"{sound_id}{ext}"
        if existing.exists():
            repaired = validate_or_repair(existing)
            if repaired is not None:
                return repaired
            existing.unlink(missing_ok=True)  # junk from an old version - redownload
            break

    blob = None
    try:  # v2 hands out a CDN location (auth helps for gated audio)
        data = json.loads(http_get(
            f"https://assetdelivery.roblox.com/v2/asset/?id={sound_id}", auth=True))
        locations = data.get("locations") or []
        if locations and locations[0].get("location"):
            blob = http_get(locations[0]["location"], timeout=60, auth=True)
    except Exception:
        blob = None
    if blob is None:
        try:  # v1 returns the bytes directly
            blob = http_get(f"https://assetdelivery.roblox.com/v1/asset/?id={sound_id}",
                            timeout=60, auth=True)
        except urllib.error.HTTPError as exc:
            hint = (" Put your .ROBLOSECURITY cookie in ~/.lyricsync/roblosecurity.txt "
                    "to download gated audio," if not roblox_cookie() else "")
            raise RuntimeError(
                f"Roblox refused the download (HTTP {exc.code}).{hint} or use "
                "'Load Audio...' with a local file instead."
            ) from exc
    if not blob or len(blob) < 1000:
        raise RuntimeError("download came back empty - use 'Load Audio...' instead")

    if blob[:2] == b"\x1f\x8b":  # Roblox's CDN often serves assets gzip-compressed
        import gzip
        blob = gzip.decompress(blob)

    ext = sniff_extension(blob)
    if ext is None:
        raise RuntimeError("the download is not audio (unrecognised file format) - "
                           "use 'Load Audio...' with a local file instead")

    path = DOWNLOADS / f"{sound_id}{ext}"
    path.write_bytes(blob)
    return path


def api_fetch_lyrics(api: str, sound_id: int) -> dict | None:
    try:
        return json.loads(http_get(f"{api.rstrip('/')}/api/lyrics?songId={sound_id}"))
    except urllib.error.HTTPError:
        return None


def api_published_ids(api: str) -> set[str]:
    """The set of song ids that already have published lyrics (for skip-synced)."""
    try:
        data = json.loads(http_get(f"{api.rstrip('/')}/api/lyrics"))
        return {str(i) for i in (data.get("ids") or [])}
    except Exception:
        return set()


def api_publish(api: str, key: str | None, document: dict) -> tuple[bool, str]:
    headers = {"Content-Type": "application/json", "User-Agent": "LyricStudio/1.0"}
    if key:
        headers["x-masters-key"] = key
    req = urllib.request.Request(
        api.rstrip("/") + "/api/lyrics",
        data=json.dumps(document).encode("utf-8"),
        headers=headers,
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            payload = json.loads(r.read().decode("utf-8"))
            return bool(payload.get("ok")), str(payload.get("storage", ""))
    except urllib.error.HTTPError as exc:
        try:
            detail = json.loads(exc.read().decode("utf-8")).get("error", "")
        except Exception:
            detail = ""
        return False, f"HTTP {exc.code} {detail}".strip()
    except Exception as exc:
        return False, str(exc)


def api_delete_lyrics(api: str, key: str | None, sound_id: int) -> tuple[bool, str]:
    headers = {"User-Agent": "LyricStudio/1.0"}
    if key:
        headers["x-masters-key"] = key
    req = urllib.request.Request(
        f"{api.rstrip('/')}/api/lyrics?songId={sound_id}",
        headers=headers,
        method="DELETE",
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            payload = json.loads(r.read().decode("utf-8"))
            return bool(payload.get("ok")), ""
    except urllib.error.HTTPError as exc:
        try:
            detail = json.loads(exc.read().decode("utf-8")).get("error", "")
        except Exception:
            detail = ""
        return False, f"HTTP {exc.code} {detail}".strip()
    except Exception as exc:
        return False, str(exc)


# ----------------------------------------------------------------- toasts


try:
    import winsound

    def _notify_sound():
        winsound.MessageBeep(winsound.MB_ICONASTERISK)
except ImportError:  # non-Windows
    def _notify_sound():
        pass


class Toast(tk.Frame):
    """A Masters-style banner that slides in from the top of the window."""

    WIDTH = 380

    def __init__(self, app, header: str, description: str, error: bool = False):
        super().__init__(app, bg="#1c1c1c", highlightthickness=1,
                         highlightbackground="#e5484d" if error else "#3a3a3a")
        self.app = app
        tk.Label(self, text=header, bg="#1c1c1c", fg=FG,
                 font=("Segoe UI", 10, "bold"), anchor="w",
                 wraplength=self.WIDTH - 30, justify="left").pack(
            fill="x", padx=14, pady=(10, 0))
        tk.Label(self, text=description, bg="#1c1c1c", fg=FG2,
                 font=("Segoe UI", 9), anchor="w",
                 wraplength=self.WIDTH - 30, justify="left").pack(
            fill="x", padx=14, pady=(2, 10))
        self.bind("<Button-1>", lambda _e: self.dismiss())
        for child in self.winfo_children():
            child.bind("<Button-1>", lambda _e: self.dismiss())

        self.offset = -120.0
        self.target = 0.0
        self.dismissed = False
        self._slide()
        self.after(7000 if error else 4500, self.dismiss)

    def _y(self) -> int:
        base = 12
        for toast in self.app._toasts:
            if toast is self:
                break
            if toast.winfo_exists():
                base += toast.winfo_reqheight() + 8
        return base

    def _slide(self):
        if not self.winfo_exists():
            return
        self.target = -130 if self.dismissed else self._y()
        self.offset += (self.target - self.offset) * 0.25
        if self.dismissed and self.offset < -110:
            if self in self.app._toasts:
                self.app._toasts.remove(self)
            self.destroy()
            return
        self.place(relx=0.5, y=int(self.offset), anchor="n", width=self.WIDTH)
        self.lift()
        self.after(16, self._slide)

    def dismiss(self):
        self.dismissed = True


# ------------------------------------------------------------------- app


class LyricStudio(tk.Tk):
    def __init__(self):
        super().__init__()
        self.title("Lyric Studio")
        self.configure(bg=BG)
        self.geometry("1180x680")
        self.minsize(940, 560)

        cfg = load_config()
        self.api_url = (cfg.get("api_url") or "").rstrip("/")
        self.publish_key = cfg.get("publish_key") or None
        # the "Synced By" name: lyricsync's saved username (--user NAME --save)
        self.username = cfg.get("username") or "You"

        self.sound_id: int | None = None
        self.audio_path: Path | None = None
        self.doc: dict = {"SoundId": 0, "Unsynced": False, "Lyrics": []}
        self.cover_img = None
        self.cover_blob: bytes | None = None
        self.preview_win = None
        self._toasts: list[Toast] = []
        self.sound_on = True

        self._build_ui()
        self._log(f"api: {self.api_url or '(none - publish disabled)'}")
        self._log(f"audio preview: {'ready' if AUDIO_OK else 'pygame missing - pip install pygame'}")

    # ---------------------------------------------------------- layout

    def _build_ui(self):
        style = ttk.Style(self)
        style.theme_use("clam")
        style.configure("Treeview", background=BG2, fieldbackground=BG2,
                        foreground=FG, rowheight=24, borderwidth=0)
        style.configure("Treeview.Heading", background=BG3, foreground=FG2, borderwidth=0)
        style.map("Treeview", background=[("selected", HILIGHT)])

        # menu bar
        menubar = tk.Menu(self)
        tools = tk.Menu(menubar, tearoff=0)
        tools.add_command(label="Bulk Sync…", command=self.on_bulk_sync)
        tools.add_command(label="Sync All by Artist…", command=self.on_artist_sync)
        menubar.add_cascade(label="Tools", menu=tools)
        try:
            self.config(menu=menubar)
        except tk.TclError:
            pass

        # top toolbar
        bar = tk.Frame(self, bg=BG2)
        bar.pack(fill="x")
        tk.Label(bar, text="Music id:", bg=BG2, fg=FG2).pack(side="left", padx=(12, 4), pady=10)
        self.id_entry = tk.Entry(bar, width=20, bg=BG3, fg=FG, insertbackground=FG,
                                 relief="flat")
        self.id_entry.pack(side="left", ipady=4)
        self._info_job = None
        self._info_fetched_for = None
        self.id_entry.bind("<KeyRelease>", self._schedule_info_fetch)

        def btn(text, cmd):
            b = tk.Button(bar, text=text, command=cmd, bg=BG3, fg=FG,
                          activebackground=HILIGHT, activeforeground=FG,
                          relief="flat", padx=12, pady=4, cursor="hand2")
            b.pack(side="left", padx=4)
            return b

        btn("Download", self.on_download)
        btn("Load Audio...", self.on_load_audio)
        btn("Fetch Published", self.on_fetch_published)
        btn("Auto-Sync (whisper)", self.on_autosync)
        btn("Publish", self.on_publish)
        btn("Test Fetch", self.on_test_fetch)
        btn("Remove Published", self.on_remove_published)
        self.preview_btn = btn("▶ Preview", self.on_preview)
        btn("Add to macOS", self.on_add_to_macos)
        btn("Discord Post", self.on_discord_post)
        btn("Bulk Sync", self.on_bulk_sync)
        self.sound_btn = btn("🔔", self.on_toggle_sound)

        self._build_main_area()

    def on_bulk_sync(self):
        BulkSyncWindow(self)

    def on_artist_sync(self):
        ArtistSyncWindow(self)

    def on_toggle_sound(self):
        self.sound_on = not self.sound_on
        self.sound_btn.configure(text="🔔" if self.sound_on else "🔕")
        self.notify("Notification sound " + ("on" if self.sound_on else "off"),
                    "Toasts will " + ("ding" if self.sound_on else "stay quiet") +
                    " when they appear.", silent=not self.sound_on)

    def notify(self, header: str, description: str = "", error: bool = False,
               silent: bool = False):
        """Masters-style toast sliding in from the top (thread-safe)."""
        def show():
            toast = Toast(self, header, description, error=error)
            self._toasts.append(toast)
            if self.sound_on and not silent:
                _notify_sound()
        self.after(0, show)

    def _build_main_area(self):
        body = tk.Frame(self, bg=BG)
        body.pack(fill="both", expand=True)

        # left: contents (cover / title / artist / log)
        left = tk.Frame(body, bg=BG, width=320)
        left.pack(side="left", fill="y", padx=16, pady=16)
        left.pack_propagate(False)

        self.cover_label = tk.Label(left, bg=BG2, width=280, height=280)
        self.cover_label.pack()
        self.title_label = tk.Label(left, text="No song loaded", bg=BG, fg=FG,
                                    font=("Segoe UI", 14, "bold"), wraplength=290,
                                    justify="left", anchor="w")
        self.title_label.pack(fill="x", pady=(12, 0))
        self.artist_label = tk.Label(left, text="Put in a music id and press Download",
                                     bg=BG, fg=FG2, font=("Segoe UI", 11),
                                     wraplength=290, justify="left", anchor="w")
        self.artist_label.pack(fill="x")

        tk.Label(left, text="Log", bg=BG, fg=FG2, anchor="w").pack(fill="x", pady=(14, 2))
        self.log_box = tk.Text(left, bg=BG2, fg=FG2, height=10, relief="flat",
                               font=("Consolas", 9), state="disabled", wrap="word")
        self.log_box.pack(fill="both", expand=True)

        # right: lyrics editor
        right = tk.Frame(body, bg=BG)
        right.pack(side="left", fill="both", expand=True, padx=(0, 16), pady=16)

        self.tree = ttk.Treeview(right, columns=("start", "end", "line"),
                                 show="headings", selectmode="browse")
        self.tree.heading("start", text="Start")
        self.tree.heading("end", text="End")
        self.tree.heading("line", text="Line")
        self.tree.column("start", width=70, anchor="e", stretch=False)
        self.tree.column("end", width=70, anchor="e", stretch=False)
        self.tree.column("line", width=480)
        self.tree.pack(fill="both", expand=True)
        self.tree.bind("<<TreeviewSelect>>", self.on_select_row)
        self._editing_index = None  # which row the edit fields were loaded from

        edit = tk.Frame(right, bg=BG)
        edit.pack(fill="x", pady=(8, 0))
        tk.Label(edit, text="Start", bg=BG, fg=FG2).grid(row=0, column=0, padx=(0, 4))
        self.start_var = tk.StringVar()
        tk.Entry(edit, textvariable=self.start_var, width=9, bg=BG3, fg=FG,
                 insertbackground=FG, relief="flat").grid(row=0, column=1, ipady=3)
        tk.Label(edit, text="End", bg=BG, fg=FG2).grid(row=0, column=2, padx=4)
        self.end_var = tk.StringVar()
        tk.Entry(edit, textvariable=self.end_var, width=9, bg=BG3, fg=FG,
                 insertbackground=FG, relief="flat").grid(row=0, column=3, ipady=3)
        tk.Label(edit, text="Line", bg=BG, fg=FG2).grid(row=0, column=4, padx=4)
        self.line_var = tk.StringVar()
        tk.Entry(edit, textvariable=self.line_var, bg=BG3, fg=FG,
                 insertbackground=FG, relief="flat").grid(row=0, column=5, sticky="ew", ipady=3)
        edit.columnconfigure(5, weight=1)
        for widget in edit.winfo_children():
            if isinstance(widget, tk.Entry):
                widget.bind("<Return>", lambda _e: self.on_apply_row())

        def ebtn(parent, text, cmd):
            b = tk.Button(parent, text=text, command=cmd, bg=BG3, fg=FG,
                          activebackground=HILIGHT, activeforeground=FG,
                          relief="flat", padx=10, pady=3, cursor="hand2")
            b.pack(side="left", padx=3)
            return b

        tools = tk.Frame(right, bg=BG)
        tools.pack(fill="x", pady=(8, 0))
        ebtn(tools, "Apply", self.on_apply_row)
        ebtn(tools, "+ Add Line", self.on_add_row)
        ebtn(tools, "Delete", self.on_delete_row)
        ebtn(tools, "-0.1s", lambda: self.on_nudge(-0.1))
        ebtn(tools, "+0.1s", lambda: self.on_nudge(0.1))
        tk.Label(tools, text="   Offset all:", bg=BG, fg=FG2).pack(side="left")
        self.offset_var = tk.StringVar(value="0.0")
        tk.Entry(tools, textvariable=self.offset_var, width=7, bg=BG3, fg=FG,
                 insertbackground=FG, relief="flat").pack(side="left", padx=3, ipady=3)
        ebtn(tools, "Shift", self.on_offset_all)
        ebtn(tools, "Save songs/ copy", self.on_save_local)

    # ------------------------------------------------------------- util

    def _log(self, text: str):
        def write():
            box = getattr(self, "log_box", None)
            if box is None or not box.winfo_exists():
                return
            self.log_box.configure(state="normal")
            self.log_box.insert("end", text.rstrip() + "\n")
            self.log_box.see("end")
            self.log_box.configure(state="disabled")
        self.after(0, write)

    def _bg(self, fn):
        threading.Thread(target=fn, daemon=True).start()

    def _refresh_tree(self):
        # after any rebuild the edit fields are no longer bound to a row, so a
        # later auto-commit can never write stale values into the wrong line
        self._editing_index = None
        self.tree.delete(*self.tree.get_children())
        for index, entry in enumerate(self.doc["Lyrics"]):
            self.tree.insert("", "end", iid=str(index), values=(
                f"{entry['TimeStart']:.2f}", f"{entry['TimeEnd']:.2f}", entry["Line"]))

    def _selected_index(self) -> int | None:
        selection = self.tree.selection()
        return int(selection[0]) if selection else None

    def _set_cover(self, blob: bytes | None):
        self.cover_blob = blob  # (Add to macOS saves it as the song's cover)

        def apply():
            if blob:
                try:
                    img = tk.PhotoImage(data=blob)
                    factor = max(1, img.width() // 280)
                    if factor > 1:
                        img = img.subsample(factor, factor)
                    self.cover_img = img
                    self.cover_label.configure(image=img, text="")
                    return
                except Exception:
                    pass
            self.cover_img = None
            self.cover_label.configure(image="", text="♪", fg=FG2,
                                       font=("Segoe UI", 60))
        self.after(0, apply)

    # ---------------------------------------------------------- actions

    def _fetch_info(self, sound_id: int):
        """Title/artist/cover for the id (runs in a background thread)."""
        self._log(f"fetching info for {sound_id}...")
        details = fetch_details(sound_id)
        title = details["title"] or f"Sound {sound_id}"
        self.after(0, lambda: (self.title_label.configure(text=title),
                               self.artist_label.configure(text=details["artist"] or "Unknown")))
        self._set_cover(fetch_thumbnail(sound_id))
        return title

    def _schedule_info_fetch(self, _event=None):
        """Auto-fetch song info one second after the user stops typing."""
        if self._info_job:
            self.after_cancel(self._info_job)
        self._info_job = self.after(1000, self._auto_info_fetch)

    def _auto_info_fetch(self):
        self._info_job = None
        try:
            sound_id = parse_sound_id(self.id_entry.get())
        except ValueError:
            return
        if sound_id == self._info_fetched_for:
            return
        self._info_fetched_for = sound_id
        self._bg(lambda: self._fetch_info(sound_id))

    def on_download(self):
        try:
            sound_id = parse_sound_id(self.id_entry.get())
        except ValueError as exc:
            self.notify("Invalid music id", str(exc), error=True)
            return

        def work():
            self.sound_id = sound_id
            self.doc["SoundId"] = sound_id
            self._info_fetched_for = sound_id
            title = self._fetch_info(sound_id)
            try:
                self.audio_path = download_audio(sound_id)
                size_mb = self.audio_path.stat().st_size / 1_000_000
                self._log(f"audio -> {self.audio_path.name} ({size_mb:.1f} MB)")
                self.notify("Audio downloaded",
                            f"{title} · {self.audio_path.name} ({size_mb:.1f} MB) - "
                            "ready for Auto-Sync or Preview.")
            except RuntimeError as exc:
                self.audio_path = None
                self._log(f"! {exc}")
                self.notify("Download failed", str(exc), error=True)

        self._bg(work)

    def on_load_audio(self):
        path = filedialog.askopenfilename(
            filetypes=[("Audio", "*.mp3 *.ogg *.wav *.flac *.m4a"), ("All files", "*.*")])
        if path:
            self.audio_path = Path(path)
            self._log(f"audio -> {self.audio_path.name}")
            if self.sound_id is None:
                try:
                    self.sound_id = parse_sound_id(self.id_entry.get())
                    self.doc["SoundId"] = self.sound_id
                except ValueError:
                    self._log("! set the music id too, publishing needs it")

    def on_fetch_published(self):
        try:
            sound_id = parse_sound_id(self.id_entry.get())
        except ValueError as exc:
            self.notify("Invalid music id", str(exc), error=True)
            return
        if not self.api_url:
            self.notify("No API configured",
                        "Put your api_url in ~/.lyricsync/config.json", error=True)
            return

        def work():
            self._log(f"fetching published lyrics for {sound_id}...")
            doc = api_fetch_lyrics(self.api_url, sound_id)
            if not doc or not doc.get("Lyrics"):
                self._log("nothing published for this song yet")
                return
            self.sound_id = sound_id
            self.doc = {"SoundId": sound_id, "Unsynced": bool(doc.get("Unsynced")),
                        "Lyrics": doc["Lyrics"]}
            self.after(0, self._refresh_tree)
            self._log(f"loaded {len(doc['Lyrics'])} published lines - edit away")

        self._bg(work)

    def on_autosync(self):
        if not self.audio_path:
            self.notify("No audio yet", "Download or load the audio first", error=True)
            return
        if not self.sound_id:
            self.notify("No music id", "Set the music id first", error=True)
            return

        def work():
            out = HERE / "downloads" / f"{self.sound_id}.sync.json"
            cmd = [sys.executable, "-m", "lyricsync", "sync", str(self.audio_path),
                   "--id", str(self.sound_id), "--user", self.username,
                   "-o", str(out), "--format", "json"]
            self._log("running whisper... (this can take a while)")
            proc = subprocess.Popen(cmd, cwd=HERE, stdout=subprocess.PIPE,
                                    stderr=subprocess.STDOUT, text=True,
                                    encoding="utf-8", errors="replace")
            for line in proc.stdout:
                if line.strip():
                    self._log("  " + line.strip())
            proc.wait()
            if proc.returncode != 0 or not out.exists():
                self._log(f"! lyricsync failed (exit {proc.returncode})")
                self.notify("Auto-Sync failed",
                            f"lyricsync exited with code {proc.returncode} - "
                            "check the log for details.", error=True)
                return
            self.doc = json.loads(out.read_text(encoding="utf-8"))
            count = len(self.doc["Lyrics"])
            self.after(0, self._refresh_tree)
            self._log(f"synced {count} lines")
            self.notify("Lyrics synced",
                        f"Whisper synced {count} lines - check the timing in "
                        "Preview, then hit Publish.")

        self._bg(work)

    def on_publish(self):
        self._commit_fields()
        if not self.doc["Lyrics"]:
            self.notify("Nothing to publish", "Load or sync lyrics first", error=True)
            return
        if not self.api_url:
            self.notify("No API configured",
                        "Put your api_url in ~/.lyricsync/config.json", error=True)
            return

        def work():
            ok, note = api_publish(self.api_url, self.publish_key, self.doc)
            self._log(f"publish: {'ok (' + note + ')' if ok else 'FAILED - ' + note}")
            if ok:
                self._log("every Masters player picks this up within ~20s")
                count = len(self.doc["Lyrics"])
                self.notify("Published!",
                            f"{count} lines stored on the API ({note}). Every "
                            "Masters player picks this up within ~20 seconds.")
            else:
                self.notify("Publish failed", note, error=True)

        self._bg(work)

    def on_remove_published(self):
        """Delete this song's published lyrics from the API (for bad syncs)."""
        try:
            sound_id = parse_sound_id(self.id_entry.get())
        except ValueError as exc:
            self.notify("Invalid music id", str(exc), error=True)
            return
        if not self.api_url:
            self.notify("No API configured",
                        "Put your api_url in ~/.lyricsync/config.json", error=True)
            return
        from tkinter import messagebox
        title = self.title_label.cget("text") or str(sound_id)
        if not messagebox.askyesno(
                "Remove published lyrics",
                f"Delete the published lyrics for\n\n{title} ({sound_id})\n\n"
                "from the API? Every Masters player stops seeing them "
                "within ~20 seconds.", parent=self):
            return

        def work():
            self._log(f"removing published lyrics for {sound_id}...")
            ok, note = api_delete_lyrics(self.api_url, self.publish_key, sound_id)
            if ok:
                self._log(f"removed {sound_id} from the API")
                self.notify("Lyrics removed",
                            f"{sound_id} is gone from the published index. "
                            "Players drop it within ~20 seconds.")
            else:
                self._log(f"remove FAILED - {note}")
                self.notify("Remove failed", note, error=True)

        self._bg(work)

    def on_test_fetch(self):
        """Ask the API for this song's lyrics, exactly like a player would."""
        try:
            sound_id = parse_sound_id(self.id_entry.get())
        except ValueError as exc:
            self.notify("Invalid music id", str(exc), error=True)
            return
        if not self.api_url:
            self.notify("No API configured",
                        "Put your api_url in ~/.lyricsync/config.json", error=True)
            return

        def work():
            self._log(f"test-fetching {sound_id} from the API...")
            doc = api_fetch_lyrics(self.api_url, sound_id)
            if doc and doc.get("Lyrics"):
                count = len(doc["Lyrics"])
                first = next((e["Line"] for e in doc["Lyrics"] if e.get("Line")), "")
                self._log(f"API serves {count} lines for {sound_id}")
                self.notify("Test fetch OK",
                            f"The API serves {count} lines for {sound_id}. "
                            f"First line: “{first}” - this is exactly what "
                            "players receive.")
            else:
                self._log(f"API has nothing for {sound_id}")
                self.notify("Nothing published",
                            f"No published lyrics for {sound_id} on the API yet.",
                            error=True)

        self._bg(work)

    def on_save_local(self):
        self._commit_fields()
        if not self.doc["Lyrics"] or not self.sound_id:
            return
        slug = re.sub(r"[^a-z0-9]+", "-",
                      (self.title_label.cget("text") or str(self.sound_id)).lower()).strip("-") \
            or str(self.sound_id)
        folder = HERE / "songs" / slug
        folder.mkdir(parents=True, exist_ok=True)
        (folder / f"{slug}.json").write_text(json.dumps(self.doc), encoding="utf-8")
        self._log(f"saved -> songs/{slug}/{slug}.json")

    # ------------------------------------------------------ row editing

    def _commit_fields(self) -> bool:
        """Push whatever is typed in the edit fields into the row they were
        loaded from, so edits stick without needing the Apply button.
        Returns True when the document changed."""
        index = getattr(self, "_editing_index", None)
        if index is None or index >= len(self.doc["Lyrics"]):
            return False
        entry = self.doc["Lyrics"][index]
        try:
            start = float(self.start_var.get())
            end = float(self.end_var.get())
        except ValueError:
            # keep the old timings but still save the text edit
            start, end = entry["TimeStart"], entry["TimeEnd"]
        line = self.line_var.get()
        if (abs(start - entry["TimeStart"]) < 1e-9
                and abs(end - entry["TimeEnd"]) < 1e-9
                and line == entry["Line"]):
            return False
        entry["TimeStart"] = start
        entry["TimeEnd"] = end
        entry["Line"] = line
        if self.tree.exists(str(index)):
            self.tree.item(str(index), values=(f"{start:.2f}", f"{end:.2f}", line))
        return True

    def on_select_row(self, _event=None):
        index = self._selected_index()
        if index is None:
            return
        self._commit_fields()
        self._editing_index = index
        entry = self.doc["Lyrics"][index]
        self.start_var.set(f"{entry['TimeStart']:.3f}")
        self.end_var.set(f"{entry['TimeEnd']:.3f}")
        self.line_var.set(entry["Line"])

    def on_apply_row(self):
        index = self._selected_index()
        if index is None:
            return
        try:
            entry = self.doc["Lyrics"][index]
            entry["TimeStart"] = float(self.start_var.get())
            entry["TimeEnd"] = float(self.end_var.get())
            entry["Line"] = self.line_var.get()
        except ValueError:
            self.notify("Bad timing", "Start/End must be numbers", error=True)
            return
        self._refresh_tree()
        self.tree.selection_set(str(index))

    def on_add_row(self):
        self._commit_fields()
        index = self._selected_index()
        at = index + 1 if index is not None else len(self.doc["Lyrics"])
        prev_end = self.doc["Lyrics"][index]["TimeEnd"] if index is not None else 0.0
        self.doc["Lyrics"].insert(at, {"RightAligned": False, "Line": "new line",
                                       "Id": "L0", "TimeStart": prev_end,
                                       "TimeEnd": prev_end + 3.0, "Adlibs": []})
        self._renumber()
        self._refresh_tree()
        self.tree.selection_set(str(at))

    def on_delete_row(self):
        index = self._selected_index()
        if index is None:
            return
        del self.doc["Lyrics"][index]
        self._renumber()
        self._refresh_tree()

    def on_nudge(self, amount: float):
        index = self._selected_index()
        if index is None:
            return
        self._commit_fields()
        entry = self.doc["Lyrics"][index]
        entry["TimeStart"] = max(0.0, entry["TimeStart"] + amount)
        entry["TimeEnd"] = max(entry["TimeStart"], entry["TimeEnd"] + amount)
        self._refresh_tree()
        self.tree.selection_set(str(index))
        self.on_select_row()

    def on_offset_all(self):
        try:
            amount = float(self.offset_var.get())
        except ValueError:
            return
        self._commit_fields()
        for entry in self.doc["Lyrics"]:
            entry["TimeStart"] = max(0.0, entry["TimeStart"] + amount)
            entry["TimeEnd"] = max(entry["TimeStart"], entry["TimeEnd"] + amount)
        self._refresh_tree()

    def _renumber(self):
        lyric_number = 0
        for slot, entry in enumerate(self.doc["Lyrics"], start=1):
            if entry["Id"] == "CERTIFICATION":
                continue
            if entry["Line"] == "":
                entry["Id"] = f"GAP_{slot}"
            else:
                lyric_number += 1
                entry["Id"] = f"L{lyric_number}"

    # ---------------------------------------------------- discord post

    def on_discord_post(self):
        self._commit_fields()
        if not self.doc["Lyrics"]:
            self.notify("Nothing to post", "Load or sync lyrics first", error=True)
            return
        DiscordPostWindow(self)

    # ------------------------------------------------- add to macOS Music

    def on_add_to_macos(self):
        self._commit_fields()
        if not self.audio_path or not self.audio_path.exists():
            self.notify("No audio yet", "Download or load the song's audio first", error=True)
            return
        AddToMacOSWindow(self)

    # --------------------------------------------------------- preview

    def on_preview(self):
        self._commit_fields()
        if not self.doc["Lyrics"]:
            self.notify("Nothing to preview", "Load or sync lyrics first", error=True)
            return
        if self.preview_win and self.preview_win.winfo_exists():
            self.preview_win.destroy()
        self.preview_win = PreviewWindow(self)


class AddToMacOSWindow(tk.Toplevel):
    """Puts the loaded song, its synced lyrics and its cover into macOS in
    Roblox Music on this PC (coolui_music in the executor's workspace). Music
    shows it within a few seconds."""

    def __init__(self, app: LyricStudio):
        super().__init__(app)
        from lyricsync import config as lyricsync_config, macos as macos_library

        self.app = app
        self.config_module = lyricsync_config
        self.library = macos_library
        self.title("Add to macOS Music")
        self.configure(bg=BG)
        self.resizable(False, False)
        self.transient(app)
        saved = lyricsync_config.load()
        self.root = macos_library.pc_music()

        def label(text, row):
            tk.Label(self, text=text, bg=BG, fg=FG2, anchor="w").grid(row=row, column=0, sticky="w",
                                                                    padx=(18, 10), pady=6)

        def entry(var, row):
            widget = tk.Entry(self, textvariable=var, width=42, bg=BG3, fg=FG, insertbackground=FG, relief="flat")
            widget.grid(row=row, column=1, sticky="ew", padx=(0, 18), pady=6, ipady=4)
            return widget

        tk.Label(self, text="Add to macOS Music", bg=BG, fg=FG, font=("Segoe UI", 14, "bold"),
                 anchor="w").grid(row=0, column=0, columnspan=2, sticky="w", padx=18, pady=(16, 2))
        lines = sum(1 for e in app.doc.get("Lyrics") or [] if e.get("Line"))
        tk.Label(self, text=(f"{app.audio_path.name} · {lines} lyric lines" if lines
                             else f"{app.audio_path.name} · no lyrics yet (Auto-Sync first to include them)"),
                 bg=BG, fg=FG2, anchor="w").grid(row=1, column=0, columnspan=2, sticky="w", padx=18, pady=(0, 10))

        label("Category", 2)
        self.category_var = tk.StringVar(value=saved.get("macos_category") or "")
        combo = ttk.Combobox(self, textvariable=self.category_var, values=macos_library.categories(self.root), width=40)
        combo.grid(row=2, column=1, sticky="ew", padx=(0, 18), pady=6, ipady=2)
        tk.Label(self, text="pick one, or type a new name (lofi/chill puts it inside lofi)",
                 bg=BG, fg=FG2, font=("Segoe UI", 8), anchor="w").grid(row=3, column=1, sticky="w", padx=(0, 18))

        title = app.title_label.cget("text")
        artist = app.artist_label.cget("text")
        label("Title", 4)
        self.title_var = tk.StringVar(value="" if title in ("No song loaded",) or title.startswith("Sound ") else title)
        entry(self.title_var, 4)
        label("Artist", 5)
        self.artist_var = tk.StringVar(value="" if artist in ("Unknown", "Put in a music id and press Download") else artist)
        entry(self.artist_var, 5)

        self.cover_var = tk.BooleanVar(value=app.cover_blob is not None)
        tk.Checkbutton(self, text="Use the Roblox thumbnail as its cover", variable=self.cover_var,
                       bg=BG, fg=FG, selectcolor=BG3, activebackground=BG, activeforeground=FG, anchor="w",
                       state="normal" if app.cover_blob else "disabled").grid(row=6, column=1, sticky="w", pady=4)

        # Where it goes: always this PC
        where = (f"Goes to this PC's Music: {self.root}" if self.root
                 else "Real's workspace wasn't found. For another executor, run "
                      "python -m lyricsync macos --workspace PATH once.")
        tk.Label(self, text=where, bg=BG, fg=FG2, font=("Segoe UI", 8), anchor="w", wraplength=460,
                 justify="left").grid(row=7, column=0, columnspan=2, sticky="w", padx=18, pady=(6, 0))

        buttons = tk.Frame(self, bg=BG)
        buttons.grid(row=8, column=0, columnspan=2, sticky="e", padx=18, pady=(10, 16))
        for text, command in (("Cancel", self.destroy), ("Add", self.on_add)):
            tk.Button(buttons, text=text, command=command, bg=BG3 if text == "Cancel" else "#0a84ff", fg=FG,
                      activebackground=HILIGHT, activeforeground=FG, relief="flat", padx=16, pady=4,
                      cursor="hand2", state="normal" if self.root or text == "Cancel" else "disabled"
                      ).pack(side="left", padx=(8, 0))
        self.columnconfigure(1, weight=1)
        combo.focus_set()

    def on_add(self):
        category = self.category_var.get().strip()
        if not category:
            self.app.notify("Pick a category", "Choose one from the list or type a new name", error=True)
            return
        app = self.app
        doc = app.doc if any(e.get("Line") for e in app.doc.get("Lyrics") or []) else None
        details = dict(
            title=self.title_var.get().strip() or app.audio_path.stem,
            artist=self.artist_var.get().strip(),
            cover=app.cover_blob if self.cover_var.get() else None,
            sound_id=app.sound_id,
        )
        self.config_module.save(macos_category=category)
        self.destroy()

        def work():
            try:
                added = self.library.add(category, app.audio_path, doc, **details)
            except Exception as exc:  # noqa: BLE001 - shown to the user
                app._log(f"! add to macOS failed: {exc}")
                app.notify("Couldn't add it to macOS", str(exc), error=True)
                return
            app._log(f"macOS Music -> {added['folder']}")
            app.notify("Added to macOS Music",
                       f"“{details['title']}” is in {category}"
                       + (" with its lyrics." if doc else " (no lyrics).")
                       + " Music shows it within a few seconds.")

        app._bg(work)


class PreviewWindow(tk.Toplevel):
    """A Masters-style now-playing window: contents on the left, lyrics right."""

    def __init__(self, app: LyricStudio):
        super().__init__(app)
        self.app = app
        self.title("Masters Preview")
        self.configure(bg=BG)
        self.geometry("900x560")
        self.playing = False
        self.position = 0.0
        self._clock_anchor = None
        self._active_index = None
        self.duration = max((e["TimeEnd"] for e in app.doc["Lyrics"]), default=0.0)

        left = tk.Frame(self, bg=BG, width=340)
        left.pack(side="left", fill="y", padx=24, pady=24)
        left.pack_propagate(False)

        cover = tk.Label(left, bg=BG2, width=280, height=280)
        if app.cover_img is not None:
            cover.configure(image=app.cover_img)
        else:
            cover.configure(text="♪", fg=FG2, font=("Segoe UI", 60))
        cover.pack()
        tk.Label(left, text=app.title_label.cget("text"), bg=BG, fg=FG,
                 font=("Segoe UI", 15, "bold"), wraplength=300, justify="left",
                 anchor="w").pack(fill="x", pady=(14, 0))
        tk.Label(left, text=app.artist_label.cget("text"), bg=BG, fg=FG2,
                 font=("Segoe UI", 11), anchor="w").pack(fill="x")

        self.seek = ttk.Scale(left, from_=0, to=max(1.0, self.duration),
                              orient="horizontal", command=self.on_seek)
        self.seek.pack(fill="x", pady=(18, 2))
        clockrow = tk.Frame(left, bg=BG)
        clockrow.pack(fill="x")
        self.clock_label = tk.Label(clockrow, text="0:00", bg=BG, fg=FG2)
        self.clock_label.pack(side="left")
        tk.Label(clockrow, text=self._fmt(self.duration), bg=BG, fg=FG2).pack(side="right")

        self.play_btn = tk.Button(left, text="▶", command=self.toggle,
                                  bg=BG3, fg=FG, activebackground=HILIGHT,
                                  activeforeground=FG, relief="flat",
                                  font=("Segoe UI", 16), width=4, cursor="hand2")
        self.play_btn.pack(pady=14)
        if not (AUDIO_OK and app.audio_path):
            note = "no audio loaded" if AUDIO_OK else "pip install pygame for audio"
            tk.Label(left, text=f"(timeline-only preview - {note})",
                     bg=BG, fg=FG2, font=("Segoe UI", 8)).pack()

        # right: the lyrics
        self.canvas = tk.Text(self, bg=BG, fg=FG2, relief="flat", wrap="word",
                              font=("Segoe UI", 16, "bold"), spacing3=14,
                              cursor="hand2", padx=24, pady=24)
        self.canvas.pack(side="left", fill="both", expand=True)
        self.canvas.tag_configure("current", foreground=FG)
        self.canvas.tag_configure("gap", foreground=BG3)
        self.canvas.tag_configure("cert", font=("Segoe UI", 10), foreground=FG2)
        self.line_marks = []
        for index, entry in enumerate(self.app.doc["Lyrics"]):
            tag = f"line{index}"
            text = entry["Line"] if entry["Line"] else "• • •"
            extra = ("cert",) if entry["Id"] == "CERTIFICATION" else \
                (("gap",) if not entry["Line"] else ())
            self.canvas.insert("end", text + "\n", (tag,) + extra)
            self.canvas.tag_bind(tag, "<Button-1>",
                                 lambda _e, i=index: self.jump_to(i))
            self.line_marks.append(tag)
        self.canvas.configure(state="disabled")

        if AUDIO_OK and app.audio_path:
            try:
                pygame.mixer.music.load(str(app.audio_path))
            except Exception as exc:
                self.app._log(f"! preview audio failed: {exc}")

        self.protocol("WM_DELETE_WINDOW", self.close)
        self.tick()

    @staticmethod
    def _fmt(seconds: float) -> str:
        minutes, secs = divmod(int(max(0, seconds)), 60)
        return f"{minutes}:{secs:02d}"

    def current_position(self) -> float:
        if self.playing and self._clock_anchor is not None:
            return time.monotonic() - self._clock_anchor
        return self.position

    def toggle(self):
        if self.playing:
            self.position = self.current_position()
            self.playing = False
            self.play_btn.configure(text="▶")
            if AUDIO_OK and self.app.audio_path:
                pygame.mixer.music.stop()
        else:
            self._clock_anchor = time.monotonic() - self.position
            self.playing = True
            self.play_btn.configure(text="⏸")
            if AUDIO_OK and self.app.audio_path:
                try:
                    pygame.mixer.music.play(start=self.position)
                except Exception:
                    pygame.mixer.music.play()

    def on_seek(self, value):
        try:
            target = float(value)
        except ValueError:
            return
        if abs(target - self.current_position()) < 0.5:
            return
        self.position = target
        if self.playing:
            self._clock_anchor = time.monotonic() - target
            if AUDIO_OK and self.app.audio_path:
                try:
                    pygame.mixer.music.play(start=target)
                except Exception:
                    pass

    def jump_to(self, index: int):
        self.position = self.app.doc["Lyrics"][index]["TimeStart"]
        if self.playing:
            self._clock_anchor = time.monotonic() - self.position
            if AUDIO_OK and self.app.audio_path:
                try:
                    pygame.mixer.music.play(start=self.position)
                except Exception:
                    pass

    def tick(self):
        if not self.winfo_exists():
            return
        pos = self.current_position()
        if self.playing and self.duration and pos >= self.duration:
            self.toggle()
            pos = self.duration
        self.seek.set(pos)
        self.clock_label.configure(text=self._fmt(pos))
        self.canvas.configure(state="normal")
        active_index = None
        for index, entry in enumerate(self.app.doc["Lyrics"]):
            tag = self.line_marks[index]
            active = entry["TimeStart"] <= pos <= entry["TimeEnd"]
            if active:
                active_index = index
                self.canvas.tag_add("current", f"{tag}.first", f"{tag}.last")
            else:
                self.canvas.tag_remove("current", f"{tag}.first", f"{tag}.last")
        self.canvas.configure(state="disabled")
        if active_index is not None and active_index != self._active_index:
            self._active_index = active_index
            self._center_line(self.line_marks[active_index])
        self.after(120, self.tick)

    def _center_line(self, tag: str):
        """Scroll so the current lyric sits in the middle, Masters-style."""
        try:
            def pixels(value):
                return value[0] if isinstance(value, tuple) else (value or 0)
            total = pixels(self.canvas.count("1.0", "end", "ypixels"))
            line = pixels(self.canvas.count("1.0", f"{tag}.first", "ypixels"))
            height = self.canvas.winfo_height()
            fraction = max(0.0, line - height / 2 + 24) / max(1, total)
            self.canvas.yview_moveto(min(1.0, fraction))
        except Exception:
            self.canvas.see(f"{tag}.first")

    def close(self):
        if AUDIO_OK:
            try:
                pygame.mixer.music.stop()
            except Exception:
                pass
        self.destroy()


class BulkSyncWindow(tk.Toplevel):
    """Queue up to 10 music ids and sync (and optionally publish) them all."""

    MAX_BATCH = 10

    def __init__(self, app: LyricStudio):
        super().__init__(app)
        self.app = app
        self.title("Bulk Sync")
        self.configure(bg=BG)
        self.geometry("720x600")
        self.running = False
        self.stop_requested = False

        tk.Label(self, text=f"Paste up to {self.MAX_BATCH} music ids - one per line. "
                            "Pasted lines from sync_candidates.md work as-is.",
                 bg=BG, fg=FG2, anchor="w").pack(fill="x", padx=16, pady=(14, 4))
        self.input_box = tk.Text(self, bg=BG3, fg=FG, insertbackground=FG,
                                 relief="flat", height=10, font=("Consolas", 9),
                                 padx=8, pady=6)
        self.input_box.pack(fill="x", padx=16)

        row = tk.Frame(self, bg=BG)
        row.pack(fill="x", padx=16, pady=8)
        self.publish_var = tk.BooleanVar(value=True)
        tk.Checkbutton(row, text="Publish each song after syncing",
                       variable=self.publish_var, bg=BG, fg=FG, selectcolor=BG3,
                       activebackground=BG, activeforeground=FG).pack(side="left")
        self.start_btn = tk.Button(row, text="Start", command=self.start,
                                   bg=BG3, fg=FG, activebackground=HILIGHT,
                                   activeforeground=FG, relief="flat", padx=18,
                                   pady=4, cursor="hand2")
        self.start_btn.pack(side="right")
        self.stop_btn = tk.Button(row, text="Stop after current", command=self.stop,
                                  bg=BG3, fg=FG2, activebackground=HILIGHT,
                                  activeforeground=FG, relief="flat", padx=12,
                                  pady=4, cursor="hand2", state="disabled")
        self.stop_btn.pack(side="right", padx=6)

        tk.Label(self, text="Progress", bg=BG, fg=FG2, anchor="w").pack(
            fill="x", padx=16, pady=(6, 2))
        self.progress = tk.Text(self, bg=BG2, fg=FG2, relief="flat",
                                font=("Consolas", 9), state="disabled",
                                wrap="word", padx=8, pady=6)
        self.progress.pack(fill="both", expand=True, padx=16, pady=(0, 14))

    def plog(self, text: str):
        def write():
            if not self.progress.winfo_exists():
                return
            self.progress.configure(state="normal")
            self.progress.insert("end", text.rstrip() + "\n")
            self.progress.see("end")
            self.progress.configure(state="disabled")
        self.app.after(0, write)

    def parse_ids(self) -> list[int]:
        ids, seen = [], set()
        for line in self.input_box.get("1.0", "end").splitlines():
            match = re.search(r"(\d{5,})", line)
            if match:
                sound_id = int(match.group(1))
                if sound_id not in seen:
                    seen.add(sound_id)
                    ids.append(sound_id)
        return ids

    def stop(self):
        self.stop_requested = True
        self.plog("! stop requested - finishing the current song first")

    def start(self):
        if self.running:
            return
        ids = self.parse_ids()
        if not ids:
            self.app.notify("No ids found", "Paste music ids first, one per line",
                            error=True)
            return
        if len(ids) > self.MAX_BATCH:
            self.app.notify(f"Capped at {self.MAX_BATCH}",
                            f"{len(ids) - self.MAX_BATCH} extra id(s) were ignored - "
                            "run another batch for those.")
            ids = ids[:self.MAX_BATCH]
        if self.publish_var.get() and not self.app.api_url:
            self.app.notify("No API configured",
                            "Publishing is on but there is no api_url in "
                            "~/.lyricsync/config.json", error=True)
            return

        self.running = True
        self.stop_requested = False
        self.start_btn.configure(state="disabled")
        self.stop_btn.configure(state="normal")
        threading.Thread(target=self._worker, args=(ids,), daemon=True).start()

    def _worker(self, ids: list[int]):
        from concurrent.futures import ThreadPoolExecutor

        publish = self.publish_var.get()
        use_groq = groq_ready()
        # Groq syncs are pure network - three at once is nowhere near its rate
        # limits. Local whisper owns the GPU, so it stays one at a time.
        workers = 3 if use_groq else 1
        self.plog("engine: " + (
            f"Groq API, {workers} songs in parallel (demucs skipped - the API "
            "gets the original file anyway)" if use_groq
            else "local whisper, one song at a time (it owns the GPU)"))

        lock = threading.Lock()
        tally = {"done": 0, "failed": 0, "skipped": 0}

        def process(index: int, sound_id: int):
            prefix = f"[{index}/{len(ids)}] {sound_id}"
            if self.stop_requested:
                with lock:
                    tally["skipped"] += 1
                return
            try:
                details = fetch_details(sound_id)
                title = details["title"] or str(sound_id)
                self.plog(f"{prefix} {title} - downloading...")
                audio = download_audio(sound_id)

                self.plog(f"{prefix} syncing...")
                out = DOWNLOADS / f"{sound_id}.sync.json"
                cmd = [sys.executable, "-m", "lyricsync", "sync", str(audio),
                       "--id", str(sound_id), "--user", self.app.username,
                       "-o", str(out), "--format", "json", "--quiet"]
                if use_groq:
                    # forced: a Groq hiccup fails this one song instead of
                    # silently piling three local whisper models onto the GPU
                    cmd += ["--engine", "groq", "--separate", "never"]
                proc = subprocess.run(cmd, cwd=HERE, capture_output=True,
                                      text=True, encoding="utf-8", errors="replace")
                if proc.returncode != 0 or not out.exists():
                    tail = (proc.stderr or proc.stdout or "").strip().splitlines()
                    raise RuntimeError(tail[-1] if tail else f"exit {proc.returncode}")
                doc = json.loads(out.read_text(encoding="utf-8"))
                count = len(doc.get("Lyrics") or [])
                if count == 0:
                    raise RuntimeError("no lyric lines produced (instrumental?)")

                if publish:
                    ok, note = api_publish(self.app.api_url, self.app.publish_key, doc)
                    if not ok:
                        raise RuntimeError(f"publish failed: {note}")
                    self.plog(f"{prefix} OK - {count} lines published ({note})")
                else:
                    self.plog(f"{prefix} OK - {count} lines synced (not published)")
                with lock:
                    tally["done"] += 1
            except Exception as exc:
                with lock:
                    tally["failed"] += 1
                self.plog(f"{prefix} FAILED - {exc}")

        with ThreadPoolExecutor(max_workers=workers) as pool:
            for future in [pool.submit(process, i, sid)
                           for i, sid in enumerate(ids, start=1)]:
                future.result()

        done, failed = tally["done"], tally["failed"]
        if tally["skipped"]:
            self.plog(f"stopped - {tally['skipped']} song(s) were never started")

        self.running = False
        self.app.after(0, lambda: (self.start_btn.configure(state="normal"),
                                   self.stop_btn.configure(state="disabled"))
                       if self.winfo_exists() else None)
        self.app.notify("Bulk sync finished",
                        f"{done} song(s) {'published' if publish else 'synced'}, "
                        f"{failed} failed.")


class ArtistSyncWindow(tk.Toplevel):
    """Find every song by an artist on Roblox and sync them all at once."""

    def __init__(self, app: LyricStudio):
        super().__init__(app)
        self.app = app
        self.title("Sync All by Artist")
        self.configure(bg=BG)
        self.geometry("760x680")
        self.running = False
        self.stop_requested = False
        self.rows: list[tuple[tk.BooleanVar, int, str]] = []

        top = tk.Frame(self, bg=BG)
        top.pack(fill="x", padx=16, pady=(14, 4))
        tk.Label(top, text="Artist (or a music id of one of their songs):",
                 bg=BG, fg=FG2).pack(side="left")
        self.artist_var = tk.StringVar(value=app.artist_label.cget("text")
                                       if app.artist_label.cget("text").strip()
                                       and "Put in" not in app.artist_label.cget("text")
                                       else "")
        tk.Entry(top, textvariable=self.artist_var, width=26, bg=BG3, fg=FG,
                 insertbackground=FG, relief="flat").pack(side="left", padx=6, ipady=3)
        tk.Button(top, text="Find songs", command=self.on_find, bg=BG3, fg=FG,
                  activebackground=HILIGHT, activeforeground=FG, relief="flat",
                  padx=12, pady=3, cursor="hand2").pack(side="left", padx=4)

        opts = tk.Frame(self, bg=BG)
        opts.pack(fill="x", padx=16, pady=4)
        tk.Label(opts, text="Max songs:", bg=BG, fg=FG2).pack(side="left")
        self.limit_var = tk.StringVar(value="10")
        tk.Spinbox(opts, from_=1, to=200, textvariable=self.limit_var, width=5,
                   bg=BG3, fg=FG, insertbackground=FG, relief="flat",
                   buttonbackground=BG3).pack(side="left", padx=(4, 14))
        self.skip_var = tk.BooleanVar(value=True)
        tk.Checkbutton(opts, text="Skip already-synced (published)",
                       variable=self.skip_var, bg=BG, fg=FG, selectcolor=BG3,
                       activebackground=BG, activeforeground=FG).pack(side="left")
        self.publish_var = tk.BooleanVar(value=True)
        tk.Checkbutton(opts, text="Publish each after syncing",
                       variable=self.publish_var, bg=BG, fg=FG, selectcolor=BG3,
                       activebackground=BG, activeforeground=FG).pack(side="left", padx=(14, 0))

        # scrollable checklist of found songs
        listwrap = tk.Frame(self, bg=BG2)
        listwrap.pack(fill="both", expand=True, padx=16, pady=(6, 6))
        self.canvas = tk.Canvas(listwrap, bg=BG2, highlightthickness=0)
        sb = tk.Scrollbar(listwrap, orient="vertical", command=self.canvas.yview)
        self.list_frame = tk.Frame(self.canvas, bg=BG2)
        self.list_frame.bind("<Configure>", lambda _e: self.canvas.configure(
            scrollregion=self.canvas.bbox("all")))
        self.canvas.create_window((0, 0), window=self.list_frame, anchor="nw")
        self.canvas.configure(yscrollcommand=sb.set)
        self.canvas.pack(side="left", fill="both", expand=True)
        sb.pack(side="right", fill="y")

        row = tk.Frame(self, bg=BG)
        row.pack(fill="x", padx=16, pady=(0, 4))
        self.status = tk.Label(row, text="Find an artist's songs to begin.",
                               bg=BG, fg=FG2, anchor="w")
        self.status.pack(side="left")
        self.start_btn = tk.Button(row, text="Sync selected", command=self.start,
                                   bg=BG3, fg=FG, activebackground=HILIGHT,
                                   activeforeground=FG, relief="flat", padx=18,
                                   pady=4, cursor="hand2", state="disabled")
        self.start_btn.pack(side="right")
        self.stop_btn = tk.Button(row, text="Stop after current", command=self.stop,
                                  bg=BG3, fg=FG2, activebackground=HILIGHT,
                                  activeforeground=FG, relief="flat", padx=12,
                                  pady=4, cursor="hand2", state="disabled")
        self.stop_btn.pack(side="right", padx=6)

        self.progress = tk.Text(self, bg=BG2, fg=FG2, relief="flat",
                                font=("Consolas", 9), state="disabled",
                                wrap="word", height=8, padx=8, pady=6)
        self.progress.pack(fill="x", padx=16, pady=(0, 14))

    def plog(self, text: str):
        def write():
            if not self.progress.winfo_exists():
                return
            self.progress.configure(state="normal")
            self.progress.insert("end", text.rstrip() + "\n")
            self.progress.see("end")
            self.progress.configure(state="disabled")
        self.app.after(0, write)

    def _set_status(self, text: str):
        self.app.after(0, lambda: self.status.winfo_exists()
                       and self.status.configure(text=text))

    def on_find(self):
        query = self.artist_var.get().strip()
        if not query:
            self.app.notify("No artist", "Type an artist name or a music id first",
                            error=True)
            return
        self._set_status("Searching Roblox...")
        threading.Thread(target=self._find_worker, args=(query,), daemon=True).start()

    def _find_worker(self, query: str):
        try:
            limit = max(1, int(self.limit_var.get()))
        except ValueError:
            limit = 10
        artist, songs = discover_artist_songs(query, log=self.plog)
        skip = self.skip_var.get()
        published = api_published_ids(self.app.api_url) if (skip and self.app.api_url) else set()
        if skip and published:
            before = len(songs)
            songs = [(sid, name) for sid, name in songs if str(sid) not in published]
            self.plog(f"skipped {before - len(songs)} already-published song(s)")
        songs = songs[:limit]
        self.app.after(0, lambda: self._populate(artist, songs))

    def _populate(self, artist: str, songs: list[tuple[int, str]]):
        for child in self.list_frame.winfo_children():
            child.destroy()
        self.rows = []
        for sid, name in songs:
            var = tk.BooleanVar(value=True)
            cb = tk.Checkbutton(self.list_frame, text=f"{name}   ({sid})",
                                variable=var, bg=BG2, fg=FG, selectcolor=BG3,
                                activebackground=BG2, activeforeground=FG,
                                anchor="w")
            cb.pack(fill="x", anchor="w")
            self.rows.append((var, sid, name))
        if songs:
            self._set_status(f"{len(songs)} song(s) for “{artist}” - untick any to skip, "
                             "then Sync selected.")
            self.start_btn.configure(state="normal")
        else:
            self._set_status(f"No matching songs found for “{artist}”.")
            self.start_btn.configure(state="disabled")

    def stop(self):
        self.stop_requested = True
        self.plog("! stop requested - finishing the current song first")

    def start(self):
        if self.running:
            return
        ids = [(sid, name) for var, sid, name in self.rows if var.get()]
        if not ids:
            self.app.notify("Nothing selected", "Tick at least one song", error=True)
            return
        if self.publish_var.get() and not self.app.api_url:
            self.app.notify("No API configured",
                            "Publishing is on but there is no api_url in "
                            "~/.lyricsync/config.json", error=True)
            return
        self.running = True
        self.stop_requested = False
        self.start_btn.configure(state="disabled")
        self.stop_btn.configure(state="normal")
        threading.Thread(target=self._sync_worker, args=(ids,), daemon=True).start()

    def _sync_worker(self, songs: list[tuple[int, str]]):
        from concurrent.futures import ThreadPoolExecutor
        publish = self.publish_var.get()
        use_groq = groq_ready()
        workers = 3 if use_groq else 1
        self.plog("engine: " + ("Groq API, 3 in parallel" if use_groq
                                 else "local whisper, one at a time"))
        lock = threading.Lock()
        tally = {"done": 0, "failed": 0, "skipped": 0}

        def process(index: int, sound_id: int):
            prefix = f"[{index}/{len(songs)}] {sound_id}"
            if self.stop_requested:
                with lock:
                    tally["skipped"] += 1
                return
            try:
                sync_one_song(self.app, sound_id, publish, use_groq, self.plog, prefix)
                with lock:
                    tally["done"] += 1
            except Exception as exc:
                with lock:
                    tally["failed"] += 1
                self.plog(f"{prefix} FAILED - {exc}")

        with ThreadPoolExecutor(max_workers=workers) as pool:
            for future in [pool.submit(process, i, sid)
                           for i, (sid, _n) in enumerate(songs, start=1)]:
                future.result()

        done, failed = tally["done"], tally["failed"]
        if tally["skipped"]:
            self.plog(f"stopped - {tally['skipped']} song(s) were never started")
        self.running = False
        self.app.after(0, lambda: (self.start_btn.configure(state="normal"),
                                   self.stop_btn.configure(state="disabled"))
                       if self.winfo_exists() else None)
        self.app.notify("Artist sync finished",
                        f"{done} song(s) {'published' if publish else 'synced'}, "
                        f"{failed} failed.")


class DiscordPostWindow(tk.Toplevel):
    """Builds a ready-to-paste Discord forum post for the lyrics channel."""

    def __init__(self, app: LyricStudio):
        super().__init__(app)
        self.app = app
        self.title("Discord Post")
        self.configure(bg=BG)
        self.geometry("640x640")

        song_title = app.title_label.cget("text")
        if song_title in ("", "No song loaded"):
            song_title = str(app.doc.get("SoundId") or "Untitled")

        description = (
            f"Generated by: Whisper\n"
            f"Synced by: AI (<@1441450343144886293>)\n\n"
            "-# How it works: i run the sound id through a script which gets "
            "the audio, then i use Whisper for the raw lyrics, then i use "
            "Whisper's word-level timestamps with forced alignment to sync "
            "every line, and then i upload it."
        )
        lyrics_json = json.dumps(self.app.doc)

        self._section("Title", song_title, height=1)
        self._section("Description", description, height=9)
        self._section("Lyrics (paste or attach as message.txt)", lyrics_json,
                      height=8, savable=True)

    def _section(self, label: str, content: str, height: int, savable: bool = False):
        row = tk.Frame(self, bg=BG)
        row.pack(fill="x", padx=16, pady=(12, 0))
        tk.Label(row, text=label, bg=BG, fg=FG2, anchor="w").pack(side="left")

        text = tk.Text(self, bg=BG3, fg=FG, insertbackground=FG, relief="flat",
                       height=height, wrap="word", font=("Consolas", 9), padx=8, pady=6)
        text.insert("1.0", content)
        text.pack(fill="x", padx=16, pady=(4, 0))

        def copy():
            value = text.get("1.0", "end-1c")
            self.clipboard_clear()
            self.clipboard_append(value)
            self.app.notify("Copied to clipboard", label, silent=True)

        tk.Button(row, text="Copy", command=copy, bg=BG3, fg=FG,
                  activebackground=HILIGHT, activeforeground=FG, relief="flat",
                  padx=10, pady=1, cursor="hand2").pack(side="right")

        if savable:
            def save():
                path = filedialog.asksaveasfilename(
                    parent=self, initialfile="message.txt",
                    defaultextension=".txt", filetypes=[("Text", "*.txt")])
                if path:
                    Path(path).write_text(text.get("1.0", "end-1c"), encoding="utf-8")
                    self.app.notify("Saved", Path(path).name + " - attach it to the post",
                                    silent=True)
            tk.Button(row, text="Save message.txt", command=save, bg=BG3, fg=FG,
                      activebackground=HILIGHT, activeforeground=FG, relief="flat",
                      padx=10, pady=1, cursor="hand2").pack(side="right", padx=(0, 6))


# ---------------------------------------------------------------- selftest


def selftest(sound_id: int) -> int:
    print(f"selftest for {sound_id}")
    print(f"  pygame audio: {'ok' if AUDIO_OK else 'MISSING (pip install pygame)'}")
    details = fetch_details(sound_id)
    print(f"  details: title={details['title']!r} artist={details['artist']!r}")
    thumb = fetch_thumbnail(sound_id)
    print(f"  thumbnail: {'ok, ' + str(len(thumb)) + ' bytes' if thumb else 'FAILED'}")
    try:
        path = download_audio(sound_id)
        print(f"  audio: ok -> {path} ({path.stat().st_size} bytes)")
    except RuntimeError as exc:
        print(f"  audio: FAILED - {exc}")
    cfg = load_config()
    api = (cfg.get("api_url") or "").rstrip("/")
    print(f"  api: {api or '(none)'}")
    if api:
        doc = api_fetch_lyrics(api, sound_id)
        print(f"  published lyrics: {'yes, ' + str(len(doc['Lyrics'])) + ' lines' if doc else 'none'}")
    return 0


if __name__ == "__main__":
    if len(sys.argv) >= 3 and sys.argv[1] == "--selftest":
        raise SystemExit(selftest(int(sys.argv[2])))
    LyricStudio().mainloop()
