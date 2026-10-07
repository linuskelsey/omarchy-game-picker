# Game picker

Native Quickshell overlay plugin. Replaces the old walker/elephant-based
game launcher (purged by the quattro upgrade). Press `SUPER CTRL G` to
open a single searchable list of every game across wine, ROMs, Steam,
and Minecraft; type to filter, arrow keys + Enter (or click) to launch.

## How it works

- `bin/scan.sh` walks `~/play/games` (wine), `~/play/roms/<platform>`
  (arcade/snes/n64/gamecube/gba, launched via the matching RetroArch
  core), and `~/.local/share/Steam/steamapps/appmanifest_*.acf` (owned +
  installed Steam titles, with a native-Linux-binary bypass for titles
  Steam insists on Proton-wrapping anyway), plus a fixed Minecraft entry.
  It prints a JSON array of `{name, platform, icon, launch}` — launch is
  plain data (type + fields), never a shell string.
- `GamePicker.qml` runs `scan.sh` fresh on every open (via `Process` +
  `StdioCollector`), filters the result as you type (`GameSearch.js`),
  and launches the selection with `Quickshell.execDetached([...])` using
  a plain argv array. No shell is invoked for launching, so names/paths
  with spaces or apostrophes (`Baldur's Gate`) need no escaping anywhere.
- `bin/launch-wine.sh` / `bin/launch-native.sh` only exist because those
  two cases need a `cd` into the game directory first; everything else
  (`retroarch`, `steam -applaunch`, `gtk-launch`) is called directly.

## Gamepad / IPC control

The plugin exposes an `IpcHandler` with target `game-picker`, so anything
(e.g. a DualSense daemon) can drive it without synthetic key events:

```
omarchy-shell game-picker open | close | toggle | isOpen
omarchy-shell game-picker move <+1|-1>     # wraps
omarchy-shell game-picker page <+1|-1>     # clamped, ~one screenful
omarchy-shell game-picker activate         # launch highlighted entry
```

The overlay's layer-shell namespace is `prometheus-game-picker`, which is
what an external controller can poll via `hyprctl layers -j` to know when
the picker has closed. After editing the QML, restart the shell
(`omarchy-restart-shell`) for the handler to reload.

## Installing

Source of truth lives here (`~/projects/QML/game-picker`). The shell
loads plugins from `~/.config/omarchy/plugins/<id>/`, so that path is a
symlink back to this directory — same pattern as forked third-party
plugins living in `~/projects/OPEN_SRC`.

Keybind: `~/.dotfiles/hypr/.config/hypr/bindings.lua` —
`o.bind("SUPER CTRL G", nil, "omarchy-shell shell toggle prometheus.game-picker")`.

## Adding icons

Highest priority: `icons/pixel/<Exact Game Name>.png` — a curated
override checked before any convention-based lookup, for every
platform including Steam/Minecraft (which have no other icon slot).

This is how the current set was made: drop source key-art into
`icons/source/<Exact Game Name>.<ext>` (gitignored, not needed at
runtime — for Minecraft this was its `.desktop` entry's icon, rasterized
with `rsvg-convert`), then run `bin/crop-and-pixelate.py`. It
center-crops each source to a square (side = the shorter dimension —
landscape key-art crops to its height, portrait crops to its width) and
runs it through [pyxelator](https://github.com/linuskelsey/pixelator)
at a 128px grid, matching the pixel-art look of the overlay. Requires
pyxelator checked out as a sibling repo at `~/projects/PYTHON/pyxelator`.

Without an override, wine/rom entries fall back to the old convention:
drop an image with the rom/exe's base name next to it (`sf2.png` next
to `sf2.zip`), or a same-named folder of images (one gets picked
deterministically by path hash). MAME/arcade roms can't be renamed
(matches driver shortname), so use a `<base>.name` sidecar text file
for the display name instead.
