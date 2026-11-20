# Lyric Studio and lyricsync

Part of [macOS in Roblox](../README.md): this is how you add songs with synced
lyrics to the Music app on your own PC.

* `lyricstudio.py` is the window: put in a Roblox music id, Download, Auto-Sync,
  fix lines, Preview, then **Add to macOS**.
* `lyricsync` (the `python -m lyricsync` command) does the syncing, and its
  `macos` command and `--macos CATEGORY` option add songs to Music.

## Adding songs to macOS Music

**Add to macOS** (or `--macos CATEGORY` / `python -m lyricsync macos`) copies the
audio into a category of your music library, `coolui_music` in Real's workspace
(`%LOCALAPPDATA%\Real\workspace`). It saves the lyrics next to the song as
`<title>.lyrics.json`, uses the Roblox thumbnail as its cover, and records the
title and artist in the category's `info.json`. Categories are folders, and
`lofi/chill` makes one inside another. Music shows the song within a few
seconds. It only ever writes to your PC.

```bash
python -m lyricsync song.mp3 --id 6910191685 --user You --macos lofi --title "Rainy Day" --artist Someone
python -m lyricsync macos song.mp3 --category dance --lyrics songs/song/song.json
python -m lyricsync macos            # lists your categories
```

For another executor, point it at that executor's workspace once:
`python -m lyricsync macos --workspace "C:\path\to\its\workspace"`. Music only
plays mp3, ogg and wav.

## Keys and the Roblox cookie

Keep them out of this folder (it's in a public repo):

* Groq API key: `%USERPROFILE%\.lyricsync\groq_key.txt` (or `GROQ_API_KEY`)
* `.ROBLOSECURITY` cookie, for downloading gated audio:
  `%USERPROFILE%\.lyricsync\roblosecurity.txt`. It's only ever sent to roblox.com.

Copies named `.groq_key.txt` / `.roblosecurity.txt` in this folder still work, and
`.gitignore` keeps them, the audio, `downloads/` and `songs/` out of git.

The "Synced By" name is your saved lyricsync username
(`python -m lyricsync song.mp3 --id … --user YourName --save`).

# lyricsync

Turn an `.mp3` plus a Roblox audio id into a timed Roblox lyrics JSON document.

```
song.mp3  +  6910191685  +  your username   ->   song.json
```

Everything runs locally with [faster-whisper](https://github.com/SYSTRAN/faster-whisper)
(the fastest free build of OpenAI's Whisper). No API key, no account, no upload limits,
no per-song cost. On this machine it uses the GPU automatically.

## Output

Exactly the shape the in-game lyric players expect:

```json
{"SoundId":6910191685,"Lyrics":[
  {"RightAligned":false,"Line":"first line here","Id":"L1","TimeStart":1.067,"TimeEnd":5.397,"Adlibs":[]},
  {"RightAligned":false,"Line":"second line here","Id":"L2","TimeStart":5.397,"TimeEnd":24.981,"Adlibs":[]},
  {"RightAligned":false,"Line":"Written By You\nSynced By @You","Id":"CERTIFICATION","TimeStart":50.941,"TimeEnd":59.488072562358279,"Adlibs":[]}
],"Unsynced":false}
```

and the Lua table, ready to drop into a ModuleScript (`--format lua`, on by default):

```lua
	["100847230469970"] = {
		SoundId = 100847230469970,
		Unsynced = false,
		Lyrics = {
			{Line = "first line here", TimeStart = 0.695, TimeEnd = 6.114, Id = "L1"},
			{Line = "second line here", TimeStart = 6.114, TimeEnd = 11.085, Id = "L2"},
			{Line = "", TimeStart = 11.085, TimeEnd = 24.433, Id = "GAP_3"},
			{Line = "Written By Them\nSynced By @You", TimeStart = 24.433, TimeEnd = 59.488072562358279, Id = "CERTIFICATION"},
		}
	},
```

Three conventions are reproduced from real files:

* **Lines are contiguous** - every `TimeEnd` is the next line's `TimeStart`, so exactly
  one line is on screen at any moment. Use `--no-chain` if your player wants true ends.
* **Instrumental breaks become blank `GAP_n` entries** so the overlay clears instead of
  holding the last line through a solo. The number is the entry's slot in the array, and
  lyric numbering ignores them (`L6`, `GAP_7`, `L7`). The threshold is `--gap-lines`
  (default 6 seconds, `0` turns it off).
* **The certification entry** runs from the last lyric to the raw, unrounded length of
  the audio file.

## Setup

Once:

```bat
setup.bat
```

or by hand:

```bash
python -m pip install -r requirements.txt
python -m pip install -e .
python -m lyricsync setup
```

`setup` installs faster-whisper, adds the CUDA runtime libraries, and downloads the
model. Check what it found any time with `python -m lyricsync doctor`.

`pip install -e .` also gives you a `lyricsync` command. On Windows that lands in
`%APPDATA%\Python\Python312\Scripts`, which is usually not on `PATH` - either add that
folder to `PATH` or keep using `python -m lyricsync`, which always works.

## Use

```bash
python -m lyricsync song.mp3 --id 6910191685 --user EpicTitan100
```

The id also accepts `rbxassetid://6910191685` or a full asset/library URL. Add `--save`
to remember your username so you never type it again.

Everything lands in a `songs/` library folder, one directory per song:

```
songs/
  LyricsLibrary.lua          every song in one ModuleScript, rebuilt on each run
  my-song/
    my-song.json             the Roblox JSON document
    my-song.lua              just the ["id"] = { ... } entry, for pasting
    my-song.lyrics.txt       the transcript, one lyric line per line, for editing
```

`--songs-dir path/to/folder` moves the library, `--name` overrides the folder name, and
`--format json` or `--format lua` writes only one of the two. `-o file.json` bypasses the
library entirely and writes a single file where you point it.

`LyricsLibrary.lua` is regenerated from the `.json` files on disk every run, so deleting
a song folder removes it from the module. In Roblox:

```lua
local Lyrics = require(script.LyricsLibrary)
local song = Lyrics[tostring(sound.SoundId)]
for _, entry in ipairs(song.Lyrics) do
	-- entry.Line, entry.TimeStart, entry.TimeEnd, entry.Id
end
```

### The two-pass workflow (this is the good part)

Whisper is very good at knowing **when** each word is sung and only decent at knowing
**what** the words are. So: run it once, fix the text, run it again.

1. `python -m lyricsync song.mp3 --id 6910191685 --user You`
2. Open `songs/song/song.lyrics.txt`. Fix misheard words, and move the line breaks to
   wherever you want lines to split on screen. `[Chorus]` markers, `#` comments and blank
   lines are ignored.
3. Re-run with your file:

```bash
python -m lyricsync song.mp3 --id 6910191685 --user You --lyrics-file songs/song/song.lyrics.txt
```

Your wording and your line breaks are kept; the timings are taken from the audio by
matching your words against what was actually heard. The run prints a word-match
percentage - under ~35% usually means the lyrics file is for a different song or a
different version of the track.

Re-running is cheap: the recognised words are cached, so pass two takes a second or two.
`--force` re-transcribes.

### Editing the Lua instead

The `.lua` file is the easier one to read, so fixing lines there is often quicker. Convert
it back when you are done:

```bash
python -m lyricsync convert songs/my-song/my-song.lua
```

That reads either a single `["id"] = { ... }` entry or a whole `LyricsLibrary.lua`, writes
the JSON and a tidied Lua back into the songs folder, and rebuilds the library. It runs in
both directions - hand it a `.json` and you get the Lua out. `--name` picks the folder,
`-o` writes a single file wherever you point it, and `-` reads a table pasted on stdin.

Timings, ids, `Unsynced`, `RightAligned`, `GAP` entries and the certification's newline all
survive the round trip byte for byte.

## Groq API engine (fast path)

Put a Groq API key in `%USERPROFILE%\.lyricsync\groq_key.txt` (or set `GROQ_API_KEY`)
and every sync automatically uses Groq's hosted `whisper-large-v3-turbo` - a full
song transcribes in under a second instead of minutes, word timestamps included,
for ~$0.002 per song (free tier works too). `--engine local` forces the local GPU,
`--engine groq` errors instead of falling back. Any API failure falls back to the
local engine automatically. Separated vocal stems over the 24MB upload cap are
swapped for the original compressed file. `doctor` shows whether a key was found.

## Getting the best accuracy

1. **Isolate the vocals.** By far the biggest win on real music - Whisper was trained on
   speech, not on a full mix.

   ```bash
   python -m lyricsync setup --demucs
   python -m lyricsync song.mp3 --id 123 --user You --separate always
   ```

   Once demucs is installed it is used automatically (`--separate never` to skip it).
   Stems are cached in `~/.lyricsync/stems`.

2. **Keep the big model.** `large-v3` is the default on a CUDA GPU. On CPU the default
   drops to `medium`; `--model large-v3` still works, it is just slow.
3. **Give it hints** for names or stylised spellings: `--prompt "Names: Kai, Nyx"`.
4. **Nudge the timing** if your player is consistently early or late: `--offset -0.15`.

### When whole sections go missing

Whisper drops parts of songs for two reasons, and lyricsync works around both.

A chorus sung six times in a row looks like a stuck decoder, so Whisper's
anti-repetition check throws those segments away - which is how the last thirty seconds
of a song quietly disappear. lyricsync raises that limit (`--repeat-tolerance`, default
3.0 against Whisper's stock 2.4). Songs with very repetitive outros can go higher still.

Then anything the first pass left empty gets a **second pass on its own**: each silent
stretch longer than `--rescue-min` (default 10s) is decoded separately with a far more
sensitive voice detector, and the recovered words are merged back in. Rescued segments
are vetted first, so instrumental breaks do not fill up with "thanks for watching".
`--no-rescue` turns it off.

Every run ends with a coverage line:

```
  rescued   14 words the first pass missed
  coverage  words found across 78% of the track
  ! still nothing at 2:41-3:12
```

That last warning is the one to read. If those seconds really are instrumental, they
become GAP entries and all is well. If they are sung, escalate: `--separate always`,
then `--rescue-min 5`, then `--repeat-tolerance 5`, then `--no-vad`. Whatever is still
wrong after that, fix in the `.lyrics.txt` and re-run with `--lyrics-file` - the words
come from your file and the timing you already liked is kept.

## Options

`python -m lyricsync --help` has everything; the ones that matter:

| flag | default | what it does |
| --- | --- | --- |
| `--id` | required | Roblox audio id, `rbxassetid://…`, or an asset URL |
| `--user NAME` | saved value | fills the certification line |
| `--save` | off | remember `--user` / `--model` for next time |
| `-o PATH` | next to the audio | where to write the JSON |
| `--lyrics-file F` | – | align to your corrected lyrics instead of the raw transcript |
| `--format` | `both` | `json` / `lua` / `both` |
| `--songs-dir D` | `songs` | where the library folder lives |
| `--name SLUG` | from filename | folder name for this song |
| `--library F` | `LyricsLibrary.lua` | combined ModuleScript file name |
| `--no-library` | off | skip regenerating the combined ModuleScript |
| `--overwrite` | off | allow writing into a folder that holds a different song |
| `--gap-lines S` | 6.0 | blank `GAP_n` entry for breaks longer than S seconds (`0` off) |
| `--separate` | `auto` | `auto` / `always` / `never` vocal isolation |
| `--model M` | `large-v3` on GPU | whisper model |
| `--language en` | auto-detect | skip detection, or force a language |
| `--repeat-tolerance R` | 3.0 | how repetitive a segment may be before Whisper rejects it |
| `--rescue-min S` | 10.0 | silent stretch length that earns a second pass |
| `--no-rescue` | off | skip the second pass entirely |
| `--max-chars N` | 42 | how wide a line may get |
| `--max-duration S` | 7.0 | how long a line may stay up |
| `--gap S` | 0.7 | silence that starts a new line |
| `--min-duration S` | 0.9 | fold blink-length lines into a neighbour |
| `--punctuation` | `soft` | `keep` / `soft` (drop trailing dots) / `strip` |
| `--capitalize` | off | force a capital at the start of every line |
| `--align` | `none` | `alternate` / `all` to set `RightAligned` |
| `--offset S` | 0 | shift every timestamp |
| `--no-chain` | off | keep true line ends instead of holding to the next line |
| `--unsynced` | off | mark the document `Unsynced` |
| `--pretty` | off | indent the JSON while you are eyeballing it |
| `--no-certification` | off | leave the certification entry out |
| `--force` | off | ignore the cached transcription |

Ad-libs are always written as `[]`; add them by hand if your player uses them.

## Layout

```
lyricsync/
  cli.py         argument parsing and the pipeline
  transcribe.py  faster-whisper -> timed words
  separate.py    optional demucs vocal isolation
  lines.py       words -> display-sized lines (gaps, width, runt merging)
  align.py       your corrected lyrics + whisper timings -> lines
  roblox.py      lines -> the document, including the GAP entries
  luafmt.py      document <-> Lua table / ModuleScript (writes and parses)
  songs.py       the songs/ folder and the combined library
  macos.py       adds songs and lyrics to macOS in Roblox Music on this PC
  audioutil.py   duration probing, sound-id parsing
  gpu.py         finds the pip-installed CUDA DLLs on Windows
tests/           31 checks, no audio or model needed
```

```bash
python tests/test_lyricsync.py
```

Working files live in `~/.lyricsync`: `config.json`, `cache/` (transcribed words) and
`stems/` (separated vocals). Deleting any of them is safe.

## Troubleshooting

**"nothing was transcribed"** - the track is probably instrumental-heavy. Try
`--separate always`, then `--no-vad`, then `--model large-v3`.

**Lines drift out of sync late in the song** - almost always a different cut of the track
(radio edit vs album). Check the intro length, then use `--offset`.

**Repeated or invented lines in an instrumental break** - Whisper hallucinating over
silence. Vocal separation fixes most of it.

**A whole section is missing** - check the coverage warning at the end of the run, then
see "When whole sections go missing" above.

**CUDA errors / it fell back to CPU** - run `python -m lyricsync doctor`. If `cuda
devices` is 0, reinstall the runtime with
`python -m pip install nvidia-cublas-cu12 "nvidia-cudnn-cu12>=9,<10"`.

**Vocal separation is slow** - demucs uses whatever torch you have. A CPU-only torch
(`python -c "import torch; print(torch.version.cuda)"` prints `None`) means minutes per
song. Swapping in the CUDA build makes it roughly ten times faster, but it replaces torch
for every project in this Python install:

```bash
python -m pip install --force-reinstall torch torchaudio --index-url https://download.pytorch.org/whl/cu124
```

**It is slow on CPU** - expect several minutes per song with `medium`. Use
`--model small` for a quick draft pass, then re-run the good model later.

Only sync audio you have the rights to use, and follow Roblox's rules for the games you
put it in.
