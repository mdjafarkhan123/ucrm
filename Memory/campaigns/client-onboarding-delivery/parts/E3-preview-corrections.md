# E3 — Preview + correction

**Campaign:** client-onboarding-delivery · **Plan:** `docs/client-onboarding-delivery-behavior-contract.md` §6 (Jafar's choices of 2026-10-05, E3)
**Code:** `main`
**Done when:** Client submits corrections once; extra scope is flagged

## Steps

- [x] Jafar's choices recorded in plan §6
- [x] Migration `20261101090000_setup_previews.sql`: previews (versioned cards), the client's notes, Jafar's save/release/sort commands, the client's save/send commands, list states
- [x] Apply to dev, regenerate types (checked in a rolled-back run: release once, round rules, send once, old version refused)
- [x] `$lib/setup/preview.ts` (choices per round, labels) + spec; project state 8 "Ready for your review" and the "corrections sent" note
- [x] Jafar's API + Setup-tab preview panel (write cards, release, sort notes); release email to owners/admins
- [x] Client preview on `/setup` (cards, choices, notes autosave, Send my corrections once)
- [x] Screenshots on cards and notes (reuse Chat with Uplift's upload pattern, `$lib/server/support/attachments.ts`)
- [ ] Checks, browser check on Raad LTD, commit

## Next

Branch `e3-preview-checks` (worktree `../Ucrm-e3`, its dev server on port 5174) holds: the type-check fix, and a
found bug fixed — a preview note now saves while typing and on leaving the page (was: only on clicking out; a
reload lost it), with a component test. Not yet on `main`.
Browser-checked on Raad LTD: write, screenshots both sides, release + email (Jafar pressed), client marks and
sends once (second send says already sent), Jafar sorts, client sees Correction / New request labels.
1. Version 2 draft is saved on Jafar's side. Waiting for Jafar to press Release on it (it emails again); then
   check the client sees only "Uplift made a mistake" and "Something new".
2. Full type check, merge the branch into `main`, remove worktree and branch, stop port 5174.
3. Clean up test rows (below), mark E3 done, point NOW.md at E4.

## Outside actions

- Test-only Ready row for Raad LTD (`18f0d717-904e-48d8-bd99-9df7e3844cda`), inserted by hand 2026-10-05 with Jafar's OK for the browser check — check: `select * from organization_setup_ready where organization_id = '18f0d717-904e-48d8-bd99-9df7e3844cda' and ready_by_email = 'e3-browser-check@uplift.test'`. Remove it and Raad's previews and notes afterwards (rows in `organization_setup_previews`, `organization_setup_preview_notes`).
- Code fixes are on branch `e3-preview-checks` in worktree `../Ucrm-e3` (a Codex session holds the main folder).
- Apply migration to dev — check: `select 1 from supabase_migrations.schema_migrations where version = '20261101090000'`
