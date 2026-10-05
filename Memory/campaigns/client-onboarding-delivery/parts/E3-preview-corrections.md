# E3 — Preview + correction

**Campaign:** client-onboarding-delivery · **Plan:** `docs/client-onboarding-delivery-behavior-contract.md` §6 (Jafar's choices of 2026-10-05, E3)
**Code:** `main`
**Done when:** Client submits corrections once; extra scope is flagged

## Steps

- [x] Jafar's choices recorded in plan §6
- [x] Migration `20261101090000_setup_previews.sql`: previews (versioned cards), the client's notes, Jafar's save/release/sort commands, the client's save/send commands, list states
- [x] Apply to dev, regenerate types (checked in a rolled-back run: release once, round rules, send once, old version refused)
- [ ] `$lib/setup/preview.ts` (choices per round, labels) + spec; project state 8 "Ready for your review" and the "corrections sent" note
- [ ] Jafar's API + Setup-tab preview panel (write cards, release, sort notes); release email to owners/admins
- [ ] Client preview on `/setup` (cards, choices, notes autosave, Send my corrections once)
- [ ] Screenshots on cards and notes (reuse Chat with Uplift's upload pattern, `$lib/server/support/attachments.ts`)
- [ ] Checks, browser check on Raad LTD, commit

## Next

Write `src/lib/setup/preview.ts` (choices per round, labels) with a spec, then add state 8 to `project-state.ts`.

## Outside actions

- Apply migration to dev — check: `select 1 from supabase_migrations.schema_migrations where version = '20261101090000'`
