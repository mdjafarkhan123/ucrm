# Jafar Panel: Current Checkpoint

## Goal

Finish the approved Platform Owner journey from public contractor application through commercial
control, support recovery, closure, and dependency-linked provider controls.

## Active part

None. Part 9 (recoverable closure and strict purge) closed after Jafar browser-verified closure
start -> restore and closure start -> early delete on a disposable test organization. Parts 0
through 9 are all complete.

## Exact next action

No dependency-ready part exists yet. Part 10 (dependency-linked provider and CRM controls) is
blocked until a contractor-facing subsystem it depends on ships (phone/SMS via Twilio, tenant email
domains via Brevo, Stripe payment readiness, webchat, or review links -- see ROADMAP's "Dependency-
linked Part 10 slices"). Part 11 (final A-Z audit) depends on Part 10. When Jafar brings a
contractor subsystem to build against, create that slice's packet under
`Memory/campaigns/jafar-panel/parts/` and resume here.

## Current truth

- Parts 0 through 9 are complete and closed.
- Part 9 delivered: recoverable 30-day organization closure with contractor notices, a real daily
  `pg_cron` purge job, strict cascading purge with a non-personal deletion receipt, Overview
  Close/Restore UI, a Settings > Cleanup early-delete page, four closure email templates, and two
  pgTAP suites (27/27, 30/30). Full details: `Memory/campaigns/jafar-panel/parts/9-recoverable-closure-and-strict-purge.md`.
- One item deferred from Part 7, still not blocking: the non-admin email-correction branch of "Fix
  profile" has never been browser-verified, because no organization on the platform currently has a
  non-owner/non-admin member. See `Memory/deferred/INDEX.md`.
- Remote Supabase MCP tools and `npx supabase gen types` against the remote project both work in
  this environment; no local Docker/CLI. `mcp__supabase__execute_sql` only surfaces the result of
  the last statement in a script, so multi-assertion pgTAP verification needs the checks aggregated
  into one `string_agg(...)` query rather than run as separate `select` statements. Also: any table
  that is deliberately not scoped to one organization (e.g. `organization_deletion_receipts`) can
  carry real rows from earlier live verification -- scope test assertions to a captured id, never to
  `limit 1` or a bare `count(*)`.

## Blockers

Part 10 is blocked on a contractor-facing subsystem existing to build eligibility/health/history/
recovery controls against. Not actionable until Jafar starts that contractor module.

## Protected work

- Preserve all unrelated dirty work, including the existing `CLAUDE.md`, `.claude/settings.local.json`,
  `LocationPicker`, `TimezonePicker`, `country-state-city`, design-skill, and application changes.

## Required pointers

- `Memory/campaigns/jafar-panel/ROADMAP.md`.
- `Memory/deferred/INDEX.md` (non-admin email-correction verification gap).

## Active-part completion gate

Not applicable -- no part is active.
