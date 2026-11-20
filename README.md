# macOS in Roblox (coolui)

A Lithora-style loader UI for Roblox executors: a shop screen with an HD Admin
rank viewer, and a "Load macOS" button that boots into a macOS Tahoe-style lock
screen with Liquid Glass, then a desktop:

- a menu bar with the Apple menu (About This Mac, System Settings, Sleep,
  Restart, Shut Down, Lock Screen, Log Out) and per-app menus
- Sleep hides macOS so you can play the game; "Wake macOS" at the top of the
  screen brings it back to the lock screen. Its "Keep apps running" option
  keeps the music playing while it's asleep
- Restart and Shut Down ask first (60-second countdown, like a Mac) and can
  reopen your windows afterwards, even after Shut Down
- a startup screen (Apple logo, progress bar and the startup chime) on Restart
  and the first time macOS starts; System Settings > General can show it every
  time. Logging in plays the Mac's log-in sound
- Redownload (System Settings > General): restarts into the startup screen,
  downloads the music, sounds and clock font again and remakes every glass
  image, saying which file it's on ("Downloading music 1/2 ·
  loadingsuccess.mp3"). A downloaded file is only replaced once its new copy
  has arrived, so a failed download never leaves you without it
- Light and Dark appearance (System Settings > Appearance)
- Spotlight (the menu bar's magnifier or Ctrl+Space): a dark Liquid Glass
  "Search or Ask" bar with a glowing cursor that finds apps, settings,
  actions, files in the workspace, and works out sums
- Ask: with your own Claude API key (System Settings > Ask), Spotlight sends
  your question to Claude Opus 5.5. While it works, the bar turns into a
  "Working" pill with a spinning ring of dots that soon names what you asked
  about, and a rainbow glow runs around the screen's edges. The answer and the
  bar then become one card (headings, lists, the sites it searched) with a
  ripple of light spreading through it, and you can ask follow-ups from its
  bottom row. Claude can search the web and use the desktop: open apps,
  arrange windows, read, write and open files in the workspace, play music and
  change settings (Sleep, Restart and Shut Down still ask you first)
- Wi-Fi and battery menus in Liquid Glass: the "network" is the game you're
  in, its signal bars follow your ping, and the battery shows as unknown
  (Roblox can't read it)
- a Liquid Glass Dock; over the live 3D scene the glass is redrawn as the
  camera moves
- windows you can drag, stretch by their edges and corners, zoom, minimize to
  the Dock and close; their red, yellow and green buttons stretch like jelly
  when you pull on them
- Finder (browses the executor's workspace folder), Notes, Chat, Terminal
  (shell commands plus Luau), Music, YouTube, Timer, System Settings and
  Preview
- Chat: the game's own chat in a window (Roblox's chat window stays hidden):
  the server channel, Roblox's Global chat (everyone playing the game, in any
  server) when Roblox has it on, team chat when the game has teams, and
  private whispers. Type "/w name message" with a username or a display name, or pick
  someone from the + list. It goes through Roblox's chat, so its filter and
  rules apply; whispers you get while Chat is in the background show a
  banner. Some games turn typing in chat off, and Chat says so
- Music: a library built from folders. `coolui_music/` is the library, every
  folder in it is a category (lofi, fun and dance come from this repo), and
  categories can hold more categories. Each one can have an `info.json` with
  its title, picture and description (see "The music library" below). The
  sidebar shows the tree, each category has a page with its cover, Play,
  Shuffle and its songs, and changes to the folders show up by themselves.
  Every start and Restart checks this repo's `music/` folder and downloads
  new songs and categories, with a banner saying what arrived. Ask can play a
  song or a whole category ("play some lofi")
- Timer: a countdown with a ring that empties as it runs (it chimes and shows
  a banner when it's done) and a stopwatch with laps. Ask can start timers
- YouTube: search, Home, Shorts and Live tabs, and real playback of videos
  (seek, pause), Shorts (upright, with next and previous) and live streams,
  with sound. Paste a YouTube link to play it. Needs the YouTube helper
  running on your PC (see below)
- a background switch between the Tahoe wallpaper and the 3D scene
- anti-AFK while it's open, so Roblox's 20-minute idle kick doesn't end it

## Run it

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/DaniBoy2014/macosinroblox/main/coolui.lua"))()
```

## Repo layout

```
coolui.lua                    the script
assets/music/loadingsuccess.mp3   sound when the loader finishes
assets/music/shopmusic.mp3        looping shop music
assets/fonts/Inter-Bold.ttf       outlines for the Liquid Glass clock
assets/fonts/OFL.txt              Inter's license (must stay next to the font)
assets/sounds/startup_chime.wav   the startup chime (startup screen)
assets/sounds/volume_mount.wav    the log-in sound
music/                            the music library everyone gets (see below)
  lofi/info.json, fun/info.json, dance/info.json
youtube_helper.py                 the YouTube helper (runs on your PC)
```

The script downloads each asset once and caches it in the executor's
workspace (`coolui_music/` and `coolui_assets/`), so later runs don't download
again. Notes saves to `coolui_assets/Notes.txt`, and any mp3, ogg or wav you
put in `coolui_music/` (or a category folder in it) shows up in Music. Settings (appearance, the startup screen,
windows to reopen) are kept in `coolui_assets/settings.json`. If a file is
missing from this repo, the script falls back to its old download source.

The Claude API key for Ask is saved as plain text in
`coolui_assets/claude_api_key.txt` (never in settings.json). It's only sent to
`api.anthropic.com`, Settings shows just its first and last characters, and
Claude's file tools can't read it. Requests use Anthropic's server-side
fallback, so a declined request can be retried on a fallback model, and every
request is billed to your Anthropic account: each question is one or more
Claude Opus 5.5 calls plus a tiny Claude Haiku 5.5 call that names the topic
for the Working pill, and web searches cost about a cent each (System
Settings > Ask can turn searching and desktop control off).

## The music library

### Adding music for everyone (this repo)

This repo's `music/` folder is the shared music tree. It's laid out exactly
like `coolui_music/` below: a folder per category, each with an `info.json`,
and the songs (mp3, ogg or wav) and pictures inside. To add music:

1. Put the songs in a category folder, like `music/lofi/rainy day.mp3`, or
   make a new folder with its own `info.json` for a new category (folders
   inside folders work too).
2. Commit and push.

Every time macOS starts (Load macOS) or restarts, it asks GitHub what's in
`music/` (one request) and downloads only what's new or changed into
`coolui_music/`, showing "Adding new music 1 of 3" on the loading or restart
screen. Once the desktop is up, a banner says what arrived ("2 new songs in
Lofi"). Click it to open Music.

- Songs people add to their own `coolui_music/` stay. Nothing is ever deleted
  there, even when a file is removed from the repo.
- A file from the repo that someone deletes locally stays deleted, until it
  changes in the repo or they use System Settings > General > Redownload
  (which gets the whole library again).
- When a file changes in the repo (an edited `info.json`, say), the new
  version replaces the local copy. Make shared changes here rather than in
  `coolui_music/`.
- What came from GitHub is remembered in `coolui_assets/music_library.json`.
- GitHub allows 60 of these checks an hour from one network. If it says no,
  macOS starts anyway and checks again next time.
- GitHub takes files up to 100 MB, but big songs take longer on the first
  start after they're added.

### The folders

Music reads its library from folders in the executor's workspace:

```
coolui_music/
  info.json           (optional) the library's own title and description
  lofi/
    info.json
    cover.png         found by itself if info.json doesn't name a picture
    rainy day.mp3
    rainy day.png     a picture named like a song is that song's cover
    chill/            a category inside a category
      info.json
      coffee.mp3
  fun/
  dance/
```

Each category's `info.json` says how it looks. Every key is optional, and a
folder without one is still a category (named after the folder):

```json
{
  "title": "Lofi",
  "description": "Slow, warm beats to study, read or relax to.",
  "image": "cover.png",
  "color": "#8E5CF7",
  "artist": "Various Artists",
  "genre": "Lofi Hip-Hop",
  "year": 2026,
  "shuffle": false,
  "volume": 0.8,
  "songs": {
    "rainy day.mp3": {"title": "Rainy Day", "artist": "Lo-Fi Kid", "image": "rain.png", "volume": 0.6}
  }
}
```

- `title`, `description`: shown on the category's page and in the sidebar.
- `image`: a picture in the category's folder, a path in the workspace, an
  `rbxassetid://` id, or an `https://` link to a PNG or JPEG (downloaded once
  and kept in `coolui_assets/music_covers/`). Without one, the cover is the
  category's `color` with its first letter.
- `artist`: the songs' artist unless a song gives its own (categories inside
  it inherit it).
- `genre`, `year`: shown under the title.
- `shuffle`: Play shuffles this category.
- `volume`: 0 to 1 (up to 2 for quiet files), for every song in the category.
- `songs`: a song's title, artist, picture and volume, by file name. It can
  also be a list, `[{"file": "rainy day.mp3", "title": "Rainy Day"}, …]`,
  which then sets the order (otherwise it's by file name).

New Category (in the sidebar) makes a folder with a ready-to-fill `info.json`
inside the category you're looking at and opens it in Notes. The info button
on a category's page opens its `info.json`, and if the file isn't valid JSON
the page says so. Play on a category plays everything in it, its
subcategories included.

## The YouTube helper

Roblox can't play video on its own (it won't load a video file a script
saves), and YouTube won't give a game its streams. So the YouTube app gets
its pictures and sound from a small program on your PC, `youtube_helper.py`,
which uses yt-dlp to find and download videos and ffmpeg to decode them.
Only your own PC can reach it (it listens on `127.0.0.1:8765`).

1. Install Python 3.9 or newer, and ffmpeg (it has to be on your PATH).
2. `pip install -U yt-dlp`
3. Download `youtube_helper.py` from this repo and run
   `python youtube_helper.py`. Leave it open while you watch.

Videos show at 480×270 (Shorts at 270×480) and 24 frames a second. A video
takes a few seconds to start; a live stream plays about 7 seconds behind
live. Thumbnails are saved in `coolui_youtube/` in the executor's workspace.
If YouTube changes something and videos stop playing, update yt-dlp
(`pip install -U yt-dlp`).

## Using a different repo name

At the top of `coolui.lua`:

```lua
local ASSET_REPO = "DaniBoy2014/macosinroblox"
local ASSET_BRANCH = "main"
```

Change these to match your repo and branch, and update the `loadstring` link
above.

## What isn't downloaded

These are made at runtime, so they don't need to be in the repo:

- the soft glow image used for the wallpaper (generated as a PNG)
- every Liquid Glass shape and clock digit (rendered once against the
  wallpaper, then cached)
- the glass over the 3D scene (drawn live from the scene's skybox)
- the icons (Roblox asset ids from the Lucide icon set)

## Optional: your own lock screen wallpaper

Put an image in `assets/images/` and set `MACOS_WALLPAPER_URL` in `coolui.lua`
to its raw link. With a custom image the glass falls back to a frosted look,
because the glass is rendered against the built-in wallpaper.

## Credits

- Liquid Glass math (refraction, fresnel, glare) follows boatbomber's
  [GlassmorphicUI](https://github.com/boatbomber/GlassmorphicUI) (MPL-2.0);
  this script renders it once per shape instead of every frame.
- Clock font: [Inter](https://github.com/rsms/inter) by The Inter Project
  Authors, SIL Open Font License 1.1 (see `assets/fonts/OFL.txt`).
- Icons: [Lucide](https://lucide.dev) (ISC license), via their Roblox uploads.
