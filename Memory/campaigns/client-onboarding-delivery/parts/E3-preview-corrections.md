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

All code is committed (session paused 2026-10-05). Route and logic tests pass, and both new components compile in
the Svelte checker. The full type check was cut off and never finished on the screens.
1. Run the type check (`NODE_OPTIONS=--max-old-space-size=8192 npx svelte-check --threshold error`) and fix errors in
   `SetupPreviewPanel.svelte` (Jafar's Setup tab), `components/setup/SetupPreview.svelte`, `PreviewScreenshots.svelte`,
   `PreviewCardBody.svelte`.
2. Browser check on Raad LTD. It needs Ready first; Raad is accepted only on "Your business". Ask Jafar before
   adding a Ready row on dev by hand, and remove it afterwards. Path: write cards → release (email) → client marks
   cards and sends once → Jafar sorts → client sees the labels → version 2 offers only "Uplift made a mistake" and
   "Something new". Also check that a screenshot upload works on both sides.
3. Then mark E3 done and point NOW.md at E4.

## Outside actions

- Test-only Ready row for Raad LTD (`18f0d717-904e-48d8-bd99-9df7e3844cda`), inserted by hand 2026-10-05 with Jafar's OK for the browser check — check: `select * from organization_setup_ready where organization_id = '18f0d717-904e-48d8-bd99-9df7e3844cda' and ready_by_email = 'e3-browser-check@uplift.test'`. Remove it and Raad's previews afterwards.
- Code fixes are on branch `e3-preview-checks` in worktree `../Ucrm-e3` (a Codex session holds the main folder).
- Apply migration to dev — check: `select 1 from supabase_migrations.schema_migrations where version = '20261101090000'`
