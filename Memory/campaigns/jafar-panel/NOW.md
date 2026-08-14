# Jafar Panel: Current Checkpoint

## Goal

Finish the approved Platform Owner journey from public contractor application through commercial
control, support recovery, closure, and dependency-linked provider controls.

## Active part

6E closed 2026-08-14 (legacy `pending_setup` organization reconciliation) — browser-verified live:
suspended the real admin-less `xdasd` organization end to end, and confirmed the full activation
readiness checklist and step-up gate on a seeded fully-eligible legacy organization (`Riverside
Legacy Demo`, stopped at the password prompt per credential-entry policy — Jafar can complete that
single click himself later if he wants the full round trip witnessed). All acceptance checks pass;
see the closed packet for durable gotchas (a real 6A check-constraint bug found and fixed via pgTAP
before it reached the API layer).

6F (searchable organization directory and attention queues) is next, dependencies 6A/6E both
complete, but its packet does not exist yet. The current directory
(`src/routes/jafar/(protected)/organizations/+page.svelte`) loads every organization client-side
with client-side search/filter — no server pagination yet.
`docs/jafar-completion-contract.md` heading `Commercial control decisions` already gives the approved
shape: "Protected directory search covers organization name, slug, and primary administrator email.
Pagination uses `created_at, id` with a default page size of 50." Attention-queue specifics (which
summaries/filters count as "needs attention" beyond lifecycle status) are not yet pinned down.

## Exact next action

Start 6F: read `docs/jafar-completion-contract.md` heading `Organization and commercial control` and
`docs/jafar-organization-management-mission.md` heading `Organization-detail structure`, check how
many real organizations exist in the remote project (client-side loading is currently fine at this
scale but the acceptance gate requires server pagination regardless), grill Jafar on attention-queue
specifics, then propose the plan and wait for approval before creating
`Memory/campaigns/jafar-panel/parts/6f-*.md`.

## Current truth

- Parts 0 through 6E are complete.
- `xdasd` is now permanently `suspended` (real action on real data, not a test rollback).
  `Riverside Legacy Demo` (`7e37a58f-60e4-40ee-bb4a-cf13966a7a3d`) is a seeded demo org, still
  `pending_setup` and fully activation-eligible, safe to leave as is.
- `database.types.ts` was regenerated against the remote project as part of 6E.

## Blockers

- None for 6E. Docker and the Supabase/psql CLIs remain unavailable locally; database work continues
  to go through the linked remote project via Supabase MCP tools, not `db push`.

## Protected work

- Preserve all unrelated dirty work in the repository.
- In particular, do not absorb or commit the existing `LocationPicker`, `TimezonePicker`,
  `country-state-city` dependency, design-skill, or unrelated application changes as campaign work.

## Required pointers

- `Memory/campaigns/jafar-panel/ROADMAP.md`.
- `Memory/campaigns/jafar-panel/parts/6e-legacy-organization-reconciliation.md` (closed — reference
  only, do not resume).
- `docs/jafar-completion-contract.md`, heading `Organization and commercial control`.
- `docs/jafar-organization-management-mission.md`, heading `Organization-detail structure`.

## Active-part completion gate

All 6F acceptance checks in the part packet pass, including pgTAP/route tests where relevant, remote
advisors, and browser verification on real organizations.
