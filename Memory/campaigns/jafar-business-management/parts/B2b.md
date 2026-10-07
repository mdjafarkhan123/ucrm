# B2b — Editing a Lead's details

**Campaign:** jafar-business-management · **Plan:** `docs/jafar-business-management-behavior-contract.md` § 1. Find and prepare a lead
**Code:** `main`
**Done when:** Jafar fixes a typo in a Lead's email; its history and any logged contact keep pointing to that detail.

## Steps

- [x] Migration `20261007071519_uplift_lead_details_edit` (applied; tested in a rolled-back transaction)
- [x] API `PATCH /api/jafar/leads/[id]/details` + validation + tests; duplicate check accepts `exclude_id`
- [x] Lead page edits in place: business (pencil by the name), Contact details card, About card. Shared pieces: `LeadBlockEditor`, `LeadContactRows`, `LeadDuplicateWarning` (add form uses the last two too)
- [x] History shows "Details changed" lines and a "Removed" tag; editing an old entry keeps its removed detail
- [ ] Browser check, desktop + phone width: fix "info@smithplumbng.co.uk" on a test Lead that has a logged email → the history shows the corrected address and a "Details changed" line; remove a used phone → "Removed" tag; the add form at `/jafar/leads/new` still looks and works the same; contact rows fit the narrow side card
- [ ] Run ESLint on the changed files (it ran out of memory this session; try `NODE_OPTIONS=--max-old-space-size=8192`)
- [ ] Performance check: the page stays one request; editors load nothing until opened (duplicate check only after typing)
- [ ] Add Jafar's decisions to plan § 1, mark B2b done

## Next

Do the browser check above (Jafar login `/jafar`, see CLAUDE.md), then the remaining steps.

## Notes

Jafar's decisions (2026-10-07): edit in place, block by block (Pipedrive/HubSpot style); every save adds one short history line (fit notes say only "Updated why they may fit"); a removed contact detail stays in old history tagged "Removed" and can never be chosen again.
Build choices: correcting a detail's text keeps the same detail (history follows); a saved detail's type can't change (remove and add instead); contact edits are sent as add/change/remove so two people's edits don't undo each other.
