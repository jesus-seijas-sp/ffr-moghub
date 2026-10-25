#!/bin/sh
# Assemble the release zip: a folder tree to extract into the game folder, holding the plugin's own files only -
# no scripts, no programs, no pak (MogHub provides the menu entry; players install MogHub and UE4SS themselves;
# Nexus quarantines .bat/.ps1/.exe).
set -e
cd "$(dirname "$0")/.."
VERSION=$(sed -n 's/^Version *= *//p' runtime/MogHubBestiary/moghub.ini | tr -d '\r')
D=dist/MogHubBestiary
M=$D/FFRS/Binaries/Win64/ue4ss/Mods/MogHubBestiary
rm -rf dist && mkdir -p $M/Scripts
cp runtime/MogHubBestiary/moghub.ini runtime/MogHubBestiary/moghub.lua $M/
cp runtime/MogHubBestiary/Scripts/*.lua data/bestiary_data.lua $M/Scripts/
mkdir -p $M/lang && cp runtime/MogHubBestiary/lang/*.ini $M/lang/ && rm -f $M/lang/en.ini   # en.ini: a template, never read
cp release/README.txt $M/README.txt
# a MogHub plugin: UE4SS itself must not load it (that is MogHub's job)
if [ -e $M/enabled.txt ] || [ -e $M/Scripts/main.lua ]; then echo "ERROR: enabled.txt / main.lua in $M" >&2; exit 1; fi
# nothing executable may slip in
if find $D -type f | grep -iqE '\.(bat|cmd|ps1|exe|dll|vbs|js)$'; then echo "ERROR: executable file in $D" >&2; exit 1; fi
rm -f dist/MogHubBestiary-$VERSION.zip
# zip with forward slashes (Windows PowerShell's Compress-Archive writes backslashes, which some tools mishandle)
python -c "
import os, sys, zipfile
root, out = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as z:
    for d, _, files in os.walk(os.path.join(root, 'FFRS')):
        for f in sorted(files):
            full = os.path.join(d, f)
            z.write(full, os.path.relpath(full, root).replace(os.sep, '/'))
" $D dist/MogHubBestiary-$VERSION.zip
find $D -type f | sed "s|^$D/||"
ls -la dist/MogHubBestiary-$VERSION.zip
