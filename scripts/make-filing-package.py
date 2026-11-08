#!/usr/bin/env python3
"""Build the ethereum/ERCs filing package from the repository sources.

    python3 scripts/make-filing-package.py [--number N] [--discussions-to URL] [--out DIR]

The repository keeps the proposal at ERCS/erc-agent-meditation.md with the placeholder
number 9999 and its assets under assets/erc-agent-meditation/. The filing package renames
both to the assigned number, rewrites the asset links, fills the discussions-to header,
and writes a manifest with the SHA-256 of every file so an upload can be verified byte for byte.
"""

import argparse
import hashlib
import os
import re
import shutil
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCE_MD = os.path.join(ROOT, "ERCS", "erc-agent-meditation.md")
SOURCE_ASSETS = os.path.join(ROOT, "assets", "erc-agent-meditation")
PLACEHOLDER_DISCUSSIONS = "https://ethereum-magicians.org/t/placeholder"
EXCLUDED_DIRS = {"__pycache__", "node_modules"}


def build(number: int, discussions_to: str | None, out_dir: str) -> list[tuple[str, str]]:
    if os.path.exists(out_dir):
        shutil.rmtree(out_dir)
    os.makedirs(os.path.join(out_dir, "ERCS"))

    with open(SOURCE_MD, encoding="utf-8") as fh:
        text = fh.read()
    text = re.sub(r"^eip: 9999$", f"eip: {number}", text, count=1, flags=re.MULTILINE)
    text = text.replace("eip-9999", f"eip-{number}")
    if discussions_to:
        text = text.replace(PLACEHOLDER_DISCUSSIONS, discussions_to)
    md_path = os.path.join(out_dir, "ERCS", f"erc-{number}.md")
    with open(md_path, "w", encoding="utf-8") as fh:
        fh.write(text)

    assets_out = os.path.join(out_dir, "assets", f"erc-{number}")
    for dirpath, dirnames, filenames in os.walk(SOURCE_ASSETS):
        dirnames[:] = sorted(d for d in dirnames if d not in EXCLUDED_DIRS)
        rel = os.path.relpath(dirpath, SOURCE_ASSETS)
        target_dir = os.path.join(assets_out, rel) if rel != "." else assets_out
        os.makedirs(target_dir, exist_ok=True)
        for name in sorted(filenames):
            shutil.copy2(os.path.join(dirpath, name), os.path.join(target_dir, name))

    manifest = []
    for dirpath, dirnames, filenames in os.walk(out_dir):
        dirnames.sort()
        for name in sorted(filenames):
            if name == "MANIFEST.sha256":
                continue
            path = os.path.join(dirpath, name)
            with open(path, "rb") as fh:
                digest = hashlib.sha256(fh.read()).hexdigest()
            manifest.append((digest, os.path.relpath(path, out_dir)))
    with open(os.path.join(out_dir, "MANIFEST.sha256"), "w", encoding="utf-8") as fh:
        for digest, rel in manifest:
            fh.write(f"{digest}  {rel}\n")
    return manifest


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--number", type=int, default=9999, help="assigned ERC number (default: 9999 placeholder)")
    parser.add_argument("--discussions-to", default=None, help="Ethereum Magicians thread URL")
    parser.add_argument("--out", default=os.path.join(ROOT, "ercs-pr-package"), help="output directory")
    args = parser.parse_args()

    if args.discussions_to and not re.match(r"^https://ethereum-magicians\.org/t/[^/]+/[0-9]+$", args.discussions_to):
        print("warning: discussions-to does not look like an Ethereum Magicians thread URL", file=sys.stderr)

    manifest = build(args.number, args.discussions_to, args.out)
    print(f"wrote {len(manifest)} files to {os.path.relpath(args.out, ROOT)}")
    if not args.discussions_to:
        print("note: discussions-to still carries the placeholder; rerun with --discussions-to once the thread exists")
    return 0


if __name__ == "__main__":
    sys.exit(main())
