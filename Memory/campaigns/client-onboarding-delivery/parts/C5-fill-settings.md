# C5 — Fill CRM settings

**Campaign:** client-onboarding-delivery · **Plan:** `docs/client-onboarding-delivery-behavior-contract.md` §4 (Jafar's choices of 2026-10-05, C5)
**Code:** `main`
**Done when:** Repeating it creates no duplicates and keeps the owner's later edits

## Steps

- [x] Jafar chose: copy on Accept (and on recording a help answer); newest word wins; setup time zone/currency count as confirmed
- [x] Migration `20261030090000_setup_settings_copy` (pushed to dev): `owner_copy_setup_settings`; rules checked by SQL dry runs on Raad
- [x] `$lib/setup/settings-copy.ts` + `$lib/server/setup/settings-copy.ts`; called from review, help-answer and new `setup/settings-copy` routes
- [x] Setup tab "CRM settings" box with Fill in again (`ClientSetupAnswers.svelte`)
- [ ] Tests, then browser check on Raad LTD

## Next

Finish `npm run check` (needs NODE_OPTIONS=--max-old-space-size=8192), then browser check: accept Raad's "Your business" again is not possible (already accepted) — press Fill in again on its Setup tab and read the CRM settings box; then Raad owner's Settings shows the phone.

## Notes

- "Newest word": write a setting when it is empty, still equals what setup last copied, or the answer's send
  (the first send that held this value) is newer than the section's last edit by a person. Skip when the
  answer equals what setup last copied (nothing new from the client).
- Address (lines, city, region, postcode, country) is copied as one unit, only with line 1, city and country.
