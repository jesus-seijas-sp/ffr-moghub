#!/bin/sh
# Build zzz_HideKeyGuide_P: the field key guide hidden for good, as a standalone pak (no UE4SS or MogHub) - the Field
# Kit's "Hide key guide" for players who want only that. The key guide widget (WBP_FieldFuncList2) is extracted, its
# root overlay and button grid set to Collapsed (their visibility, not the widget's own, which the game sets at times),
# and converted back to zen. Rerun after a game patch.
# Needs moghub/tools/downloads/retoc and moghub/extracted/Mappings.usmap (see moghub/tools/build_pak.sh).
# usage: plugins/fieldkit/tools/build_hidekeyguide.sh [game folder]     -> plugins/fieldkit/build/out/zzz_HideKeyGuide_P.*
set -e
export MSYS_NO_PATHCONV=1
cd "$(dirname "$0")/.."
FK=$(pwd -W 2>/dev/null || pwd)
GAME=${1:-"E:/SteamLibrary/steamapps/common/FINAL FANTASY RESONANCE"}
RETOC=../../moghub/tools/downloads/retoc/retoc.exe
USMAP=../../moghub/extracted/Mappings.usmap
TOOL=tools/hide-pak/bin/Release/net10.0/hide-pak.exe
ASSET=FFRS/Content/UI/Field/FuncButton/Widget/WBP_FieldFuncList2
[ -f "$TOOL" ] || dotnet build -c Release tools/hide-pak > /dev/null
rm -rf extracted/FFRS build && mkdir -p build/out
$RETOC to-legacy --version UE5_6 --no-shaders --no-script-objects -f WBP_FieldFuncList2 "$GAME/FFRS/Content/Paks" "$FK/extracted" > /dev/null
$TOOL hide "$FK/extracted" "$FK/build/pak" $ASSET Overlay_0,WBP_DirectionGridPanel --usmap $USMAP
$RETOC to-zen --version UE5_6 "$FK/build/pak" "$FK/build/out/zzz_HideKeyGuide_P.utoc" > build/retoc.log 2>&1
ls -la build/out
