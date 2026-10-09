#!/usr/bin/env python3
"""Agent edit hook: tidies the files an agent just wrote with the project's Prettier setup.

Claude Code runs it after Write/Edit (`.claude/settings.json`) and Codex after apply_patch
(`.codex/hooks.json`). Claude's hook input names the file in `tool_input.file_path`; Codex's carries
the patch text, whose `*** Add File:` / `*** Update File:` / `*** Move to:` lines name the files.
Files outside a Git checkout, ignored by .prettierignore, or unsupported by Prettier stay as written.
It never blocks the edit: a file Prettier cannot parse stays as written and the type check reports it.
"""

import json
import os
import re
import subprocess
import sys
from collections import defaultdict

PATCH_FILE_LINE = re.compile(r"^\*\*\* (?:Add File|Update File|Move to): (.+?)\s*$", re.MULTILINE)


def strings_in(value):
    if isinstance(value, str):
        yield value
    elif isinstance(value, dict):
        for item in value.values():
            yield from strings_in(item)
    elif isinstance(value, list):
        for item in value:
            yield from strings_in(item)


def edited_paths(payload):
    tool_input = payload.get("tool_input") or {}
    tool_response = payload.get("tool_response") or {}
    claude_path = (tool_input.get("file_path") if isinstance(tool_input, dict) else None) or (
        tool_response.get("filePath") if isinstance(tool_response, dict) else None
    )
    if isinstance(claude_path, str):
        return [claude_path]
    return [path for text in strings_in(tool_input) for path in PATCH_FILE_LINE.findall(text)]


def main():
    payload = json.load(sys.stdin)
    cwd = payload.get("cwd") or os.getcwd()
    files_by_checkout = defaultdict(list)
    for path in edited_paths(payload):
        path = os.path.normpath(os.path.join(cwd, path))
        if not os.path.isfile(path):
            continue
        checkout = subprocess.run(
            ["git", "-C", os.path.dirname(path), "rev-parse", "--show-toplevel"],
            capture_output=True,
            text=True,
        ).stdout.strip()
        if checkout:
            files_by_checkout[checkout].append(path)
    for checkout, files in files_by_checkout.items():
        prettier = os.path.join(checkout, "node_modules", ".bin", "prettier")
        if os.access(prettier, os.X_OK):
            subprocess.run(
                [prettier, "--write", "--ignore-unknown", "--log-level=silent", *files],
                cwd=checkout,
                capture_output=True,
            )


if __name__ == "__main__":
    try:
        main()
    except Exception:
        pass
