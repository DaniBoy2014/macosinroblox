# macOS in Roblox (coolui)

A Lithora-style loader UI for Roblox executors: a shop screen with an HD Admin
rank viewer, and a "Load macOS" button that boots into a macOS Tahoe-style lock
screen with Liquid Glass.

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
```

The script downloads each asset once and caches it in the executor's
workspace (`coolui_music/` and `coolui_assets/`), so later runs don't download
again. If a file is missing from this repo, the script falls back to its old
download source.

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
