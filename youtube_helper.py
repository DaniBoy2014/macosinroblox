#!/usr/bin/env python3
"""
YouTube helper for macOS in Roblox (coolui.lua)

Roblox can't play YouTube by itself, so this small program does that part on
your PC. It finds and searches videos with yt-dlp, decodes them with ffmpeg,
and hands the YouTube app in the game its pictures (raw frames) and sound
(short mp3 files) at http://127.0.0.1:8765. Only your own PC can reach it,
and the only other thing it talks to is YouTube.

Needs:  Python 3.9 or newer
        yt-dlp   (pip install -U yt-dlp)
        ffmpeg   (on your PATH: https://ffmpeg.org/download.html)

Run it with   python youtube_helper.py   and leave it open while you watch.
"""

import collections
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import threading
import time
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, quote_plus, urlparse

try:
    import yt_dlp
except ImportError:
    sys.exit("yt-dlp isn't installed. Install it with:  pip install -U yt-dlp")

HOST, PORT = "127.0.0.1", 8765
VERSION = 1
AUDIO_SEGMENT = 10  # seconds of sound per mp3 file (a video)
LIVE_SEGMENT = 5  # the same for a live stream, which can only be watched once a file is finished
LIVE_BEHIND = LIVE_SEGMENT + 2  # so a live stream plays this many seconds behind the newest picture
AHEAD = 8  # seconds of pictures to decode ahead of what's been asked for
LIVE_KEEP = 12  # seconds of pictures a live stream keeps before dropping old ones
IDLE_STOP = 30  # a session nobody asks about for this long is stopped

# YouTube's own search filters (the "sp" parameter): videos only, live now,
# and videos under 4 minutes (with "#shorts" in the search, mostly Shorts)
FILTERS = {"video": "EgIQAQ%3D%3D", "live": "EgJAAQ%3D%3D", "shorts": "EgQQARgB"}


def log(*parts):
    print(time.strftime("%H:%M:%S"), *parts, flush=True)


def ydl(options=None):
    settings = {"quiet": True, "no_warnings": True, "skip_download": True, "noprogress": True}
    settings.update(options or {})
    return yt_dlp.YoutubeDL(settings)


def thumbnail(video_id):
    return f"https://i.ytimg.com/vi/{video_id}/mqdefault.jpg"


# ---------- Search ----------

def search(query, kind, limit):
    """Videos, Shorts or live streams for a query, newest YouTube ranking first."""
    if kind == "shorts":
        query = query + " #shorts"
    url = "https://www.youtube.com/results?search_query=" + quote_plus(query) + "&sp=" + FILTERS.get(kind, FILTERS["video"])
    with ydl({"extract_flat": "in_playlist", "playlistend": limit * 3}) as y:
        info = y.extract_info(url, download=False)
    results = []
    for entry in info.get("entries") or []:
        video_id = entry.get("id")
        if not video_id or len(video_id) != 11:
            continue
        short = "/shorts/" in (entry.get("url") or "")
        live = entry.get("live_status") == "is_live"
        duration = entry.get("duration")
        if kind == "shorts" and not (short or (duration and duration <= 180)):
            continue
        if kind == "live" and not live:
            continue
        results.append({
            "id": video_id,
            "title": entry.get("title") or "",
            "channel": entry.get("channel") or entry.get("uploader") or "",
            "duration": duration,
            "views": entry.get("view_count") or entry.get("concurrent_view_count"),
            "live": live,
            "short": short or kind == "shorts",
            "thumbnail": thumbnail(video_id),
        })
        if len(results) >= limit:
            break
    return results


# ---------- Playback ----------

def header_args(fmt):
    headers = fmt.get("http_headers") or {}
    if not headers:
        return []
    return ["-headers", "".join(f"{key}: {value}\r\n" for key, value in headers.items())]


# A video's details (and its stream links) for half an hour, so seeking
# doesn't look the video up again. Saved as JSON for yt-dlp to download from.
INFO_FOLDER = tempfile.mkdtemp(prefix="coolui_youtube_info_")
info_cache = {}
info_lock = threading.Lock()


def video_info(video_id, limit):
    key = (video_id, limit)
    with info_lock:
        cached = info_cache.get(key)
    if cached and time.time() - cached[0] < 1800 and os.path.exists(cached[2]):
        return cached[1], cached[2]
    # Under `limit` pixels tall, preferring H.264 (quickest to decode) and
    # ordinary-quality sound
    choice = (f"(bv*[height<={limit}][vcodec^=avc1]/bv*[height<={limit}])+(ba[abr<=160]/ba)"
              f"/b[height<={limit}]/bv*+ba/b")
    with ydl({"format": choice}) as y:
        info = y.extract_info("https://www.youtube.com/watch?v=" + video_id, download=False)
        path = os.path.join(INFO_FOLDER, f"{video_id}_{limit}_{uuid.uuid4().hex[:6]}.json")
        with open(path, "w", encoding="utf-8") as file:
            json.dump(y.sanitize_info(info), file)
    if not info.get("is_live"):  # (a live stream's links expire quickly)
        with info_lock:
            info_cache[key] = (time.time(), info, path)
    return info, path


class Session:
    """One video playing from `start` seconds: an ffmpeg decoding pictures
    into memory, and one cutting the sound into mp3 files. A video is fed to
    them by yt-dlp (YouTube refuses ffmpeg's own requests for whole files);
    a live stream comes in short pieces that ffmpeg can fetch itself."""

    def __init__(self, video_id, start, width, height, fps):
        self.id = uuid.uuid4().hex[:12]
        self.video_id = video_id
        self.start = max(0.0, start)
        self.width, self.height, self.fps = width, height, fps
        self.frame_size = width * height * 4
        self.frames = collections.deque()  # (index, bytes)
        self.wanted = 0  # the first frame the game still needs
        self.video_done = False
        self.audio_done = False
        self.closed = False
        self.cond = threading.Condition()
        self.last_seen = time.time()
        self.folder = tempfile.mkdtemp(prefix="coolui_youtube_")
        self.processes = []

        # Small enough to decode quickly, big enough for the size it's shown at
        limit = 480 if max(width, height) <= 640 else 720
        info, info_path = video_info(video_id, limit)
        # Usually a picture-only and a sound-only stream; sometimes one that has both.
        # (Live streams list their sound's codec as unknown, so "no picture" is the test.)
        parts = info.get("requested_formats") or [info]
        video = next((p for p in parts if p.get("vcodec") not in (None, "none")), parts[0])
        audio = next((p for p in parts if p is not video and p.get("vcodec") in (None, "none")), None)
        if audio is None and video.get("acodec") != "none":
            audio = video
        self.live = bool(info.get("is_live"))
        self.segment = LIVE_SEGMENT if self.live else AUDIO_SEGMENT
        self.info = {
            "session": self.id,
            "id": video_id,
            "title": info.get("title") or "",
            "channel": info.get("channel") or info.get("uploader") or "",
            "duration": None if self.live else info.get("duration"),
            "live": self.live,
            "width": width,
            "height": height,
            "fps": fps,
            "start": 0 if self.live else self.start,
            "segment": self.segment,
            "sourceWidth": info.get("width"),
            "sourceHeight": info.get("height"),
            "thumbnail": thumbnail(video_id),
        }

        # An old-style MP4 (one file with picture and sound, as some Shorts only
        # have) keeps its index at the end, which ffmpeg can't reach in a stream,
        # so it's downloaded whole first. They're small.
        self.whole_file = None
        if not self.live and not str(video.get("container") or "").endswith("_dash"):
            path = os.path.join(self.folder, "whole." + (video.get("ext") or "mp4"))
            subprocess.run(
                [sys.executable, "-m", "yt_dlp", "-q", "--no-warnings", "--no-part", "--load-info-json", info_path,
                 "-f", video["format_id"], "-o", path],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=600)
            if os.path.exists(path):
                self.whole_file = path

        def source(fmt):
            """ffmpeg's input options for a stream, and what feeds its stdin"""
            if self.live:
                return header_args(fmt) + ["-i", fmt["url"]], None
            if self.whole_file and fmt.get("format_id") == video.get("format_id"):
                return (["-ss", f"{self.start:.3f}"] if self.start > 0 else []) + ["-i", self.whole_file], None
            feed = subprocess.Popen(
                [sys.executable, "-m", "yt_dlp", "-q", "--no-warnings", "--no-part", "--load-info-json", info_path,
                 "-f", fmt["format_id"], "-o", "-"],
                stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
            self.processes.append(feed)
            seek = ["-ss", f"{self.start:.3f}"] if self.start > 0 else []
            return seek + ["-i", "pipe:0"], feed

        picture = (
            f"scale={width}:{height}:force_original_aspect_ratio=decrease:flags=bicubic,"
            f"pad={width}:{height}:(ow-iw)/2:(oh-ih)/2:color=black,fps={fps}"
        )
        options, feed = source(video)
        self.video_process = subprocess.Popen(
            ["ffmpeg", "-nostdin", "-loglevel", "error"] + options
            + ["-an", "-vf", picture, "-f", "rawvideo", "-pix_fmt", "rgba", "pipe:1"],
            stdin=feed.stdout if feed else subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        if feed:
            feed.stdout.close()  # (ffmpeg has it now)
        self.processes.append(self.video_process)
        threading.Thread(target=self._read_pictures, daemon=True).start()

        if audio:
            options, feed = source(audio)
            self.audio_process = subprocess.Popen(
                ["ffmpeg", "-nostdin", "-loglevel", "error"] + options
                + ["-vn", "-ac", "2", "-ar", "44100", "-c:a", "libmp3lame", "-b:a", "128k",
                   "-f", "segment", "-segment_time", str(self.segment), "-reset_timestamps", "1",
                   os.path.join(self.folder, "seg%05d.mp3")],
                stdin=feed.stdout if feed else subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            if feed:
                feed.stdout.close()
            self.processes.append(self.audio_process)
            threading.Thread(target=self._wait_for_audio, daemon=True).start()
        else:
            self.audio_done = True
            self.info["silent"] = True
        log(f"playing {video_id} ({'live' if self.live else 'from %.0fs' % self.start}) at {width}x{height} {fps}fps")

    def _read_pictures(self):
        index = 0
        stream = self.video_process.stdout
        while True:
            data = stream.read(self.frame_size)
            if not data or len(data) < self.frame_size:
                break
            with self.cond:
                # A video waits for the game to catch up; live just drops old pictures
                while not self.closed and not self.live and index - self.wanted > self.fps * AHEAD:
                    self.cond.wait(0.5)
                if self.closed:
                    break
                self.frames.append((index, data))
                while self.live and len(self.frames) > self.fps * LIVE_KEEP:
                    self.frames.popleft()
                index += 1
                self.cond.notify_all()
        with self.cond:
            self.video_done = True
            self.cond.notify_all()

    def _wait_for_audio(self):
        self.audio_process.wait()
        self.audio_done = True

    def pictures(self, first, most, wait):
        """Up to `most` pictures from number `first` on (fewer if they aren't
        decoded yet). Returns (number of the first one sent, list, finished)."""
        self.last_seen = time.time()
        with self.cond:
            self.wanted = max(self.wanted, first)
            self.cond.notify_all()
            deadline = time.time() + wait
            while (not self.video_done and (not self.frames or self.frames[-1][0] < first)
                   and time.time() < deadline):
                self.cond.wait(0.1)
            # A live stream starts with a burst of the last several seconds. Watch
            # LIVE_BEHIND seconds behind the newest picture rather than at the start
            # of the burst (or the oldest pictures would be dropped just as they're
            # needed), which also gives each sound file time to finish.
            if self.live and self.frames and first < self.frames[-1][0] - self.fps * (LIVE_BEHIND + 3):
                first = max(self.frames[0][0], self.frames[-1][0] - self.fps * LIVE_BEHIND)
                self.wanted = first
            # What's been asked past is no longer needed
            while self.frames and self.frames[0][0] < first and not self.live:
                self.frames.popleft()
            chosen = [frame for frame in self.frames if frame[0] >= first][:most]
            if not chosen and self.live and self.frames:
                # The game fell behind a live stream: send the oldest we still have
                chosen = list(self.frames)[:most]
            finished = self.video_done and (not self.frames or self.frames[-1][0] < first + len(chosen))
        start = chosen[0][0] if chosen else first
        return start, [data for _, data in chosen], finished

    def sound(self, number):
        """The mp3 for audio segment `number`, "wait" if it isn't finished, or None past the end."""
        self.last_seen = time.time()
        path = os.path.join(self.folder, f"seg{number:05d}.mp3")
        following = os.path.join(self.folder, f"seg{number + 1:05d}.mp3")
        if os.path.exists(path) and (os.path.exists(following) or self.audio_done):
            with open(path, "rb") as file:
                return file.read()
        if self.audio_done and not os.path.exists(path):
            return None
        return "wait"

    def close(self):
        with self.cond:
            self.closed = True
            self.cond.notify_all()
        for process in self.processes:
            try:
                process.kill()
            except Exception:
                pass
        shutil.rmtree(self.folder, ignore_errors=True)


sessions = {}
sessions_lock = threading.Lock()


def janitor():
    while True:
        time.sleep(5)
        with sessions_lock:
            stale = [s for s in sessions.values() if time.time() - s.last_seen > IDLE_STOP]
            for session in stale:
                del sessions[session.id]
        for session in stale:
            log(f"stopped {session.video_id} (nothing asked for it)")
            session.close()


# ---------- HTTP ----------

class Handler(BaseHTTPRequestHandler):
    server_version = "CooluiYouTubeHelper/1"

    def log_message(self, *args):
        pass

    def reply(self, status, body=b"", kind="application/json", headers=None):
        if isinstance(body, (dict, list)):
            body = json.dumps(body).encode()
        elif isinstance(body, str):
            body = body.encode()
        self.send_response(status)
        self.send_header("Content-Type", kind)
        self.send_header("Content-Length", str(len(body)))
        for key, value in (headers or {}).items():
            self.send_header(key, str(value))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        url = urlparse(self.path)
        query = {key: values[0] for key, values in parse_qs(url.query).items()}
        try:
            route = getattr(self, "route_" + url.path.strip("/"), None)
            if not route:
                return self.reply(404, {"error": "unknown path"})
            route(query)
        except Exception as error:  # report it to the game instead of dropping the connection
            log("error:", url.path, error)
            try:
                self.reply(500, {"error": str(error)[:300]})
            except Exception:
                pass

    def session(self, query):
        with sessions_lock:
            return sessions.get(query.get("session", ""))

    def route_ping(self, query):
        self.reply(200, {"ok": True, "version": VERSION})

    def route_search(self, query):
        text = query.get("q", "").strip()
        kind = query.get("type", "video")
        limit = max(1, min(40, int(query.get("limit", "24"))))
        if not text:
            return self.reply(400, {"error": "empty search"})
        self.reply(200, {"results": search(text, kind, limit)})

    def route_play(self, query):
        video_id = query.get("id", "")
        if not re.fullmatch(r"[A-Za-z0-9_-]{11}", video_id):
            return self.reply(400, {"error": "that isn't a YouTube video id"})
        width = max(64, min(1024, int(query.get("w", "480"))))
        height = max(64, min(1024, int(query.get("h", "270"))))
        fps = max(5, min(30, int(query.get("fps", "24"))))
        session = Session(video_id, float(query.get("start", "0")), width, height, fps)
        with sessions_lock:
            sessions[session.id] = session
        self.reply(200, session.info)

    def route_frames(self, query):
        session = self.session(query)
        if not session:
            return self.reply(404, {"error": "no such session"})
        first = int(query.get("from", "0"))
        most = max(1, min(60, int(query.get("max", "12"))))
        start, pictures, finished = session.pictures(first, most, float(query.get("wait", "2")))
        self.reply(200, b"".join(pictures), "application/octet-stream",
                   {"X-First": start, "X-Count": len(pictures), "X-Ended": 1 if finished else 0})

    def route_audio(self, query):
        session = self.session(query)
        if not session:
            return self.reply(404, {"error": "no such session"})
        data = session.sound(int(query.get("seg", "0")))
        if data is None:
            self.reply(410, {"error": "no more sound"})
        elif data == "wait":
            self.reply(202, {"wait": True})
        else:
            self.reply(200, data, "audio/mpeg")

    def route_stop(self, query):
        with sessions_lock:
            session = sessions.pop(query.get("session", ""), None)
        if session:
            session.close()
        self.reply(200, {"ok": True})


def main():
    if not shutil.which("ffmpeg"):
        sys.exit("ffmpeg isn't on your PATH. Install it (https://ffmpeg.org/download.html) and try again.")
    threading.Thread(target=janitor, daemon=True).start()
    server = ThreadingHTTPServer((HOST, PORT), Handler)
    server.daemon_threads = True
    log(f"YouTube helper for macOS in Roblox is running at http://{HOST}:{PORT}")
    log("Leave this window open while you use the YouTube app. Press Ctrl+C to stop.")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        with sessions_lock:
            for session in sessions.values():
                session.close()
        shutil.rmtree(INFO_FOLDER, ignore_errors=True)


if __name__ == "__main__":
    main()
