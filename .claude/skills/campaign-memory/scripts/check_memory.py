#!/usr/bin/env python3
"""Check Campaign Memory for notes over their word limit, pointers to missing files, and index mismatches.

By default it checks only the Memory files you changed: uncommitted changes, plus commits on this
branch that main does not have. `--all` checks every file.

    python3 .claude/skills/campaign-memory/scripts/check_memory.py
    python3 .claude/skills/campaign-memory/scripts/check_memory.py --all

Prints one line per problem and exits 1, or prints "Memory check passed" and exits 0.
"""

import argparse
import re
import subprocess
import sys
from pathlib import Path

# Word limits for each kind of Memory file. This is the only place they are set.
NOW_LIMIT, ROADMAP_LIMIT, PART_LIMIT, DEFERRED_LIMIT, INDEX_ROW_LIMIT = 200, 800, 500, 150, 50
STATES = ("planning", "in progress", "paused", "blocked")

MARKDOWN_LINK = re.compile(r"\[[^\]]*\]\(([^)\s]+)[^)]*\)")
CODE_SPAN = re.compile(r"`([^`\s]+)`")
PLACEHOLDER = re.compile(r"[<>*{}$]|\.\.\.|://")
LINE_SUFFIX = re.compile(r":\d+(-\d+)?$")


def git(root, *args):
    result = subprocess.run(["git", *args], cwd=root, capture_output=True, text=True)
    return result.stdout if result.returncode == 0 else None


def project_root():
    top = git(Path.cwd(), "rev-parse", "--show-toplevel")
    return Path(top.strip()) if top else Path(__file__).resolve().parents[4]


def compare_base(root, base):
    """The commit to compare against: where this branch left main, or HEAD when on main."""
    if base:
        return base
    branch = (git(root, "rev-parse", "--abbrev-ref", "HEAD") or "").strip()
    if branch != "main" and git(root, "rev-parse", "--verify", "--quiet", "main"):
        merge_base = git(root, "merge-base", "main", "HEAD")
        if merge_base:
            return merge_base.strip()
    return "HEAD"


def changed_files(root, base):
    changed = set()
    status = git(root, "status", "--porcelain", "--untracked-files=all", "--", "Memory") or ""
    for line in status.splitlines():
        for path in line[3:].split(" -> "):
            changed.add(path.strip().strip('"'))
    committed = git(root, "diff", "--name-only", f"{base}..HEAD", "--", "Memory") or ""
    changed.update(path for path in committed.splitlines() if path)
    return changed


def campaign_of(rel):
    parts = Path(rel).parts
    return parts[2] if len(parts) > 3 and parts[:2] == ("Memory", "campaigns") else None


def word_limit(rel):
    parts = Path(rel).parts
    if campaign_of(rel):
        inside = parts[3:]
        if inside == ("NOW.md",):
            return NOW_LIMIT, "NOW.md"
        if inside == ("ROADMAP.md",):
            return ROADMAP_LIMIT, "roadmap"
        if inside[0] == "stages":
            return ROADMAP_LIMIT, "stage file"
        if inside[0] == "parts":
            return PART_LIMIT, "part note"
    if parts[:2] == ("Memory", "deferred") and parts[-1] != "INDEX.md":
        return DEFERRED_LIMIT, "deferred note"
    return None, None


def pointer_targets(text):
    """File pointers worth checking: every local Markdown link, and code spans that name a document."""
    for target in MARKDOWN_LINK.findall(text):
        if not target.startswith(("http:", "https:", "mailto:", "#")):
            yield target.split("#")[0], True
    for span in CODE_SPAN.findall(text):
        span = LINE_SUFFIX.sub("", span.split("#")[0])
        if PLACEHOLDER.search(span):
            continue
        if span.endswith(".md") or span.startswith(("Memory/", "docs/", ".claude/")):
            yield span, "/" in span


def resolves(root, rel, target):
    base = root / rel
    candidates = [base.parent / target, root / "Memory" / target, root / target]
    campaign = campaign_of(rel)
    if campaign:
        candidates.append(root / "Memory" / "campaigns" / campaign / target)
    if target.startswith("/"):
        candidates.append(Path(target))
    return any(path.exists() for path in candidates)


def table_rows(text):
    rows = [line for line in text.splitlines() if line.lstrip().startswith("|")]
    return [row for row in rows[1:] if not re.fullmatch(r"[\s|:-]*", row)]


def cells(row):
    return [cell.strip() for cell in row.strip().strip("|").split("|")]


def row_name(row):
    first = re.sub(r"[`*]", "", cells(row)[0])
    match = re.search(r"\[([^\]]+)\]|([A-Za-z0-9][\w.-]*)", first)
    return (match.group(1) or match.group(2)) if match else first


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--all", action="store_true", help="check every Memory file, not only changed ones")
    parser.add_argument("--base", help="compare against this commit instead of main")
    args = parser.parse_args()

    root = project_root()
    memory = root / "Memory"
    if not memory.is_dir():
        print("No Memory/ folder here; see the skill's setup.md")
        return 0

    base = compare_base(root, args.base)
    if args.all:
        changed = {str(path.relative_to(root)) for path in memory.rglob("*.md")}
    else:
        changed = {path for path in changed_files(root, base) if path.endswith(".md")}
    if not changed:
        print("No changed Memory files to check (use --all to check everything)")
        return 0

    problems = []
    checked = 0
    for rel in sorted(changed):
        path = root / rel
        if not path.is_file():
            continue
        checked += 1
        text = path.read_text(encoding="utf-8")
        limit, kind = word_limit(rel)
        words = len(text.split())
        if limit and words > limit:
            problems.append(f"{rel}: {words} words, over the {limit}-word limit for a {kind}")
        if rel.endswith("/INDEX.md"):
            continue  # the index checks below cover both index files
        for target, strict in pointer_targets(text):
            if not resolves(root, rel, target) and (strict or rel.endswith(("NOW.md", "ROADMAP.md"))):
                problems.append(f"{rel}: points to {target}, which does not exist")

    # The campaign index: every campaign folder has one row, every row has a folder, rows stay short.
    index = memory / "INDEX.md"
    index_rel = "Memory/INDEX.md"
    campaigns_changed = {campaign_of(rel) for rel in changed} - {None}
    folders = {path.parent.name for path in (memory / "campaigns").glob("*/NOW.md")}
    if index.is_file():
        rows = table_rows(index.read_text(encoding="utf-8"))
        old_rows = set()
        if not args.all and index_rel in changed:
            old_rows = set(table_rows(git(root, "show", f"{base}:{index_rel}") or ""))
        named = {}
        for row in rows:
            name = row_name(row)
            named[name] = row
            row_changed = args.all or name in campaigns_changed or (index_rel in changed and row not in old_rows)
            if not row_changed:
                continue
            row_words = len(row.replace("|", " ").split())
            if row_words > INDEX_ROW_LIMIT:
                problems.append(f"{index_rel}: row '{name}' has {row_words} words, over the {INDEX_ROW_LIMIT}-word limit")
            state = cells(row)[1] if len(cells(row)) > 1 else ""
            if not state.lower().startswith(STATES):
                problems.append(f"{index_rel}: row '{name}' state '{state[:40]}' is not Planning, In progress, Paused, or Blocked")
            if name not in folders:
                problems.append(f"{index_rel}: row '{name}' has no Memory/campaigns/{name}/NOW.md")
        for name in sorted(folders if args.all else campaigns_changed & folders):
            if name not in named:
                problems.append(f"Memory/campaigns/{name}/: no row in {index_rel}")

    # The deferred index: each row links to its note, and each note has a row.
    deferred = memory / "deferred"
    deferred_changed = any(rel.startswith("Memory/deferred/") for rel in changed)
    deferred_index = deferred / "INDEX.md"
    if deferred_index.is_file() and (args.all or deferred_changed):
        linked = set()
        for row in table_rows(deferred_index.read_text(encoding="utf-8")):
            for target in MARKDOWN_LINK.findall(row):
                linked.add(target)
                if not (deferred / target).is_file():
                    problems.append(f"Memory/deferred/INDEX.md: row links to {target}, which does not exist")
        for note in sorted(deferred.glob("*.md")):
            rel = str(note.relative_to(root))
            if note.name != "INDEX.md" and note.name not in linked and (args.all or rel in changed):
                problems.append(f"{rel}: no row in Memory/deferred/INDEX.md")

    for problem in problems:
        print(problem)
    if problems:
        print(f"{len(problems)} problem(s) in {checked} file(s) checked")
        return 1
    print(f"Memory check passed ({checked} file(s) checked)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
