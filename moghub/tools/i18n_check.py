"""Checks every translation against its English template (lang/en.ini, written by i18n_template.py): missing and
unknown keys, and placeholders ({1}, {2}...) or line breaks (\\n) that differ from the English.

usage: python moghub/tools/i18n_check.py          (from the repository root; exit code 1 when something is wrong)
"""
import glob
import os
import re
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
LANGS = ["fr", "de", "es", "ja", "ko", "zh-Hans", "zh-Hant"]


def read(path):
    out = {}
    with open(path, encoding="utf-8-sig") as f:
        for line in f:
            line = line.rstrip("\r\n")
            if not line.strip() or line.lstrip().startswith((";", "#")):
                continue
            if "=" in line:
                k, v = line.split("=", 1)
                out[k.strip()] = v.strip()
    return out


def marks(text):
    return sorted(re.findall(r"\{\d+\}", text)), text.count("\\n")


def main():
    problems = 0
    templates = glob.glob(os.path.join(ROOT, "moghub", "runtime", "*", "lang", "en.ini")) + \
        glob.glob(os.path.join(ROOT, "plugins", "*", "runtime", "*", "lang", "en.ini"))
    for en_path in sorted(templates):
        en = read(en_path)
        folder = os.path.dirname(en_path)
        rel = os.path.relpath(folder, ROOT)
        for lang in LANGS:
            path = os.path.join(folder, lang + ".ini")
            if not os.path.exists(path):
                print(f"{rel}/{lang}.ini: missing file")
                problems += 1
                continue
            tr = read(path)
            issues = []
            for k in en:
                if k not in tr:
                    issues.append(f"missing {k}")
                elif marks(en[k])[0] != marks(tr[k])[0]:
                    issues.append(f"placeholders differ in {k}: {tr[k]}")
                elif marks(en[k])[1] != marks(tr[k])[1]:
                    issues.append(f"line breaks differ in {k}")
            issues += [f"unknown key {k}" for k in tr if k not in en]
            status = "ok" if not issues else f"{len(issues)} problem(s)"
            print(f"{rel}/{lang}.ini: {len(tr)} texts, {status}")
            for i in issues:
                print("    " + i)
            problems += len(issues)
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
