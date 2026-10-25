"""Writes lang/en.ini - every translatable English text - for MogHub and each plugin in the repository, as the
template translators work from (copy it to lang/<culture>.ini and translate the right-hand sides). The file itself is
never read by MogHub: the English lives in the code.

Settings texts come from running MogHub and the plugins outside the game (UE4SS stubbed; needs `pip install lupa`):
plugins may build their settings with helper functions. Message texts come from the source: every t("key",
"English") call (mod:t, kit.t, or a local t), with the English as string literals joined by `..`.

usage: python moghub/tools/i18n_template.py          (from the repository root)
"""
import os
import re
import shutil
import sys
import tempfile

from lupa import lua54

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
KIT = os.path.join(ROOT, "moghub", "runtime", "MogHub")
HEADER = ("; {name}: English texts, written by moghub/tools/i18n_template.py. This file is a template and is never\n"
          "; read: copy it to {culture_list} and translate what follows each \"=\". Keep {{1}}, {{2}}... and \\n.\n"
          "; Official game terms in every language: moghub/docs/GLOSSARY.md\n")
CULTURES = "fr.ini, de.ini, es.ini, ja.ini, ko.ini, zh-Hans.ini or zh-Hant.ini"

STUBS = r'''
local loops = {}
_G.__loops = loops
function RegisterHook() end
function RegisterKeyBind() end
Key = setmetatable({}, { __index = function(_, k) return k end })
ModifierKey = setmetatable({}, { __index = function(_, k) return k end })
function LoopAsync(ms, fn) loops[#loops + 1] = fn end
function ExecuteInGameThread(fn) fn() end
function ExecuteWithDelay() end
function StaticFindObject() return nil end
function FindFirstOf() return nil end
function FindAllOf() return nil end
function FName(s) return s end
function FText(s) return s end
print = function() end
'''


# --- messages: t("key", "English" .. "more") in the source -----------------------------------------------------------
STRING = r'"(?:[^"\\\n]|\\.)*"|\'(?:[^\'\\\n]|\\.)*\''
CALL = re.compile(r'(?<![\w.])(?:mod:t|kit\.t|M\.t|t)\(\s*(' + STRING + r')\s*,\s*((?:' + STRING + r')(?:\s*\.\.\s*(?:' + STRING + r'))*)')


def unquote(lit):
    body = lit[1:-1]
    return re.sub(r'\\(.)', lambda m: {"n": "\n", "t": "\t"}.get(m.group(1), m.group(1)), body)


def strip_comments(text):
    """Lua source without -- comments (a -- inside a string literal stays)."""
    out = []
    for line in text.split("\n"):
        i, quote = 0, None
        while i < len(line):
            c = line[i]
            if quote:
                if c == "\\":
                    i += 1
                elif c == quote:
                    quote = None
            elif c in "\"'":
                quote = c
            elif line.startswith("--", i):
                line = line[:i]
                break
            i += 1
        out.append(line)
    return "\n".join(out)


def messages(folder):
    found = {}
    for dirpath, _, files in os.walk(folder):
        for f in sorted(files):
            if not f.endswith(".lua"):
                continue
            text = strip_comments(open(os.path.join(dirpath, f), encoding="utf-8").read())
            for m in CALL.finditer(text):
                key = unquote(m.group(1))
                parts = re.findall(STRING, m.group(2))
                found.setdefault(key, "".join(unquote(p) for p in parts))
    return found


# --- settings: run the kit with stubs and read each plugin's items --------------------------------------------------
def run_kit(mods):
    L = lua54.LuaRuntime()
    L.execute(STUBS)
    L.execute('package.path = "' + mods.replace("\\", "/") + '/MogHub/Scripts/?.lua;" .. package.path')
    L.execute('_G.kit = require("kit.core"); kit.start("' + mods.replace("\\", "/") + '/MogHub")')
    return L


def settings_texts(L, plugin_id):
    rows = L.execute('''
        local id = ...
        local out = {}
        for _, p in ipairs(kit.plugins) do if p.id == id then
            local function add(k, v) if v and v ~= "" then out[#out + 1] = { k, v } end end
            add("plugin.name", p.name); add("plugin.description", p.description)
            if p.ownScreen then add("screen.title", p.ownScreen.title) end
            if p.config then
                for _, it in ipairs(p.config:items()) do
                    if it.type == "header" then add("header." .. it.label, it.label)
                    elseif it.type ~= "value" then
                        local b = it.key or it.id or it.label
                        for _, f in ipairs({ "label", "help", "button", "done" }) do add(b .. "." .. f, it[f]) end
                        if it.type == "choice" then
                            for _, c in ipairs(it.choices) do if c[2] then add(b .. ".choice." .. tostring(c[1]), c[2]) end end
                        end
                    end
                end
            end
        end end
        return out
    ''', plugin_id)
    return [(rows[i][1], rows[i][2]) for i in range(1, len(rows) + 1)]


def write(path, name, settings, msgs):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    lines = [HEADER.format(name=name, culture_list=CULTURES)]
    seen = set()
    if settings:
        lines.append("\n; --- name and settings ---")
        for k, v in settings:
            if k not in seen:
                seen.add(k)
                lines.append(f"{k} = {v}".replace("\n", "\\n"))
    rest = [(k, v) for k, v in sorted(msgs.items()) if k not in seen]
    if rest:
        lines.append("\n; --- messages ---")
        for k, v in rest:
            lines.append(f"{k} = {v}".replace("\n", "\\n"))
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")
    return len(seen) + len(rest)


def main():
    tmp = tempfile.mkdtemp(prefix="moghub_i18n_")
    try:
        mods = os.path.join(tmp, "Mods")
        shutil.copytree(KIT, os.path.join(mods, "MogHub"), ignore=shutil.ignore_patterns("lang"))
        plugins = []
        for name in sorted(os.listdir(os.path.join(ROOT, "plugins"))):
            rt = os.path.join(ROOT, "plugins", name, "runtime")
            for folder in sorted(os.listdir(rt)) if os.path.isdir(rt) else []:
                src = os.path.join(rt, folder)
                if os.path.exists(os.path.join(src, "moghub.lua")):
                    dst = os.path.join(mods, folder)
                    shutil.copytree(src, dst, ignore=shutil.ignore_patterns("lang", "config.ini", "saves"))
                    data = os.path.join(ROOT, "plugins", name, "data")
                    for f in os.listdir(data) if os.path.isdir(data) else []:
                        if f.endswith(".lua"):
                            shutil.copy(os.path.join(data, f), os.path.join(dst, "Scripts", f))
                    plugins.append((folder, src))
        L = run_kit(mods)
        n = write(os.path.join(KIT, "lang", "en.ini"), "MogHub", [], messages(os.path.join(KIT, "Scripts")))
        print(f"MogHub: {n} texts")
        for folder, src in plugins:
            n = write(os.path.join(src, "lang", "en.ini"), folder, settings_texts(L, folder), messages(src))
            print(f"{folder}: {n} texts")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
