#!/bin/sh
# Development: install MogHub, its menu pak and every plugin in plugins/ into the game.
# usage: tools/deploy.sh [game folder]     (Debug = 1 in a newly installed MogHub config.ini)
set -e
cd "$(dirname "$0")/.."
GAME=${1:-"E:/SteamLibrary/steamapps/common/FINAL FANTASY RESONANCE"}
MODS="$GAME/FFRS/Binaries/Win64/ue4ss/Mods"
PAKS="$GAME/FFRS/Content/Paks/~mods"

# MogHub: the only UE4SS mod, and its menu pak (built by moghub/tools/build_pak.sh)
mkdir -p "$MODS/MogHub/Scripts/kit" "$PAKS"
cp moghub/runtime/MogHub/Scripts/main.lua "$MODS/MogHub/Scripts/"
cp moghub/runtime/MogHub/Scripts/kit/*.lua "$MODS/MogHub/Scripts/kit/"
mkdir -p "$MODS/MogHub/lang" && cp moghub/runtime/MogHub/lang/*.ini "$MODS/MogHub/lang/"
[ -f "$MODS/MogHub/config.ini" ] || sed 's/^Debug = 0/Debug = 1/' moghub/runtime/MogHub/config.ini > "$MODS/MogHub/config.ini"
touch "$MODS/MogHub/enabled.txt"
for f in moghub/build/out/zzz_MogHub_P.*; do          # only when changed: the running game locks it
    cmp -s "$f" "$PAKS/$(basename "$f")" || cp "$f" "$PAKS/"
done

# plugins: each plugins/<name>/runtime/<Folder> holds moghub.ini, moghub.lua and optional Scripts/*.lua; a
# plugin's data/*.lua goes into its Scripts too (bestiary_data.lua)
for dir in plugins/*/runtime/*/; do
    [ -f "$dir/moghub.lua" ] || continue
    name=$(basename "$dir")
    mkdir -p "$MODS/$name/Scripts"
    cp "$dir"moghub.* "$MODS/$name/"
    if [ -d "$dir"lang ]; then mkdir -p "$MODS/$name/lang"; cp "$dir"lang/*.ini "$MODS/$name/lang/"; fi
    for f in "$dir"Scripts/*.lua "$dir"../../data/*.lua; do
        [ -f "$f" ] && cp "$f" "$MODS/$name/Scripts/"
    done
done
ls "$MODS" "$PAKS"
