# C5 — Fill CRM settings

**Campaign:** client-onboarding-delivery · **Plan:** `docs/client-onboarding-delivery-behavior-contract.md` §4 (Jafar's choices of 2026-10-05, C5)
**Code:** `main`
**Done when:** Repeating it creates no duplicates and keeps the owner's later edits

## Steps

- [x] Jafar chose: copy on Accept (and on recording a help answer); newest word wins; setup time zone/currency count as confirmed
- [ ] Migration: last-copied values table + `owner_apply_setup_settings` (service role only)
- [ ] Server: accepted built-in values → settings payload; called from the review and help-answer routes
- [ ] Setup tab: "Copied to settings" / "Kept their own Settings change" lines
- [ ] Tests, then browser check on Raad LTD

## Next

Write the migration.

## Notes

- "Newest word": write a setting when it is empty, still equals what setup last copied, or the answer's send
  (the first send that held this value) is newer than the section's last edit by a person. Skip when the
  answer equals what setup last copied (nothing new from the client).
- Address (lines, city, region, postcode, country) is copied as one unit, only with line 1, city and country.
