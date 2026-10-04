# C2 — Client page

**Campaign:** client-onboarding-delivery · **Plan:** `docs/client-onboarding-delivery-behavior-contract.md` § 8, § 5
**Code:** `main`
**Done when:** Jafar reads a submitted client's answers by section

## Steps

- [x] Migration `20261025090000_setup_client_page.sql`: version catalogue for the owner, pause/resume reminders (audited), onboarding list knows sends (`review_setup`, waiting on Uplift)
- [ ] Apply migration to dev, regenerate database types
- [ ] Shared `SetupAnswerList` component (from the check-and-send page's answer list), used by both pages
- [ ] GET `/api/jafar/organizations/[id]/setup?send=N` (sends, chosen send read back against its own version, files, confirmations, reminders, changes since newest send); PATCH `.../setup/reminders`
- [ ] Setup tab shows it above Protected documents; onboarding list rows link to `?tab=setup`, "Review their setup" label
- [ ] Tests, checks, browser check on Raad LTD (one dev send)

## Next

Apply the migration (`npx supabase db push --linked`), then build the API.

## Outside actions

- Dev migration 20261025090000 — check: `npx supabase migration list --linked` shows it remote — pending

## Notes

Lives in the existing Setup tab of `/jafar/organizations/[id]` (its comment reserved it for stage C), not a new page.
