# B2b — Editing a Lead's details

**Campaign:** jafar-business-management · **Plan:** `docs/jafar-business-management-behavior-contract.md` § 1. Find and prepare a lead
**Code:** `main`
**Done when:** Jafar fixes a typo in a Lead's email; its history and any logged contact keep pointing to that detail.

## Steps

- [ ] Migration: contact details can be removed without disappearing (removed date); a "details changed" history entry; one save function for the business, contact details and About, writing one history line per save
- [ ] API route + validation + tests
- [ ] Lead page: edit in place — business (hero), contact details card, About card (source, source details, fit notes); possible-duplicate warning reused from the add form
- [ ] History shows the change line and a "removed" tag on a removed detail
- [ ] Plan updated with Jafar's decisions; browser check desktop + phone; commit

## Next

Write the migration (`supabase/migrations/<ts>_uplift_lead_details_edit.sql`).

## Notes

Jafar's decisions (2026-10-07): edit in place, card by card (Pipedrive/HubSpot style), not a separate edit page. Every save adds one short history line ("Jafar changed the email from … to …"; fit notes say only "updated why they may fit"). A removed contact detail stays in old history tagged "removed", leaves the contact list, and can never be chosen again.
Build choices: editing a detail's text keeps the same detail (history follows the fix); a detail's type cannot change — remove and add instead. Contact-detail edits are sent as add/change/remove operations, not a whole list, so two people's edits don't erase each other.
