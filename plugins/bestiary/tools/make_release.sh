#!/bin/sh
# Assemble the release zip: a folder tree to extract into the game folder, holding the plugin's own files only -
# no scripts, no programs, no pak (MogHub provides the menu entry; players install MogHub and UE4SS themselves;
# Nexus quarantines .bat/.ps1/.exe).
set -e
cd "$(dirname "$0")/.."
VERSION=$(sed -n 's/^Version *= *//p' runtime/FFRBestiary/moghub.ini | tr -d '\r')
D=dist/FFRBestiary
M=$D/FFRS/Binaries/Win64/ue4ss/Mods/FFRBestiary
rm -rf dist && mkdir -p $M/Scripts
cp runtime/FFRBestiary/moghub.ini runtime/FFRBestiary/moghub.lua $M/
cp runtime/FFRBestiary/Scripts/*.lua data/bestiary_data.lua $M/Scripts/
cp release/README.txt $M/README.txt
# a MogHub plugin: UE4SS itself must not load it (that is MogHub's job)
if [ -e $M/enabled.txt ] || [ -e $M/Scripts/main.lua ]; then echo "ERROR: enabled.txt / main.lua in $M" >&2; exit 1; fi
# nothing executable may slip in
if find $D -type f | grep -iqE '\.(bat|cmd|ps1|exe|dll|vbs|js)$'; then echo "ERROR: executable file in $D" >&2; exit 1; fi
rm -f dist/FFRBestiary-$VERSION.zip
# zip with forward slashes (Windows PowerShell's Compress-Archive writes backslashes, which some tools mishandle)
python -c "
import os, sys, zipfile
root, out = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as z:
    for d, _, files in os.walk(os.path.join(root, 'FFRS')):
        for f in sorted(files):
            full = os.path.join(d, f)
            z.write(full, os.path.relpath(full, root).replace(os.sep, '/'))
" $D dist/FFRBestiary-$VERSION.zip
find $D -type f | sed "s|^$D/||"
ls -la dist/FFRBestiary-$VERSION.zip
