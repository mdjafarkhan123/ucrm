#!/usr/bin/env python3
"""Local, atomic reservations for independent agent sessions in this repository."""

import argparse
import fcntl
import json
import os
import subprocess
import sys
import tempfile
import uuid
from datetime import datetime, timezone
from pathlib import Path


def git(*args):
    return subprocess.check_output(["git", *args], text=True).strip()


def paths():
    # The first entry is the main worktree, shared by every linked worktree.
    main = Path(git("worktree", "list", "--porcelain").splitlines()[0][9:]).resolve()
    current = Path(git("rev-parse", "--show-toplevel")).resolve()
    return main / ".agent-work", current


def read_state(path):
    if not path.exists():
        return {"claims": []}
    with path.open(encoding="utf-8") as stream:
        state = json.load(stream)
    if not isinstance(state, dict) or not isinstance(state.get("claims"), list):
        raise ValueError("Invalid agent-work state; inspect it before proceeding")
    return state


def save_state(path, state):
    descriptor, temporary = tempfile.mkstemp(prefix="state-", dir=path.parent)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as stream:
            json.dump(state, stream, indent=2)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("list", help="Show active reservations")
    claim = commands.add_parser("claim", help="Reserve one task before beginning it")
    claim.add_argument("campaign", help="Campaign name, or 'standalone'")
    claim.add_argument("task", help="Roadmap part or unique task name")
    claim.add_argument("--owner", required=True, help="Session or terminal label")
    claim.add_argument("--mode", choices=("read", "write"), required=True)
    claim.add_argument("--area", action="append", default=[], help="Shared code or external resource; repeat as needed")
    claim.add_argument("--adopt-existing", action="store_true", help="Claim a workspace with changes you verified belong to this session")
    release = commands.add_parser("release", help="Release a completed or inspected abandoned reservation")
    release.add_argument("id", help="Reservation ID from list")
    expand = commands.add_parser("expand", help="Atomically add areas to a write reservation")
    expand.add_argument("id", help="Reservation ID from list")
    expand.add_argument("--area", action="append", required=True, help="Additional code or external resource")
    args = parser.parse_args()

    directory, workspace = paths()
    directory.mkdir(exist_ok=True)
    with (directory / "lock").open("a+") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        state_path = directory / "state.json"
        state = read_state(state_path)
        claims = state["claims"]

        if args.command == "list":
            if not claims:
                print("No active reservations. Check Git for unclaimed changes before writing.")
            for item in claims:
                print(f"{item['id']}  {item['campaign']}/{item['task']}  {item['mode']}  {item['owner']}  {item['workspace']}  areas={','.join(item['areas']) or '-'}  since={item['created']}")
            return

        if args.command == "release":
            remaining = [item for item in claims if item["id"] != args.id]
            if len(remaining) == len(claims):
                parser.error("Reservation not found; run list")
            state["claims"] = remaining
            save_state(state_path, state)
            print(f"Released {args.id}")
            return

        if args.command == "expand":
            item = next((entry for entry in claims if entry["id"] == args.id), None)
            if item is None or item["mode"] != "write":
                parser.error("Write reservation not found; run list")
            if item["workspace"] != str(workspace):
                parser.error("Expand this reservation from its owning worktree")
            areas = sorted(set(item["areas"]) | {area.strip() for area in args.area})
            if any(not area for area in areas):
                parser.error("Areas must be nonempty")
            for other in claims:
                if other["id"] != item["id"] and other["mode"] == "write":
                    if "*" in areas or "*" in other["areas"] or set(areas) & set(other["areas"]):
                        parser.error(f"Area overlaps {other['owner']} ({other['id']})")
            item["areas"] = areas
            save_state(state_path, state)
            print(f"Expanded {args.id}: {', '.join(areas)}")
            return

        if not args.campaign.strip() or not args.task.strip() or not args.owner.strip():
            parser.error("Campaign, task, and owner must be nonempty")
        areas = sorted(set(area.strip() for area in args.area))
        if args.mode == "write" and (not areas or any(not area for area in areas)):
            parser.error("Write reservations need at least one nonempty --area")
        for item in claims:
            if item["campaign"] == args.campaign and item["task"] == args.task:
                parser.error(f"Task already reserved by {item['owner']} ({item['id']})")
            if args.mode == "write" and item["mode"] == "write":
                if item["workspace"] == str(workspace):
                    parser.error(f"Workspace already has a writer: {item['owner']} ({item['id']})")
                if "*" in areas or "*" in item["areas"] or set(areas) & set(item["areas"]):
                    parser.error(f"Area overlaps {item['owner']} ({item['id']})")
        if args.mode == "write" and not args.adopt_existing:
            if git("status", "--porcelain", "--untracked-files=all"):
                parser.error("Workspace has unclaimed changes. Inspect ownership, then use --adopt-existing only for your own work")

        item = {
            "id": uuid.uuid4().hex[:12],
            "campaign": args.campaign,
            "task": args.task,
            "owner": args.owner,
            "mode": args.mode,
            "workspace": str(workspace),
            "areas": areas,
            "created": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        }
        claims.append(item)
        save_state(state_path, state)
        print(f"Reserved {item['id']} for {item['owner']}")


if __name__ == "__main__":
    try:
        main()
    except (subprocess.CalledProcessError, OSError, ValueError) as error:
        print(f"agent-work: {error}", file=sys.stderr)
        sys.exit(1)
