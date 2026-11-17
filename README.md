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
  deletes the downloaded and generated assets and gets each one again, saying
  which file it's on ("Downloading music 1/2 · loadingsuccess.mp3")
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
- Finder (browses the executor's workspace folder), Notes, Terminal (shell
  commands plus Luau), Music, System Settings and Preview
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
```

The script downloads each asset once and caches it in the executor's
workspace (`coolui_music/` and `coolui_assets/`), so later runs don't download
again. Notes saves to `coolui_assets/Notes.txt`, and any mp3 you put in
`coolui_music/` shows up in Music. Settings (appearance, the startup screen,
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
