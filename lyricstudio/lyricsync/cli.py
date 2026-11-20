"""Command line interface for lyricsync."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from . import __version__, audioutil, config, gpu, groqapi, luafmt, macos, roblox, separate, songs
from .align import align_reference, coverage, read_lyrics_file
from .lines import LineOptions, group_words, rebalance
from .transcribe import MODELS, Backend, Word, pick_backend, transcribe

CACHE_DIR = config.CONFIG_DIR / "cache"
STEM_DIR = config.CONFIG_DIR / "stems"
COMMANDS = ("sync", "setup", "doctor", "convert", "publish", "macos")


# --------------------------------------------------------------------------- args


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="lyricsync",
        description="Turn an .mp3 plus a Roblox audio id into a timed Roblox lyrics JSON file.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "examples:\n"
            "  python -m lyricsync song.mp3 --id 6910191685 --user EpicTitan100\n"
            "  python -m lyricsync song.mp3 --id rbxassetid://6910191685 --user Me --separate always\n"
            "  python -m lyricsync song.mp3 --id 6910191685 --user Me --lyrics-file song.lyrics.txt\n"
            "  python -m lyricsync song.mp3 --id 6910191685 --user Me --macos lofi --title \"Rainy Day\"\n"
            "  python -m lyricsync macos song.mp3 --category dance --artist Someone\n"
            "  python -m lyricsync setup --model large-v3 --demucs\n"
        ),
    )
    parser.add_argument("--version", action="version", version=f"lyricsync {__version__}")
    sub = parser.add_subparsers(dest="command")

    sync = sub.add_parser("sync", help="transcribe an audio file and write the Roblox JSON")
    sync.add_argument("audio", help="path to the .mp3 (or wav/flac/ogg/m4a)")
    sync.add_argument("--id", "--sound-id", dest="sound_id", required=True,
                      help="Roblox audio id: 6910191685, rbxassetid://6910191685 or an asset URL")
    sync.add_argument("--user", "--username", dest="username",
                      help="name used in the certification line (remembered with --save)")
    sync.add_argument("--written-by", help="override the 'Written By' name")
    sync.add_argument("--synced-by", help="override the 'Synced By' name")
    sync.add_argument("--cert-template", help="custom certification text, {written_by} / {synced_by}")
    sync.add_argument("--no-certification", action="store_true", help="omit the CERTIFICATION entry")
    sync.add_argument("-o", "--out", help="write a single file to this exact path instead of songs/")
    sync.add_argument("--macos", metavar="CATEGORY",
                      help="also add the song and its lyrics to this category of macOS in Roblox Music "
                           "on this PC (lofi, or lofi/chill for one inside it)")
    sync.add_argument("--title", help="the song's title in Music (default: the file name)")
    sync.add_argument("--artist", help="the song's artist in Music")

    output = sync.add_argument_group("output")
    output.add_argument("--format", dest="fmt", choices=("json", "lua", "both"), default="both",
                        help="roblox JSON, a Lua table entry, or both (default: both)")
    output.add_argument("--songs-dir", default="songs",
                        help="library folder holding every song (default: ./songs)")
    output.add_argument("--name", help="folder name for this song (default: from the audio file name)")
    output.add_argument("--library", default="LyricsLibrary.lua",
                        help="combined ModuleScript file name inside the songs folder")
    output.add_argument("--no-library", action="store_true",
                        help="do not regenerate the combined ModuleScript")
    output.add_argument("--overwrite", action="store_true",
                        help="write even if the target folder already holds a different song")
    output.add_argument("--publish", action="store_true",
                        help="also upload to the Masters API so every player gets the lyrics live")

    engine = sync.add_argument_group("engine")
    engine.add_argument("--engine", choices=("auto", "groq", "local"), default="auto",
                        help="auto = Groq API when a key exists, local whisper otherwise")
    engine.add_argument("--model", help=f"whisper model (default: auto). Common: {', '.join(MODELS)}")
    engine.add_argument("--device", choices=("auto", "cuda", "cpu"), default="auto")
    engine.add_argument("--language", help="force a language code (e.g. en). Default: auto-detect")
    engine.add_argument("--beam-size", type=int, default=5)
    engine.add_argument("--prompt", help="initial prompt to nudge spelling/style")
    engine.add_argument("--no-vad", action="store_true", help="disable voice-activity filtering")
    engine.add_argument("--no-rescue", action="store_true",
                        help="skip the second pass over stretches the first pass left empty")
    engine.add_argument("--rescue-min", type=float, default=10.0, metavar="S",
                        help="how long a silent stretch must be to get a second pass (default 10s)")
    engine.add_argument("--repeat-tolerance", type=float, default=3.0, metavar="R",
                        help="how repetitive a segment may be before Whisper rejects it "
                             "(default 3.0; raise for songs with heavily repeated choruses)")
    engine.add_argument("--separate", choices=("auto", "always", "never"), default=None,
                        help="isolate vocals with demucs first (auto = use it when installed)")
    engine.add_argument("--force", action="store_true", help="re-transcribe even if a cache exists")
    engine.add_argument("--no-cache", action="store_true", help="do not read or write the word cache")

    layout = sync.add_argument_group("line layout")
    layout.add_argument("--lyrics-file", help="align to a corrected lyrics .txt (one line per lyric line)")
    layout.add_argument("--max-chars", type=int, default=42, help="max characters per line (default 42)")
    layout.add_argument("--max-duration", type=float, default=7.0, help="max seconds per line (default 7)")
    layout.add_argument("--gap", type=float, default=0.7, help="silence that starts a new line (default 0.7s)")
    layout.add_argument("--min-duration", type=float, default=0.9, help="merge lines shorter than this")
    layout.add_argument("--punctuation", choices=("keep", "soft", "strip"), default="soft")
    layout.add_argument("--capitalize", action="store_true", help="force a capital letter on every line")
    layout.add_argument("--no-txt", action="store_true", help="do not write the editable .lyrics.txt")

    timing = sync.add_argument_group("timing / output")
    timing.add_argument("--offset", type=float, default=0.0, help="shift every timestamp by N seconds")
    timing.add_argument("--gap-lines", type=float, default=6.0, metavar="S",
                        help="blank GAP entries for instrumental breaks longer than S seconds "
                             "(default 6, use 0 to disable)")
    timing.add_argument("--decimals", type=int, default=3, help="timestamp rounding (default 3)")
    timing.add_argument("--no-chain", action="store_true",
                        help="keep true line ends instead of holding until the next line")
    timing.add_argument("--align", choices=("none", "alternate", "all"), default="none",
                        help="RightAligned pattern (default none)")
    timing.add_argument("--unsynced", action="store_true", help="mark the document as Unsynced")
    timing.add_argument("--pretty", action="store_true", help="indent the JSON")
    timing.add_argument("--ascii", action="store_true", help="escape non-ASCII characters")
    timing.add_argument("--save", action="store_true", help="remember username/model for next time")
    timing.add_argument("--quiet", action="store_true")

    setup = sub.add_parser("setup", help="install dependencies and pre-download a model")
    setup.add_argument("--model", help="model to download now (default: the auto-picked one)")
    setup.add_argument("--demucs", action="store_true", help="also install demucs for vocal isolation")
    setup.add_argument("--username", help="save a default username")

    convert = sub.add_parser("convert", help="convert between the Lua table and the Roblox JSON")
    convert.add_argument("input", help="a .lua or .json file, or - to read from stdin")
    convert.add_argument("--format", dest="fmt", choices=("json", "lua", "both"), default="both",
                         help="what to write out (default: both)")
    convert.add_argument("-o", "--out", help="write one file to this exact path instead of songs/")
    convert.add_argument("--songs-dir", default="songs")
    convert.add_argument("--name", help="folder name (default: from the input file name)")
    convert.add_argument("--library", default="LyricsLibrary.lua")
    convert.add_argument("--no-library", action="store_true")
    convert.add_argument("--overwrite", action="store_true",
                         help="write even if the target folder holds a different song")
    convert.add_argument("--pretty", action="store_true")
    convert.add_argument("--ascii", action="store_true")
    convert.add_argument("--quiet", action="store_true")

    publish = sub.add_parser("publish", help="upload synced lyrics to the Masters API for everyone")
    publish.add_argument("input", nargs="?",
                         help="a .json or .lua file to publish (default: every song in the library)")
    publish.add_argument("--songs-dir", default="songs",
                         help="library folder used when no input file is given (default: ./songs)")
    publish.add_argument("--api", help="API base url, e.g. https://bestmusicplayer.vercel.app "
                                       "(remembered with --save)")
    publish.add_argument("--key", help="publish key, if the API requires one (remembered with --save)")
    publish.add_argument("--save", action="store_true", help="remember --api / --key for next time")
    publish.add_argument("--quiet", action="store_true")

    sub.add_parser("doctor", help="show what is installed and which device will be used")

    mac = sub.add_parser("macos", help="add a song and its lyrics to macOS in Roblox Music on this PC")
    mac.add_argument("audio", nargs="?", help="the mp3, ogg or wav (leave out to list the categories)")
    mac.add_argument("-c", "--category", help="lofi, or lofi/chill for a category inside another")
    mac.add_argument("--lyrics", help="its lyricsync .json (default: found in songs/ or next to the audio)")
    mac.add_argument("--title", help="the song's title (default: the file name)")
    mac.add_argument("--artist", help="the song's artist")
    mac.add_argument("--cover", help="a PNG or JPEG for the song's cover")
    mac.add_argument("--name", help="file name to use in the library (default: the title)")
    mac.add_argument("--workspace", help="the executor's workspace folder, if it isn't Real's (remembered)")
    return parser


def main(argv: list[str] | None = None) -> int:
    argv = list(sys.argv[1:] if argv is None else argv)
    if argv and argv[0] not in COMMANDS and not argv[0].startswith("-"):
        argv.insert(0, "sync")  # `lyricsync song.mp3 ...` works without typing `sync`
    args = build_parser().parse_args(argv)

    if args.command == "setup":
        return cmd_setup(args)
    if args.command == "doctor":
        return cmd_doctor()
    if args.command == "convert":
        return cmd_convert(args)
    if args.command == "publish":
        return cmd_publish(args)
    if args.command == "macos":
        return cmd_macos(args)
    if args.command == "sync":
        return cmd_sync(args)
    build_parser().print_help()
    return 1


# ------------------------------------------------------------------------ doctor


def cmd_doctor() -> int:
    import importlib.util

    print(f"lyricsync {__version__}")
    print(f"  python           {sys.version.split()[0]}")
    for module in ("faster_whisper", "ctranslate2", "av", "demucs", "torch"):
        mark = "yes" if importlib.util.find_spec(module) else "no"
        print(f"  {module:<16} {mark}")
    dirs = gpu.enable_cuda_libraries()
    print(f"  groq api         {'key found (syncs use the API)' if groqapi.available() else 'no key (local whisper)'}")
    print(f"  cuda devices     {gpu.cuda_device_count()}")
    if dirs:
        print(f"  cuda libs        {len(dirs)} directory(ies) registered")
    saved = config.load()
    print(f"  default engine   {pick_backend(saved.get('model') or None).describe()}")
    print(f"  config           {config.CONFIG_PATH}")
    if saved.get("username"):
        print(f"  saved username   {saved['username']}")
    return 0


def cmd_setup(args) -> int:
    import subprocess

    print("checking core dependencies...")
    try:
        import faster_whisper  # noqa: F401
    except ImportError:
        subprocess.run([sys.executable, "-m", "pip", "install", "faster-whisper"], check=False)

    try:
        import nvidia  # noqa: F401
    except ImportError:
        print("installing CUDA runtime libraries (cuBLAS + cuDNN)...")
        subprocess.run(
            [sys.executable, "-m", "pip", "install", "nvidia-cublas-cu12", "nvidia-cudnn-cu12>=9,<10"],
            check=False,
        )

    if args.demucs and not separate.available():
        separate.install()

    backend = pick_backend(args.model or config.load().get("model") or None)
    print(f"downloading model: {backend.describe()}")
    from .transcribe import load_model

    load_model(backend)
    print("model ready.")

    if args.username or args.model:
        config.save(username=args.username, model=args.model)
        print(f"saved defaults to {config.CONFIG_PATH}")
    return cmd_doctor()


# ----------------------------------------------------------------------- convert


def cmd_convert(args) -> int:
    """Lua table <-> Roblox JSON, for documents you have edited by hand."""
    log = (lambda *a: None) if args.quiet else print

    if args.input == "-":
        text, source_name, suffix = sys.stdin.read(), "pasted", ""
    else:
        path = Path(args.input).expanduser()
        if not path.exists():
            print(f"error: file not found: {path}", file=sys.stderr)
            return 2
        text, source_name, suffix = path.read_text(encoding="utf-8-sig"), path.stem, path.suffix.lower()

    def as_json() -> list[dict]:
        data = json.loads(text)
        return data if isinstance(data, list) else [data]

    try:
        # A Lua entry opens with ["id"], so sniffing the first character is not enough -
        # trust the extension, and only guess when there is none.
        if suffix == ".lua":
            documents, kind = luafmt.parse(text), "lua"
        elif suffix == ".json":
            documents, kind = as_json(), "json"
        else:
            try:
                documents, kind = as_json(), "json"
            except json.JSONDecodeError:
                documents, kind = luafmt.parse(text), "lua"
    except (ValueError, json.JSONDecodeError) as exc:
        print(f"error: could not read {source_name}: {exc}", file=sys.stderr)
        return 2

    documents = [_normalise(d) for d in documents]
    log(f"\n  read      {len(documents)} song(s) from {kind}: {source_name}")

    if args.out:
        if len(documents) > 1:
            print("error: -o writes a single file, but the input holds several songs.", file=sys.stderr)
            return 2
        out_path = Path(args.out).expanduser()
        fmt = args.fmt
        if fmt == "both":
            fmt = "lua" if out_path.suffix.lower() == ".lua" else "json"
        _emit(documents[0], out_path.parent, out_path.stem, fmt=fmt, pretty=args.pretty,
              ascii_only=args.ascii, log=log, json_path=out_path if fmt == "json" else None,
              lua_path=out_path if fmt == "lua" else None)
        return 0

    songs_dir = Path(args.songs_dir).expanduser()
    _warn_if_nested(songs_dir, log)
    for document in documents:
        stem = songs.slugify(args.name or source_name if len(documents) == 1
                             else str(document["SoundId"]))
        folder = songs.song_folder(songs_dir, stem)
        if not _safe_to_write(folder / f"{stem}.json", document["SoundId"], args.overwrite):
            return 2
        _emit(document, folder, stem, fmt=args.fmt, pretty=args.pretty, ascii_only=args.ascii, log=log)
        log(f"  {len(document['Lyrics'])} entries, SoundId {document['SoundId']}")

    if args.fmt in ("lua", "both") and not args.no_library:
        library_path, count = songs.rebuild_library(songs_dir, args.library)
        log(f"  lua library         -> {library_path}  ({count} song{'s' if count != 1 else ''})")
    log("")
    return 0


def _normalise(document: dict) -> dict:
    """Fill in anything a hand-edited document is missing."""
    if not isinstance(document, dict) or "Lyrics" not in document:
        raise ValueError("a song needs SoundId and Lyrics")
    entries = []
    for index, item in enumerate(document.get("Lyrics") or [], start=1):
        entries.append(
            {
                "RightAligned": bool(item.get("RightAligned", False)),
                "Line": str(item.get("Line", "")),
                "Id": str(item.get("Id") or f"L{index}"),
                "TimeStart": float(item.get("TimeStart", 0.0)),
                "TimeEnd": float(item.get("TimeEnd", 0.0)),
                "Adlibs": item.get("Adlibs") or [],
            }
        )
    return {
        "SoundId": int(document.get("SoundId") or 0),
        "Lyrics": entries,
        "Unsynced": bool(document.get("Unsynced", False)),
    }


def _emit(document, folder: Path, stem: str, *, fmt: str, pretty: bool, ascii_only: bool, log,
          json_path: Path | None = None, lua_path: Path | None = None) -> None:
    """Write a document as JSON, Lua, or both."""
    folder.mkdir(parents=True, exist_ok=True)
    if fmt in ("json", "both"):
        path = json_path or folder / f"{stem}.json"
        path.write_text(roblox.dumps(document, pretty=pretty, ascii_only=ascii_only), encoding="utf-8")
        log(f"  roblox json         -> {path}")
    if fmt in ("lua", "both"):
        path = lua_path or folder / f"{stem}.lua"
        path.write_text(luafmt.entry(document) + "\n", encoding="utf-8")
        log(f"  lua table entry     -> {path}")


def _safe_to_write(json_path: Path, sound_id: int, overwrite: bool) -> bool:
    """Stop a song from landing in a folder that already holds a different one."""
    if overwrite or not json_path.exists():
        return True
    try:
        existing = json.loads(json_path.read_text(encoding="utf-8")).get("SoundId")
    except (OSError, json.JSONDecodeError):
        return True
    if existing is None or int(existing) == int(sound_id):
        return True
    print(f"error: {json_path} already holds SoundId {existing}, not {sound_id}.", file=sys.stderr)
    print("       That usually means --name was left over from another song.", file=sys.stderr)
    print("       Pass a different --name, or --overwrite to replace it.", file=sys.stderr)
    return False


def _warn_if_nested(songs_dir: Path, log) -> None:
    """Catch `cd songs && lyricsync ...`, which quietly makes songs/songs/."""
    parent = songs_dir.resolve().parent
    if (parent / "LyricsLibrary.lua").exists():
        log(f"  ! {parent} already looks like a songs library")
        log(f"    writing to {songs_dir.resolve()} - use --songs-dir if that is not what you want")


# ----------------------------------------------------------------------- publish


def _publish_document(api: str, key: str | None, document: dict) -> tuple[bool, str]:
    """POST one document to the Masters lyrics API. Returns (ok, note)."""
    import urllib.error
    import urllib.request

    headers = {"Content-Type": "application/json"}
    if key:
        headers["x-masters-key"] = key
    request = urllib.request.Request(
        api.rstrip("/") + "/api/lyrics",
        data=json.dumps(document).encode("utf-8"),
        headers=headers,
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            payload = json.loads(response.read().decode("utf-8"))
            return bool(payload.get("ok")), str(payload.get("storage", ""))
    except urllib.error.HTTPError as exc:
        try:
            detail = json.loads(exc.read().decode("utf-8")).get("error", "")
        except Exception:
            detail = ""
        return False, f"HTTP {exc.code} {detail}".strip()
    except Exception as exc:
        return False, str(exc)


def cmd_publish(args) -> int:
    """Upload synced lyrics so every Masters player fetches them live."""
    saved = config.load()
    log = (lambda *a: None) if args.quiet else print

    if args.save and (args.api or args.key):
        config.save(api_url=args.api, publish_key=args.key)
        log(f"  saved defaults to {config.CONFIG_PATH}")

    api = (args.api or saved.get("api_url") or "").rstrip("/")
    key = args.key or saved.get("publish_key") or None
    if not api:
        print("error: no API url. Pass --api https://bestmusicplayer.vercel.app "
              "(add --save to remember it).", file=sys.stderr)
        return 2

    documents: list[tuple[str, dict]] = []
    if args.input:
        path = Path(args.input).expanduser()
        if not path.exists():
            print(f"error: file not found: {path}", file=sys.stderr)
            return 2
        text = path.read_text(encoding="utf-8-sig")
        try:
            if path.suffix.lower() == ".lua":
                parsed = luafmt.parse(text)
            else:
                data = json.loads(text)
                parsed = data if isinstance(data, list) else [data]
            documents = [(path.name, _normalise(d)) for d in parsed]
        except (ValueError, json.JSONDecodeError) as exc:
            print(f"error: could not read {path.name}: {exc}", file=sys.stderr)
            return 2
    else:
        songs_dir = Path(args.songs_dir).expanduser()
        for json_path in sorted(songs_dir.glob("*/*.json")):
            try:
                documents.append(
                    (json_path.parent.name, _normalise(json.loads(json_path.read_text(encoding="utf-8"))))
                )
            except (OSError, json.JSONDecodeError, ValueError) as exc:
                log(f"  ! skipped {json_path.name}: {exc}")
        if not documents:
            print(f"error: nothing to publish in {songs_dir}/*/*.json", file=sys.stderr)
            return 2

    log(f"\n  publishing {len(documents)} song(s) to {api}\n")
    failures = 0
    for name, document in documents:
        ok, note = _publish_document(api, key, document)
        if ok:
            log(f"  ok      {document['SoundId']:<18} {name}  ({note})")
        else:
            log(f"  FAILED  {document['SoundId']:<18} {name}  {note}")
            failures += 1
    log("")
    return 1 if failures else 0


# -------------------------------------------------------------------------- sync


def cmd_macos(args) -> int:
    """Add a song (and its lyrics) to macOS in Roblox Music on this PC."""
    if args.workspace:
        workspace = Path(args.workspace).expanduser()
        if not workspace.is_dir():
            print(f"error: no such folder: {workspace}", file=sys.stderr)
            return 2
        config.save(macos_workspace=str(workspace))
    library = macos.pc_music()

    if not args.audio:
        print(f"macOS in Roblox music library: {library or '(no Real workspace found; use --workspace PATH)'}")
        names = macos.categories(library)
        print("categories: " + (", ".join(names) if names else "(none yet)"))
        return 0
    if not args.category:
        print("error: pick a category with --category lofi (or lofi/chill)", file=sys.stderr)
        return 2

    audio = Path(args.audio).expanduser()
    if not audio.exists():
        print(f"error: audio file not found: {audio}", file=sys.stderr)
        return 2

    # Its lyrics: --lyrics, or what lyricsync wrote for it (songs/<name>/<name>.json,
    # next to the audio, or Lyric Studio's downloads/<id>.sync.json)
    lyrics_path = Path(args.lyrics).expanduser() if args.lyrics else None
    if lyrics_path is None:
        slug = songs.slugify(audio.stem)
        for candidate in (Path("songs") / slug / f"{slug}.json", audio.with_suffix(".json"),
                          audio.with_name(f"{audio.stem}.sync.json"), audio.with_name(f"{audio.stem}.lyrics.json")):
            if candidate.exists():
                lyrics_path = candidate
                break
    document = None
    if lyrics_path is not None:
        try:
            if lyrics_path.suffix.lower() == ".lua":
                document = luafmt.parse(lyrics_path.read_text(encoding="utf-8"))
            else:
                document = json.loads(lyrics_path.read_text(encoding="utf-8"))
        except Exception as exc:  # noqa: BLE001 - any bad lyrics file
            print(f"error: couldn't read the lyrics {lyrics_path}: {exc}", file=sys.stderr)
            return 2
        if isinstance(document, list):  # a whole library: take the first song
            document = document[0] if document else None
    cover = Path(args.cover).expanduser().read_bytes() if args.cover else None

    try:
        added = macos.add(
            args.category, audio, document,
            title=args.title or audio.stem, artist=args.artist or "", cover=cover, name=args.name,
            sound_id=(document or {}).get("SoundId") or None,
        )
    except macos.MacOSError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2
    print(f"added “{args.title or audio.stem}”" + (f" with {len(document['Lyrics'])} lyric lines" if document else " (no lyrics found)"))
    print(f"  {added['folder']}  (Music shows it within a few seconds)")
    return 0


def cmd_sync(args) -> int:
    saved = config.load()
    log = (lambda *a: None) if args.quiet else print

    audio_path = Path(args.audio).expanduser()
    if not audio_path.exists():
        print(f"error: audio file not found: {audio_path}", file=sys.stderr)
        return 2

    try:
        sound_id = audioutil.parse_sound_id(args.sound_id)
    except ValueError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2

    username = args.username or saved.get("username") or ""
    written_by = args.written_by or username
    synced_by = args.synced_by or username
    if not args.no_certification and not (written_by and synced_by):
        print("error: no username. Pass --user YourName (add --save to remember it).", file=sys.stderr)
        return 2

    try:
        duration = audioutil.probe_duration(audio_path)
    except audioutil.AudioError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2

    log(f"\n=== lyricsync {__version__} ===")
    log(f"  audio     {audio_path.name}  ({audioutil.format_timestamp(duration)})")
    log(f"  sound id  {sound_id}")

    backend = pick_backend(args.model or saved.get("model") or None, args.device)
    log(f"  engine    {backend.describe()}")

    source = audio_path
    mode = args.separate or saved.get("separate") or "auto"
    if mode == "always" or (mode == "auto" and separate.available()):
        try:
            source = separate.separate_vocals(audio_path, STEM_DIR)
        except Exception as exc:
            log(f"  ! vocal separation skipped: {exc}")
            source = audio_path

    words = _cached_words(source, audio_path, backend, args, duration, log)
    if not words:
        print("error: nothing was transcribed. Try --model large-v3, --separate always, or --no-vad.",
              file=sys.stderr)
        return 3

    opts = LineOptions(
        max_chars=args.max_chars,
        max_duration=args.max_duration,
        gap_split=args.gap,
        min_duration=args.min_duration,
        punctuation=args.punctuation,
        capitalize=args.capitalize,
    )

    if args.lyrics_file:
        reference = read_lyrics_file(args.lyrics_file)
        score = coverage(reference, words)
        log(f"  aligning  {len(reference)} lines from {Path(args.lyrics_file).name} "
            f"(word match {score * 100:.0f}%)")
        if score < 0.35:
            log("  ! low match - check that the lyrics file really is this song")
        lines = align_reference(reference, words, opts)
    else:
        lines = rebalance(group_words(words, opts), opts)

    if not lines:
        print("error: no lyric lines were produced.", file=sys.stderr)
        return 3

    document = roblox.build_document(
        sound_id,
        lines,
        duration,
        written_by=written_by,
        synced_by=synced_by,
        certification_template=args.cert_template,
        offset=args.offset,
        decimals=args.decimals,
        chain=not args.no_chain,
        align_mode=args.align,
        unsynced=args.unsynced,
        include_certification=not args.no_certification,
        gap_threshold=max(0.0, args.gap_lines),
    )

    # Either one explicit file (-o) or a folder in the songs library.
    slug = songs.slugify(args.name or audio_path.stem)
    songs_dir = Path(args.songs_dir).expanduser()
    explicit_json = None
    if args.out:
        explicit_json = Path(args.out).expanduser()
        folder, stem = explicit_json.parent, explicit_json.stem
        folder.mkdir(parents=True, exist_ok=True)
    else:
        _warn_if_nested(songs_dir, log)
        folder = songs.song_folder(songs_dir, slug)
        stem = slug

    log("")
    if not _safe_to_write(explicit_json or folder / f"{stem}.json", sound_id, args.overwrite):
        return 2
    _emit(document, folder, stem, fmt=args.fmt, pretty=args.pretty, ascii_only=args.ascii,
          log=log, json_path=explicit_json)

    if not args.no_txt and not args.lyrics_file:
        txt_path = folder / f"{stem}.lyrics.txt"
        header = (
            "# Corrected lyrics for lyricsync. One lyric line per text line.\n"
            "# Fix the words / move the line breaks, then re-run with:\n"
            f"#   lyricsync \"{audio_path.name}\" --id {sound_id} "
            f"--user {written_by or 'You'} --lyrics-file \"{txt_path}\"\n"
        )
        txt_path.write_text(header + "\n".join(line.text for line in lines) + "\n", encoding="utf-8")
        log(f"  editable transcript -> {txt_path}")

    if args.fmt in ("lua", "both") and not args.no_library and not args.out:
        library_path, count = songs.rebuild_library(songs_dir, args.library)
        log(f"  lua library         -> {library_path}  ({count} song{'s' if count != 1 else ''})")

    if args.publish:
        api = (saved.get("api_url") or "").rstrip("/")
        if not api:
            log("  ! --publish skipped: no API url saved. Run once:")
            log("      python -m lyricsync publish --api https://bestmusicplayer.vercel.app --save")
        else:
            ok, note = _publish_document(api, saved.get("publish_key") or None, document)
            log(f"  published           -> {api}  ({note})" if ok
                else f"  ! publish FAILED: {note}")

    if args.macos:
        try:
            added = macos.add(
                args.macos, audio_path, document,
                title=args.title or audio_path.stem, artist=args.artist or "", sound_id=sound_id,
            )
            log(f"  macOS Music         -> {added['folder']}")
        except macos.MacOSError as exc:
            log(f"  ! not added to macOS Music: {exc}")

    gaps = sum(1 for e in document["Lyrics"] if e["Id"].startswith("GAP_"))
    summary = f"{len(document['Lyrics'])} entries"
    if gaps:
        summary += f" ({gaps} instrumental gap{'s' if gaps != 1 else ''})"
    log(f"\n  {summary}, ending at {audioutil.format_timestamp(duration)}\n")
    log(roblox.preview(document, limit=12))
    log("")

    if args.save:
        config.save(username=username or None, model=args.model)
        log(f"  saved defaults to {config.CONFIG_PATH}\n")
    return 0


def _cached_words(source: Path, original: Path, backend: Backend, args, duration: float, log) -> list[Word]:
    engine = getattr(args, "engine", "auto")
    if engine == "groq" or (engine == "auto" and groqapi.available()):
        groq_key = "-".join([
            original.stem[:40],
            audioutil.fingerprint(original),
            "groq-large-v3-turbo",
            "sep" if source != original else "raw",
            args.language or "auto",
        ])
        groq_cache = CACHE_DIR / f"{_safe(groq_key)}.words.json"
        if not args.no_cache and not args.force and groq_cache.exists():
            try:
                payload = json.loads(groq_cache.read_text(encoding="utf-8"))
                words = [Word.from_dict(w) for w in payload["words"]]
                log(f"  cache     reusing {len(words)} words from an earlier Groq run (--force to redo)")
                _report_coverage(payload.get("meta", {}), duration, log)
                return words
            except Exception:
                pass
        try:
            log("  engine    Groq API (whisper-large-v3-turbo)")
            started = __import__("time").monotonic()
            words, meta = groqapi.transcribe_groq(
                source,
                original_path=original,
                language=args.language,
                initial_prompt=args.prompt,
                total_duration=duration,
                rescue_min=args.rescue_min,
            )
            log(f"  groq      {len(words)} words in "
                f"{__import__('time').monotonic() - started:.1f}s")
            log(f"  language  {meta['language']}")
            _report_coverage(meta, duration, log)
            if not args.no_cache and words:
                CACHE_DIR.mkdir(parents=True, exist_ok=True)
                groq_cache.write_text(
                    json.dumps({"meta": meta, "words": [w.to_dict() for w in words]}),
                    encoding="utf-8")
            return words
        except groqapi.GroqError as exc:
            if engine == "groq":
                print(f"error: {exc}", file=sys.stderr)
                return []
            log(f"  ! Groq failed ({exc}) - falling back to local whisper")

    key = "-".join(
        [
            original.stem[:40],
            audioutil.fingerprint(original),
            backend.model.replace("/", "_"),
            "sep" if source != original else "raw",
            args.language or "auto",
            f"b{args.beam_size}",
            "novad" if args.no_vad else "vad",
            "norescue" if args.no_rescue else f"r{args.rescue_min:g}",
            f"c{args.repeat_tolerance:g}",
        ]
    )
    cache_path = CACHE_DIR / f"{_safe(key)}.words.json"

    if not args.no_cache and not args.force and cache_path.exists():
        try:
            payload = json.loads(cache_path.read_text(encoding="utf-8"))
            words = [Word.from_dict(w) for w in payload["words"]]
            log(f"  cache     reusing {len(words)} words from an earlier run (--force to redo)")
            _report_coverage(payload.get("meta", {}), duration, log)
            return words
        except Exception:
            pass

    words, meta = transcribe(
        source,
        backend,
        language=args.language,
        initial_prompt=args.prompt,
        beam_size=args.beam_size,
        vad=not args.no_vad,
        total_duration=duration,
        progress=not args.quiet,
        rescue=not args.no_rescue,
        rescue_min=args.rescue_min,
        compression_threshold=args.repeat_tolerance,
    )
    log(f"  language  {meta['language']} (confidence {meta['language_probability']})")
    if meta.get("rescued"):
        log(f"  rescued   {meta['rescued']} words the first pass missed")
    _report_coverage(meta, duration, log)

    if not args.no_cache and words:
        CACHE_DIR.mkdir(parents=True, exist_ok=True)
        cache_path.write_text(
            json.dumps({"meta": meta, "words": [w.to_dict() for w in words]}), encoding="utf-8"
        )
    return words


def _report_coverage(meta: dict, duration: float, log) -> None:
    """Tell the user how much of the track actually produced words."""
    if duration <= 0:
        return
    coverage = float(meta.get("coverage") or 0.0)
    log(f"  coverage  words found across {coverage * 100:.0f}% of the track")

    spans = [tuple(s) for s in (meta.get("silent_spans") or [])]
    if not spans:
        return
    shown = ", ".join(f"{_clock(a)}-{_clock(b)}" for a, b in spans[:4])
    extra = f" (+{len(spans) - 4} more)" if len(spans) > 4 else ""
    log(f"  ! still nothing at {shown}{extra}")
    log("    instrumental? fine - they become GAP entries. If those parts are sung, try")
    log("    --separate always, then --rescue-min 5, then --no-vad")


def _clock(seconds: float) -> str:
    minutes, secs = divmod(max(0.0, float(seconds)), 60)
    return f"{int(minutes)}:{int(secs):02d}"


def _safe(name: str) -> str:
    return "".join(c if c.isalnum() or c in "-_." else "_" for c in name)
