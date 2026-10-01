#!/usr/bin/env bash
# Scans wine/rom/Steam libraries and prints a JSON array of games on stdout.
# Each entry: {name, platform, icon, launch:{type,...}}. No shell strings are
# built anywhere here — launch fields are plain data, concatenated into argv
# arrays by GamePicker.qml, so paths with apostrophes/spaces just work.
set -uo pipefail

WINE_DIR="$HOME/play/games"
ROMS_DIR="$HOME/play/roms"
STEAM_DIR="$HOME/.local/share/Steam/steamapps"
STEAM_LIBRARY_CACHE="$HOME/.local/share/Steam/appcache/librarycache"

declare -A CORE_FOR_PLATFORM=(
  [arcade]="mame"
  [snes]="snes9x"
  [n64]="mupen64plus_next"
  [gamecube]="dolphin"
  [gba]="mgba"
)
declare -A LABEL_FOR_PLATFORM=(
  [arcade]="Arcade"
  [snes]="SNES"
  [n64]="N64"
  [gamecube]="GameCube"
  [gba]="GBA"
)

entries=()

# pretty_name: strip extension, turn ./_ into spaces, trim
pretty_name() {
  local base="$1"
  base="${base%.*}"
  base="${base//[._]/ }"
  echo "$base" | sed -E 's/  +/ /g; s/^ +| +$//g'
}

# stable_pick <path> <n> — deterministic index in [0,n) from a hash of path
stable_pick() {
  local path="$1" n="$2"
  local h
  h="$(cksum <<<"$path" | cut -d' ' -f1)"
  echo $((h % n))
}

# icon_for_path <base-path-no-ext> — same-basename image, or a same-named
# folder of images (stable pick), else empty.
icon_for_path() {
  local base="$1"
  for ext in png jpg jpeg svg; do
    [[ -f "$base.$ext" ]] && { echo "$base.$ext"; return; }
  done
  if [[ -d "$base" ]]; then
    local imgs=()
    while IFS= read -r -d '' f; do imgs+=("$f"); done < <(find "$base" -maxdepth 1 -type f \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' \) -print0 2>/dev/null | sort -z)
    if [[ ${#imgs[@]} -gt 0 ]]; then
      echo "${imgs[$(stable_pick "$base" ${#imgs[@]})]}"
      return
    fi
  fi
  echo ""
}

add_entry() {
  # add_entry <json-object>
  entries+=("$1")
}

# --- Wine games: ~/play/games/<name>/ -------------------------------------
if [[ -d "$WINE_DIR" ]]; then
  while IFS= read -r -d '' dir; do
    name="$(basename "$dir")"
    exe=""
    best_size=-1
    while IFS= read -r -d '' candidate; do
      base="$(basename "$candidate")"
      [[ "$base" =~ [Cc]rash ]] && continue
      [[ "$base" =~ ^[Uu]nins ]] && continue
      [[ "$base" =~ ^[Ss]etup ]] && continue
      size="$(stat -c '%s' "$candidate" 2>/dev/null || echo 0)"
      if (( size > best_size )); then
        best_size="$size"
        exe="$candidate"
      fi
    done < <(find "$dir" -iname '*.exe' -print0 2>/dev/null)
    [[ -z "$exe" ]] && continue

    icon="$(icon_for_path "$dir/icon")"
    [[ -z "$icon" ]] && icon="$(icon_for_path "$dir/${name}")"

    entry="$(jq -n --arg name "$(pretty_name "$name")" --arg icon "$icon" \
      --arg dir "$dir" --arg exe "$exe" \
      '{name:$name, platform:"Wine", icon:$icon, launch:{type:"wine", dir:$dir, exe:$exe}}')"
    add_entry "$entry"
  done < <(find "$WINE_DIR" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null)
fi

# --- ROMs: ~/play/roms/<platform>/ -----------------------------------------
for platform in "${!CORE_FOR_PLATFORM[@]}"; do
  dir="$ROMS_DIR/$platform"
  [[ -d "$dir" ]] || continue
  core="${CORE_FOR_PLATFORM[$platform]}"
  label="${LABEL_FOR_PLATFORM[$platform]}"

  while IFS= read -r -d '' rom; do
    base="$(basename "$rom")"
    stem="${base%.*}"
    rom_dir="$(dirname "$rom")"
    name_sidecar="$rom_dir/$stem.name"

    if [[ -f "$name_sidecar" ]]; then
      name="$(head -n1 "$name_sidecar")"
    else
      name="$(pretty_name "$stem")"
    fi

    icon="$(icon_for_path "$rom_dir/$stem")"

    entry="$(jq -n --arg name "$name" --arg platform "$label" --arg icon "$icon" \
      --arg core "$core" --arg rom "$rom" \
      '{name:$name, platform:$platform, icon:$icon, launch:{type:"retroarch", core:$core, rom:$rom}}')"
    add_entry "$entry"
  done < <(find "$dir" -maxdepth 1 -type f \( -iname '*.zip' -o -iname '*.iso' -o -iname '*.rvz' \) -print0 2>/dev/null)
done

# --- Steam: owned + installed, from appmanifest_*.acf ----------------------
if [[ -d "$STEAM_DIR" ]]; then
  while IFS= read -r -d '' acf; do
    appid="$(grep -oP '"appid"\s*"\K[0-9]+' "$acf" | head -n1)"
    name="$(grep -oP '"name"\s*"\K[^"]+' "$acf" | head -n1)"
    installdir="$(grep -oP '"installdir"\s*"\K[^"]+' "$acf" | head -n1)"
    [[ -z "$appid" || -z "$name" ]] && continue
    [[ "$name" =~ ^Steam\ Linux\ Runtime ]] && continue
    [[ "$name" =~ ^Proton\  ]] && continue
    [[ "$name" == "Steamworks Common Redistributables" ]] && continue
    [[ "$name" == "SteamVR" ]] && continue

    full_install_dir="$STEAM_DIR/common/$installdir"
    icon=""
    header="$STEAM_LIBRARY_CACHE/$appid/header.jpg"
    [[ -f "$header" ]] && icon="$header"

    native=""
    if [[ -d "$full_install_dir" ]]; then
      while IFS= read -r -d '' bin; do
        native="$bin"
        break
      done < <(find "$full_install_dir" -maxdepth 1 -type f \( -iname '*.x86_64' -o -iname '*.x86' \) -print0 2>/dev/null)
    fi

    if [[ -n "$native" ]]; then
      entry="$(jq -n --arg name "$name" --arg icon "$icon" --arg dir "$full_install_dir" --arg bin "$native" \
        '{name:$name, platform:"Steam", icon:$icon, launch:{type:"native", dir:$dir, binary:$bin}}')"
    else
      entry="$(jq -n --arg name "$name" --arg icon "$icon" --arg appid "$appid" \
        '{name:$name, platform:"Steam", icon:$icon, launch:{type:"steam", appid:$appid}}')"
    fi
    add_entry "$entry"
  done < <(find "$STEAM_DIR" -maxdepth 1 -iname 'appmanifest_*.acf' -print0 2>/dev/null)
fi

# --- Minecraft: fixed entry, launched via its desktop file ------------------
if [[ -f "$HOME/.local/share/applications/minecraft-launcher.desktop" ]]; then
  entry="$(jq -n '{name:"Minecraft", platform:"Minecraft", icon:"", launch:{type:"desktop", id:"minecraft-launcher"}}')"
  add_entry "$entry"
fi

if [[ ${#entries[@]} -eq 0 ]]; then
  echo "[]"
else
  printf '%s\n' "${entries[@]}" | jq -s '.'
fi
