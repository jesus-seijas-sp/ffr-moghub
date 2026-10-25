"""Release zips for Nexus Mods and GitHub: one per mod, laid out to be extracted into the game folder.

usage (from the repository root):  python tools/package.py      -> dist/<Name>-<version>.zip

MogHub-<v>.zip            FFRS/Binaries/Win64/ue4ss/Mods/MogHub (scripts, translations, config.ini, enabled.txt)
                          and its menu pak FFRS/Content/Paks/~mods/zzz_MogHub_P.* (moghub/build/out)
MogHub<Plugin>-<v>.zip    FFRS/Binaries/Win64/ue4ss/Mods/<Folder> (moghub.ini, moghub.lua, Scripts with the plugin's
                          data/*.lua, translations, LICENSE)
lang/en.ini is left out everywhere: it is the template for translators, never read (the English is in the code).
"""
import glob, os, re, zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MODS = 'FFRS/Binaries/Win64/ue4ss/Mods'
PAKS = 'FFRS/Content/Paks/~mods'
DIST = os.path.join(ROOT, 'dist')


def rel(*p):
    return os.path.join(ROOT, *p)


def write(name, files):
    """files: [(source path, path in the zip)]"""
    os.makedirs(DIST, exist_ok=True)
    out = os.path.join(DIST, name)
    with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as z:
        for src, arc in sorted(files, key=lambda f: f[1]):
            if src is None:
                z.writestr(arc, '')
            else:
                z.write(src, arc)
    print(f'{name}: {len(files)} files, {os.path.getsize(out) // 1024} KB')


def translations(folder, arc):
    return [(f, f'{arc}/lang/{os.path.basename(f)}') for f in glob.glob(os.path.join(folder, 'lang', '*.ini'))
            if os.path.basename(f) != 'en.ini']


# ---------- MogHub ----------
core = open(rel('moghub/runtime/MogHub/Scripts/kit/core.lua'), encoding='utf8').read()
version = re.search(r'VERSION = "([^"]+)"', core).group(1)
arc = f'{MODS}/MogHub'
files = [(rel('moghub/runtime/MogHub/Scripts/main.lua'), f'{arc}/Scripts/main.lua'),
         (rel('moghub/runtime/MogHub/config.ini'), f'{arc}/config.ini'),
         (None, f'{arc}/enabled.txt'),
         (rel('LICENSE'), f'{arc}/LICENSE')]
files += [(f, f'{arc}/Scripts/kit/{os.path.basename(f)}') for f in glob.glob(rel('moghub/runtime/MogHub/Scripts/kit/*.lua'))]
files += translations(rel('moghub/runtime/MogHub'), arc)
paks = glob.glob(rel('moghub/build/out/zzz_MogHub_P.*'))
assert len(paks) == 3, 'menu pak missing: run moghub/tools/build_pak.sh'
files += [(f, f'{PAKS}/{os.path.basename(f)}') for f in paks]
write(f'MogHub-{version}.zip', files)

# ---------- plugins ----------
for folder in sorted(glob.glob(rel('plugins/*/runtime/*/'))):
    if not os.path.exists(os.path.join(folder, 'moghub.lua')):
        continue
    name = os.path.basename(os.path.normpath(folder))
    plugin = os.path.dirname(os.path.dirname(os.path.normpath(folder)))
    ini = open(os.path.join(folder, 'moghub.ini'), encoding='utf8').read()
    version = re.search(r'^Version\s*=\s*(\S+)', ini, re.M).group(1)
    arc = f'{MODS}/{name}'
    files = [(os.path.join(folder, f), f'{arc}/{f}') for f in ('moghub.ini', 'moghub.lua')]
    files += [(f, f'{arc}/Scripts/{os.path.basename(f)}') for f in glob.glob(os.path.join(folder, 'Scripts', '*.lua'))]
    files += [(f, f'{arc}/Scripts/{os.path.basename(f)}') for f in glob.glob(os.path.join(plugin, 'data', '*.lua'))]
    files += translations(folder, arc)
    if os.path.exists(os.path.join(plugin, 'LICENSE')):
        files.append((os.path.join(plugin, 'LICENSE'), f'{arc}/LICENSE'))
    write(f'{name}-{version}.zip', files)
