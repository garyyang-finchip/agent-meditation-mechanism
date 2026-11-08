#!/usr/bin/env python3
"""Repository text checks.

Fails when any tracked text file contains CJK characters (the repository is English only) or
smart quotes inside the proposal text. Binary files and node_modules are skipped.

    python3 scripts/check-text.py
"""

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SKIP_DIRS = {".git", "node_modules", "out", "cache", "broadcast", "ercs-pr-package"}
TEXT_EXT = {".md", ".sol", ".js", ".json", ".py", ".sh", ".toml", ".yaml", ".yml", ".txt", ".gitignore"}
CJK = re.compile("[%s-%s%s-%s%s-%s%s-%s%s-%s]" % tuple(chr(c) for c in (0x3040, 0x30FF, 0x3400, 0x4DBF, 0x4E00, 0x9FFF, 0xF900, 0xFAFF, 0xFF00, 0xFFEF)))
SMART = re.compile("[%s%s%s%s]" % tuple(chr(c) for c in (0x201C, 0x201D, 0x2018, 0x2019)))


def main() -> int:
    problems = 0
    for dirpath, dirnames, filenames in os.walk(ROOT):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        for name in filenames:
            ext = os.path.splitext(name)[1] or name
            if ext not in TEXT_EXT:
                continue
            path = os.path.join(dirpath, name)
            try:
                text = open(path, encoding="utf-8").read()
            except UnicodeDecodeError:
                print(f"not utf-8: {os.path.relpath(path, ROOT)}")
                problems += 1
                continue
            for lineno, line in enumerate(text.splitlines(), 1):
                if CJK.search(line):
                    print(f"CJK text: {os.path.relpath(path, ROOT)}:{lineno}")
                    problems += 1
                if path.endswith(".md") and SMART.search(line) and "ERCS" in path:
                    print(f"smart quote: {os.path.relpath(path, ROOT)}:{lineno}")
                    problems += 1
    print("text check: ok" if problems == 0 else f"text check: {problems} problem(s)")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
