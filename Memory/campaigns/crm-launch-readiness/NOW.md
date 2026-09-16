# CRM Launch Readiness: Current Checkpoint

## Goal

Complete the nine-part path to a controlled first launch, then widen access only from measured customer and
production evidence.

## Current state

- Part 1 is complete.
- Part 2 is complete 2026-09-17 — the opening-balances assisted-import wizard shipped, browser-verified, and
  committed (`onboarding-and-data-portability` campaign closed, its Memory folder removed).
- Part 3 is complete 2026-09-16 — `financial-reconciliation` campaign closed all 6 parts; its Memory folder is
  removed. Detail lives in code, migrations, tests and `docs/financial-reconciliation-contract.md`.
- Part 4 (minimum website speed-to-lead) is now dependency-ready — Part 3 and the existing Website Chat, email,
  and Automation it builds on are all in place. Not yet researched or planned.
- Part 9 preparation may run beside remaining parts, but infrastructure implementation still needs Jafar's
  separate topology and migration approval.
- Parts 5–7 follow the controlled first launch; Part 8 is chosen from evidence from those early customers.

## Exact next action

Start Part 4 (minimum website speed-to-lead): research how comparable products (Jobber — see
`.claude/skills/jobber/SKILL.md`) handle speed-to-lead, and inspect the existing Website Chat, email, and
Automation code this builds on, before proposing an implementation plan to Jafar per CLAUDE.md Rule 2. This is
a new feature area, not yet scoped — expect it to need its own campaign registration (goal, ordered parts,
completion gate) before implementation starts.

## Essential pointers

- `docs/crm-launch-implementation-roadmap.md` (Part 4 scope: "Form/Chat creates or matches one lead and sends
  at most one eligible reply, stopping on human activity")
- `.claude/skills/jobber/SKILL.md`

Jafar's only required resume command: `continue the CRM launch-readiness campaign`.
