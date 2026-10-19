"""Build an isolated test copy of the project for campaign-memory skill trials.

Usage: python3 docs/research/campaign-memory-trials/make_fixture.py <dest> <skill_dir> <project_root>

<dest> must be outside the project (a scratch folder); it becomes its own Git repository.
"""

import shutil
import subprocess
import sys
from pathlib import Path

dest, skill_dir, project_root = (Path(arg).resolve() for arg in sys.argv[1:4])

FILES = {
    ".gitignore": ".agent-work/\n.worktrees/\n__pycache__/\n",
    # ---------------------------------------------------------------- Memory
    "Memory/INDEX.md": """# Campaigns

Plans live in `docs/<feature>-behavior-contract.md`. Each campaign's notes are in
`campaigns/<campaign>/`, starting with its `NOW.md`. Postponed work is in `deferred/INDEX.md`; read it only
when a note or Jafar names it.

| Campaign | State | Purpose | Read when |
| --- | --- | --- | --- |
| job-checklists | In progress | Crews tick off job steps on site | job checklists, crew checklist |
| invoice-export | Blocked | Owners send invoices to their accountant | invoice export, accountant, CSV |
| price-book-import | In progress | Owners import their price list from a spreadsheet | price book, import prices |
| staff-timesheets | Planning | Workers log hours; managers approve them | timesheets, hours, overtime |
| quote-reminders | In progress | Unanswered quotes get automatic reminder texts | quote reminders, follow-up texts |
""",
    "Memory/deferred/INDEX.md": """# Deferred work

One row per postponed task; its note holds the detail.

| Priority | Task |
| --- | --- |
| P2 | [Clients add photos when they request work](request-photos.md) |
| P3 | [Printed invoices in dark colours](print-dark-invoices.md) |
""",
    "Memory/deferred/request-photos.md": """# Clients add photos when they request work

**Why it waits:** photo storage costs were not decided (2026-09-20)
**Brings it back:** Jafar starts a campaign for request photos
**Known constraints:** at most 10 photos per request, 10 MB each (Jafar, 2026-09-20)
""",
    "Memory/deferred/print-dark-invoices.md": """# Printed invoices in dark colours

**Why it waits:** no customer has asked for it
**Brings it back:** a customer asks for dark printed invoices
""",
    # quote-reminders: resume, outside action already done, build, finish a part
    "Memory/campaigns/quote-reminders/NOW.md": """# Quote reminders — now

**Goal:** Unanswered quotes get automatic reminder texts, so owners stop chasing clients by hand.
**Core agreement — read on every resume:** `docs/quote-reminders-behavior-contract.md` § Summary and § Rules for every part
**Plan:** `docs/quote-reminders-behavior-contract.md` — first version approved 2026-10-02
**Stage:** Building

**In progress:**

- 2 Reminder sender — `parts/2-reminder-sender.md`

**Next part:** 3 Settings switch — the on/off switch in Settings → Quotes

**Blockers:** none
""",
    "Memory/campaigns/quote-reminders/ROADMAP.md": """# Quote reminders — roadmap

**Plan:** `docs/quote-reminders-behavior-contract.md` — scope and build order approved 2026-10-02

| Part | Plan section | Delivers | Waits for | Done when | State |
| --- | --- | --- | --- | --- | --- |
| 1 Reminder schedule | § Sending a reminder | which quotes are due a reminder today | — | `python3 checks/schedule_check.py` passes | Done 2026-10-05 |
| 2 Reminder sender | § Sending a reminder | due reminders are texted; opted-out clients skipped and recorded | 1 | `python3 checks/reminder_check.py` passes | In progress |
| 3 Settings switch | § First version | owners turn reminders on or off | 2 | the switch turns sending on and off in the live app | Not started |
| 4 Final walk-through | § Success checks | both success checks tried in the live app | 2, 3 | Jafar watched both checks pass | Not started |
""",
    "Memory/campaigns/quote-reminders/parts/2-reminder-sender.md": """# Part 2 — Reminder sender

**Campaign:** quote-reminders · **Plan:** `docs/quote-reminders-behavior-contract.md` § Sending a reminder
**Stage:** Building
**Code:** `main`
**Done when:** `python3 checks/reminder_check.py` passes

## Steps

- [x] Send due reminders through the text provider (`app/reminders/sender.py`)
- [x] Send one real test reminder to Jafar's phone
- [ ] Skip opted-out clients and record the skip
- [ ] Run the done-check

## Next

Add the opted-out skip to `pick_recipients` in `app/reminders/sender.py`, recording "Reminder skipped: client
opted out" on the quote's activity, then run `python3 checks/reminder_check.py`.

## Outside actions

- Send one test reminder to Jafar's phone — check: `outbox/sent.log` has a line with message id `QR-TEST-7` — pending

## Notes

- The last session stopped right after pressing send on the test reminder, before its result was saved.
""",
    "docs/quote-reminders-behavior-contract.md": """# Quote reminders

**Status:** First version approved by Jafar on 2026-10-02.

## Summary

Contractors send quotes that clients often forget to answer. With quote reminders turned on, the client gets
one friendly text 3 days after the quote is sent and a second one 7 days after, unless they have answered.
More quotes reach a yes without the owner chasing anyone by hand.

## Rules for every part

- Never text a client who has opted out of texts. This applies to every message this campaign sends.
- Reminders carry the business's own name, never "Uplift".

## First version

- Text reminders on day 3 and day 7 for quotes still waiting for an answer.
- One on/off switch in Settings → Quotes, off by default.

## Sending a reminder

- A quote counts as waiting while its status is Sent.
- At most two reminders per quote; none after the client approves or declines.
- Opted-out clients are skipped, and the skip is recorded on the quote's activity.

## Success checks

- A quote sent 3 days ago and still waiting → its client receives one reminder text.
- The same quote's client has opted out → no text; the quote's activity says "Reminder skipped: client opted out".

## Not doing

- Email reminders — later version.

## Sources and design decisions

- Settings switch design: `concept.pen` frame "Quotes settings" (approved 2026-10-03).
""",
    "app/__init__.py": "",
    "app/reminders/__init__.py": "",
    "app/reminders/sender.py": '''"""Sends due quote reminders. Part 2 of the quote-reminders campaign."""

from dataclasses import dataclass, field


@dataclass
class Client:
    name: str
    phone: str
    opted_out: bool = False


@dataclass
class Quote:
    number: str
    client: Client
    status: str = "Sent"
    activity: list = field(default_factory=list)


def pick_recipients(quotes):
    """Return the quotes whose clients should get a reminder text now."""
    return [quote for quote in quotes if quote.status == "Sent"]


def send_due_reminders(quotes, send_text):
    for quote in pick_recipients(quotes):
        send_text(quote.client.phone, f"Reminder: quote {quote.number} is waiting for your answer.")
''',
    "checks/reminder_check.py": '''"""Done-check for quote-reminders Part 2."""

import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from app.reminders.sender import Client, Quote, send_due_reminders  # noqa: E402

sent = []
waiting = Quote("Q-101", Client("Rahim", "+8801700000001"))
opted_out = Quote("Q-102", Client("Karim", "+8801700000002", opted_out=True))
answered = Quote("Q-103", Client("Nadia", "+8801700000003"), status="Approved")

send_due_reminders([waiting, opted_out, answered], lambda phone, text: sent.append(phone))

assert sent == ["+8801700000001"], f"expected one reminder to Rahim, got {sent}"
assert "Reminder skipped: client opted out" in opted_out.activity, "opted-out skip was not recorded"
print("reminder check passed")
''',
    "outbox/sent.log": '2026-10-18T10:02:11 QR-TEST-7 delivered +8801700009999 "Reminder: quote Q-001 is waiting for your answer."\n',
    # staff-timesheets: interrupted planning with one pending question
    "Memory/campaigns/staff-timesheets/NOW.md": """# Staff timesheets — now

**Goal:** Workers log hours on their phone and managers approve them, so pay is right without paper.
**Core agreement — read on every resume:** `docs/staff-timesheets-behavior-contract.md` § Summary
**Plan:** `docs/staff-timesheets-behavior-contract.md` — still being planned
**Stage:** Planning

**In progress:**

- 1 Plan: timesheets — `parts/1-plan.md`

**Next part:** 2 Split the work — after Jafar approves the plan

**Blockers:** none
""",
    "Memory/campaigns/staff-timesheets/ROADMAP.md": """# Staff timesheets — roadmap

**Plan:** `docs/staff-timesheets-behavior-contract.md` — proposed

| Part | Plan section | Delivers | Waits for | Done when | State |
| --- | --- | --- | --- | --- | --- |
| 1 Plan: timesheets | § Summary | the first-version questions settled | — | first-version questions settled; Jafar approved | In progress |
| 2 Split the work | § First version | buildable parts with checks | 1 | Jafar approved the parts and order | Not started |
""",
    "Memory/campaigns/staff-timesheets/parts/1-plan.md": """# Part 1 — Plan: timesheets

**Campaign:** staff-timesheets · **Plan:** `docs/staff-timesheets-behavior-contract.md`
**Stage:** Planning
**Code:** `main`
**Done when:** first-version questions settled; Jafar approved

## Steps

- [x] Research how Jobber and Connecteam handle timesheet edits and approval
- [x] Ask Jafar whether workers can edit submitted hours (answered 2026-10-14, recorded in the plan)
- [ ] Ask Jafar about overtime approval
- [ ] Fresh-reader check, then ask Jafar to approve the plan

## Next

Ask Jafar this question, word for word, then record his answer in the plan:

"When a worker logs more than 8 hours in a day, should the extra hours wait for a manager's approval before
they count as overtime pay? I recommend yes: Jobber and Connecteam both hold overtime for approval, and it
stops surprise pay. For example, if Rafi logs 10 hours on Tuesday, 8 count straight away and 2 wait for you."

## Notes

- Research notes: `docs/research/timesheets.md`.
""",
    "docs/staff-timesheets-behavior-contract.md": """# Staff timesheets

**Status:** Planning — not yet approved.

## Summary

Workers log the hours they spend on each job from their phone. Managers check and approve the hours before
payroll, so pay is right without paper timesheets.

## Problem and audience

Owners of 3–20 person crews collect hours on paper or by text message, and pay mistakes are common.

## First version

- Workers log start and end times per job.
- Managers approve a worker's week.

## Editing hours

- Workers can edit their own hours until a manager approves the week (Jafar, 2026-10-14).

## Still unclear

- When a worker logs more than 8 hours in a day, should the extra hours wait for a manager's approval before
  they count as overtime pay? Blocks the first version.

## Not doing

- Payroll export — later version.
""",
    "docs/research/timesheets.md": """# Timesheets research

- Jobber: workers edit their own timesheets until a manager approves them; overtime is flagged for approval.
- Connecteam: managers approve timesheets weekly; overtime above a daily limit needs approval.
""",
    # invoice-export: blocked on Jafar's design approval
    "Memory/campaigns/invoice-export/NOW.md": """# Invoice export — now

**Goal:** Owners send their accountant a clean invoice spreadsheet in two clicks.
**Core agreement — read on every resume:** `docs/invoice-export-behavior-contract.md` § Summary
**Plan:** `docs/invoice-export-behavior-contract.md` — first version approved 2026-10-08
**Stage:** Design

**In progress:** none

**Next part:** 2 Build the export — after Jafar approves the export dialog design

**Blockers:** Jafar's approval of the "Export dialog" frame in `concept.pen` (shown to him 2026-10-15)
""",
    "Memory/campaigns/invoice-export/ROADMAP.md": """# Invoice export — roadmap

**Plan:** `docs/invoice-export-behavior-contract.md` — scope and build order approved 2026-10-08

| Part | Plan section | Delivers | Waits for | Done when | State |
| --- | --- | --- | --- | --- | --- |
| 1 Export dialog design | § First version | the approved dialog look | — | Jafar approved the "Export dialog" frame | Waiting for Jafar |
| 2 Build the export | § First version | a CSV of the chosen invoices | 1 | the CSV opens in a spreadsheet with every column | Not started |
""",
    "docs/invoice-export-behavior-contract.md": """# Invoice export

**Status:** First version approved by Jafar on 2026-10-08.

## Summary

Owners pick a date range and download their invoices as a CSV file their accountant can open.

## First version

- Date range, then download. Columns: number, client, date, total, paid.
""",
    # job-checklists: its only movable part is claimed by another session in a worktree
    "Memory/campaigns/job-checklists/NOW.md": """# Job checklists — now

**Goal:** Crews tick off each job step on site, so owners know the work was done right.
**Core agreement — read on every resume:** `docs/job-checklists-behavior-contract.md` § Summary
**Plan:** `docs/job-checklists-behavior-contract.md` — first version approved 2026-10-04
**Stage:** Building

**In progress:**

- 2 Crew tick-off screen — worktree `.worktrees/job-checklists-2`, branch `job-checklists-2`

**Next part:** 3 Owner checklist report — waits for 2

**Blockers:** none
""",
    "Memory/campaigns/job-checklists/ROADMAP.md": """# Job checklists — roadmap

**Plan:** `docs/job-checklists-behavior-contract.md` — scope and build order approved 2026-10-04

| Part | Plan section | Delivers | Waits for | Done when | State |
| --- | --- | --- | --- | --- | --- |
| 1 Checklist templates | § First version | owners create a checklist for a job type | — | a template saves and shows on new jobs | Done 2026-10-09 |
| 2 Crew tick-off screen | § First version | crews tick steps on their phone | 1 | ticks save and show to the owner | In progress |
| 3 Owner checklist report | § First version | owners see unticked steps per job | 2 | the report lists every unticked step | Not started |
""",
    "docs/job-checklists-behavior-contract.md": """# Job checklists

**Status:** First version approved by Jafar on 2026-10-04.

## Summary

Owners attach a checklist to each job type; crews tick off the steps on their phone while on site.

## First version

- Checklist templates per job type, a tick-off screen for crews, and an owner report of unticked steps.
""",
    # price-book-import: last part verifying, campaign ready to finish
    "Memory/campaigns/price-book-import/NOW.md": """# Price book import — now

**Goal:** Owners import their whole price list from a spreadsheet instead of retyping it.
**Core agreement — read on every resume:** `docs/price-book-import-behavior-contract.md` § Summary
**Plan:** `docs/price-book-import-behavior-contract.md` — first version approved 2026-09-30
**Stage:** Verifying

**In progress:**

- 3 Final proof — `parts/3-final-proof.md`

**Next part:** none — Part 3 is the last part

**Blockers:** none
""",
    "Memory/campaigns/price-book-import/ROADMAP.md": """# Price book import — roadmap

**Plan:** `docs/price-book-import-behavior-contract.md` — scope and build order approved 2026-09-30

| Part | Plan section | Delivers | Waits for | Done when | State |
| --- | --- | --- | --- | --- | --- |
| 1 Import rules | § Importing a price list | rows become items; bad rows are listed | — | `python3 checks/price_import_check.py` passes for rules | Done 2026-10-06 |
| 2 Preview screen | § First version | the preview of rows to add and problems | 1 | the preview matches the approved frame in the live app | Done 2026-10-12 |
| 3 Final proof | § Success checks | both success checks proven | 1, 2 | both success checks pass in the live app and `python3 checks/price_import_check.py` passes | In progress |
""",
    "Memory/campaigns/price-book-import/parts/3-final-proof.md": """# Part 3 — Final proof

**Campaign:** price-book-import · **Plan:** `docs/price-book-import-behavior-contract.md` § Success checks
**Stage:** Verifying
**Code:** `main`
**Done when:** both success checks pass in the live app and `python3 checks/price_import_check.py` passes

## Steps

- [x] Jafar tried both success checks in the live app (2026-10-16)
- [ ] Run the automated done-check

## Next

Run `python3 checks/price_import_check.py`. If it passes, Part 3 is done, and so is the campaign.

## Proof

- Jafar's live-app walk-through, both checks passed — `docs/research/price-import-proof.md`
""",
    "docs/price-book-import-behavior-contract.md": """# Price book import

**Status:** First version approved by Jafar on 2026-09-30.

## Summary

Owners upload their price list as a spreadsheet (CSV) and every row becomes an item in their price book, so
they don't retype hundreds of prices.

## First version

- CSV upload with name, description, and unit price columns.
- A preview showing the rows that will be added and the rows with problems.

## Importing a price list

- Rows with a missing name or a price that is not a number are listed as problems and not imported.
- Importing twice does not create duplicates: a row whose name already exists updates that item's price.

## Success checks

- A 3-row CSV with one bad price → the preview shows 2 to add and 1 problem; importing adds 2.
- Importing the same file again adds nothing new.

## Not doing

- Excel (.xlsx) files — later version.

## Sources and design decisions

- Import preview design: `concept.pen` frame "Price import preview" (approved 2026-10-01).
""",
    "docs/research/price-import-proof.md": """# Price import — live proof

2026-10-16, Jafar in the live app with the owner login:

- A 3-row CSV with one bad price: the preview showed 2 to add and 1 problem; importing added 2. Passed.
- Importing the same file again added nothing new. Passed.
""",
    "app/price_book/__init__.py": "",
    "app/price_book/importer.py": '''"""Imports a price list CSV into the price book."""

import csv
import io


def preview(csv_text):
    rows, problems = [], []
    for row in csv.DictReader(io.StringIO(csv_text)):
        try:
            price = float(row["unit price"])
        except ValueError:
            problems.append(row)
            continue
        if not row["name"].strip():
            problems.append(row)
            continue
        rows.append({"name": row["name"].strip(), "price": price})
    return rows, problems


def import_rows(price_book, rows):
    added = 0
    for row in rows:
        if row["name"] not in price_book:
            added += 1
        price_book[row["name"]] = row["price"]
    return added
''',
    "checks/price_import_check.py": '''"""Done-check for price-book-import."""

import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from app.price_book.importer import import_rows, preview  # noqa: E402

CSV = "name,description,unit price\\nGutter clean,Per metre,4.50\\nRoof check,Visual,abc\\nDrain flush,Per drain,30\\n"
rows, problems = preview(CSV)
assert len(rows) == 2 and len(problems) == 1, (rows, problems)
book = {}
assert import_rows(book, rows) == 2
assert import_rows(book, preview(CSV)[0]) == 0
print("price import check passed")
''',
    # a small task outside any campaign
    "docs/help/notice.md": """# Notice

Clients will recieve a text when their quote is ready.
""",
}

if dest.exists():
    shutil.rmtree(dest)
dest.mkdir(parents=True)
for name in ("CLAUDE.md", "AGENTS.md"):
    shutil.copy(project_root / name, dest / name)
shutil.copytree(
    project_root / ".claude" / "skills",
    dest / ".claude" / "skills",
    ignore=shutil.ignore_patterns("campaign-memory"),
)
shutil.copytree(skill_dir, dest / ".claude" / "skills" / "campaign-memory")
for path, text in FILES.items():
    target = dest / path
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(text)


def run(*args, cwd=dest):
    subprocess.run(args, cwd=cwd, check=True, capture_output=True, text=True)


run("git", "init", "-q", "-b", "main")
run("git", "config", "user.name", "Test Agent")
run("git", "config", "user.email", "test@example.invalid")
run("git", "add", "-A")
run("git", "commit", "-q", "-m", "Test project")
run("git", "worktree", "add", "-q", "-b", "job-checklists-2", ".worktrees/job-checklists-2")
run(
    "python3", ".claude/skills/agent-coordination/scripts/agent-work.py", "claim",
    "job-checklists", "2-crew-tick-off-screen", "--owner", "other-session-opus",
    "--mode", "write", "--area", "job-checklists",
    cwd=dest / ".worktrees" / "job-checklists-2",
)
print(f"built {dest}")
