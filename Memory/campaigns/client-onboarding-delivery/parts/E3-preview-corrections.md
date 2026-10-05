# E3 — Preview + correction

**Campaign:** client-onboarding-delivery · **Plan:** `docs/client-onboarding-delivery-behavior-contract.md` §6 (Jafar's choices of 2026-10-05, E3)
**Code:** `main`
**Done when:** Client submits corrections once; extra scope is flagged

## Steps

- [x] Jafar's choices recorded in plan §6
- [ ] Migration: previews (versioned cards), the client's notes, Jafar's save/release/sort commands, the client's save/send commands, list states
- [ ] Apply to dev, regenerate types
- [ ] `$lib/setup/preview.ts` (choices per round, labels) + spec; project state 8 "Ready for your review" and the "corrections sent" note
- [ ] Jafar's API + Setup-tab preview panel (write cards, release, sort notes); release email to owners/admins
- [ ] Client preview on `/setup` (cards, choices, notes autosave, Send my corrections once)
- [ ] Screenshots on cards and notes (reuse Chat with Uplift's upload pattern, `$lib/server/support/attachments.ts`)
- [ ] Checks, browser check on Raad LTD, commit

## Next

Write the migration (next number after `20261031090000`), modelled on E2's and C4's.
