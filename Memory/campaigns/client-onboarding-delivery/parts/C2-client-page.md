# C2 — Client page

**Campaign:** client-onboarding-delivery · **Plan:** `docs/client-onboarding-delivery-behavior-contract.md` § 8, § 5
**Code:** `main`
**Done when:** Jafar reads a submitted client's answers by section

## Steps

- [x] Migration `20261025090000_setup_client_page.sql`: version catalogue for the owner, pause/resume reminders (audited), onboarding list knows sends (`review_setup`, waiting on Uplift)
- [x] Apply migration to dev, regenerate database types
- [x] Shared `SetupAnswerList` component (from the check-and-send page's answer list), used by both pages
- [x] GET `/api/jafar/organizations/[id]/setup?send=N` (sends, chosen send read back against its own version, files, confirmations, reminders, changes since newest send); PATCH `.../setup/reminders`
- [x] Setup tab shows it above Protected documents; onboarding list rows link to `?tab=setup`, "Review their setup" label
- [x] Unit tests, lint, type check (one old error in `reminder-emails.spec.ts` from B13, not ours)
- [ ] Finish browser check on Raad LTD: scroll the Setup tab — photos open in the viewer, help/not-yet answers, "What they confirmed"; reminders block shows the sentence, not a switch, after a send; check a phone width

## Next

Finish the browser check on Raad LTD (`/jafar/organizations/18f0d717-904e-48d8-bd99-9df7e3844cda?tab=setup`; the top of the tab and the onboarding list already look right). Then close C2: mark done in `stages/C-review.md`, point NOW.md at C3, delete this note.

## Outside actions

- Dev migration 20261025090000 — check: `npx supabase migration list --linked` shows it remote — done 2026-10-04

## Notes

Lives in the existing Setup tab of `/jafar/organizations/[id]` (its comment reserved it for stage C), not a new page.
