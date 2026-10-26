#!/bin/sh
# Build the menu pak (zzz_MogHub_9_P): extract the two game tables, add MogHub's rows, convert back to zen.
# The _9_ ranks it above other paks that replace the same tables, such as FFR Bestiary's zzz_FFRBestiary_P: the
# engine gives a pak named ..._<n>_P the priority of patch n.
# Needs tools/downloads/retoc (github.com/trumank/retoc), tools/downloads/uassetapi (github.com/atenfyr/UAssetAPI)
# and extracted/Mappings.usmap (UE4SS DumpUSMAP, see docs/BUILDING.md). Rerun after a game patch.
# usage: tools/build_pak.sh [game folder]
set -e
export MSYS_NO_PATHCONV=1
cd "$(dirname "$0")/.."
GAME=${1:-"E:/SteamLibrary/steamapps/common/FINAL FANTASY RESONANCE"}
RETOC=tools/downloads/retoc/retoc.exe
TOOL=tools/menu-pak/bin/Release/net10.0/menu-pak.exe
[ -f "$TOOL" ] || dotnet build -c Release tools/menu-pak > /dev/null
rm -rf extracted/FFRS build/pak build/out && mkdir -p build/out
for t in DT_MainMenuScene DM_DT_GameplayTag_Option; do
    $RETOC to-legacy --version UE5_6 --no-shaders --no-script-objects -f $t "$GAME/FFRS/Content/Paks" extracted > /dev/null
done
$TOOL extracted build/pak --usmap extracted/Mappings.usmap
$RETOC to-zen --version UE5_6 build/pak build/out/zzz_MogHub_9_P.utoc > build/retoc.log 2>&1
ls -la build/out
