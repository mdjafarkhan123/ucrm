# Contractor Settings: Current Checkpoint

## Goal

Give contractors one permission-aware control room for business identity and feature-owned settings.

## Where things stand

Part 3 (Team and access) closed 2026-09-12. The two live-verification gaps found 2026-09-11 (invitation
lifecycle events never recorded; `member.work_unassigned` falling to a generic sentence) are both fixed and
re-verified live on Raad LTD — see `ROADMAP.md`'s Part 3 row for the detail. Committed this session.

Part 4 (Request and booking forms) is next. Dependency check: Requests and Scheduling are both shipped,
working production features (visible in nav, real data flowing) — no owning campaign blocks them. Part 4 is
dependency-ready, but has no approved plan yet.

## Blockers

None.

## Exact next action

Per the Working Procedure (non-trivial work), inspect the current Request/booking-form code and the `jobber`
skill's relevant research, then present Jafar a plan for Part 4 (public forms + creation outcomes end to end)
before writing any code.

## Essential pointers

- `docs/contractor-settings-blueprint.md` — permanent behavior reference
- `Memory/campaigns/contractor-settings/ROADMAP.md` — read only when planning Part 4 or resolving a dependency

Resume command: `continue contractor settings`.
