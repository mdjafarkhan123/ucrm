# Time clock Part 7 — weekly approval proof (2026-10-12)

Branch dev server on port 5174, remote dev database, business Raad LTD. Logins from `Login.md`: the
contractor owner, and the Field member (`Field Tester`). Script: `journey.mjs` in this folder.

## Database (rolled back, before applying `20261210090000_weekly_approval`)

`database-proof.sql` → `database-proof-output.txt`: a crew member with "Record and change their own hours"
is refused on approved hours on Timesheets and Job Labor; the manager still edits; the entry stays approved
after a move; history reads added → approved → changed; a second approve finds nothing; a future day is
refused.

## Live app

**Owner, 1440px (`--approve`):** hovering Approve reads what is waiting; the dialog for Sun 11 Oct lists
Field Tester with 6 entries · 8m; Approve → toast "Approved 6 entries for 1 person." (no undo, so this was
the only approval run). Today's 12 Oct entry stays unapproved. 4/4 checks.

**Owner, 1440px and 390px (after approving):** the dialog shows "Nothing is waiting"; the person row shows
an Approved badge; 6 entries show Approved; the entry menu still offers Edit, History, Delete; Edit shows
the approved notice; Job #20 Labor shows "· Approved" on those lines. 7/7 checks at each width.

**Owner, `--running`, 390px and 1440px:** the owner clocks Field Tester in, opens Approve on today: the
running General timer is listed under "Still running, so not approved" while today's stopped entry can be
approved; the owner clocks them out again inside a minute (discarded, no stray entry — checked in the
database). 4/4 checks at each width.

**Field member, 390px and 1440px:** given "Record and change their own hours" for this run only (permission
override inserted, then deleted), so the approval lock rather than the timers-only rung is tested. No
Approve button; approved entries offer History only and come back `can_edit`/`can_delete` false; today's
unapproved entry still offers Edit, History, Delete; `/api` refuses with 409 "These hours are approved. Ask
a manager to change them." for Timesheets PATCH and DELETE and Job Labor PATCH. 7/7 checks at each width.

**Owner changes an approved entry (`manager-edit.mjs`):** a note added to one approved Job #20 entry through
the Timesheets route → 200; the entry is still approved with the same 3 minutes; its history reads
"stopped" (Field Tester) → "approved" (Jafar Khan) → the change with the new note.

## Screen check (Classic)

Screenshots here: `owner-approve-dialog-1440`, `owner-approved-1440`, `owner-nothing-waiting-*`,
`owner-approve-running-*`, `owner-approved-entries-*`, `owner-edit-approved-*`, `owner-job-labor-*`,
`field-approved-own-*`, `field-job-labor-own-*`. Two fixes after the first round: Job Labor rows on a phone
now put the cost and menu below the entry instead of squeezing it into a narrow column (an older layout
problem that the Approved line made worse), and the person row's badges on a phone line up with the entry
count. Second round at both widths: nothing further to fix.
