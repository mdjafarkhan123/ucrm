# Part 7 — Client work + schedule

**Campaign:** deferred-sweep-2 · **Plan:** `docs/client-property-behavior-contract.md` (Details view: Work Overview = Item, Address, Date, Status, Amount; Client Schedule = Schedule, Title, Assigned) · spec `Memory/deferred/client-work-overview-and-schedule-sections-are-empty.md`
**Code:** `main`
**Done when:** the client page's two boxes show the client's real work

## Steps

- [x] Requests/Quotes/Jobs list routes accept `client_id` (Invoices already did)
- [x] `src/lib/clients/work.ts` + `ClientWorkOverview.svelte`: All work (newest 10) + per-type paged view
- [x] `client_schedule_rows` DB function + `/api/clients/[id]/schedule` + `ClientSchedule.svelte` (Upcoming incl. Overdue / Past)
- [x] Wired into the client page; unit tests for those APIs pass; browser-checked as office login
- [ ] Fix Work overview table width, then re-verify and close the part

## Next

At 1400px wide the client page's main column is ~620px and the Work overview table still pushes the Amount
column off the right edge (address and title already clipped to 120px / 170px in
`src/lib/components/clients/ClientWorkOverview.svelte`). Look at `DataTable.svelte` cell padding and pick a
fix that keeps all five columns visible (e.g. a shorter date, or tighter cells). Re-run
`node p7-verify.mjs dev.jafarkhan+office@gmail.com 'PaidLaunch16!' 468350d0-2eee-4cdc-8b81-bf8ea0b46eeb tester`
(uncommitted helper in the project folder; screenshots go to the session scratchpad — edit the SHOT path);
delete the script when done. Then close the part: delete the deferred note + its INDEX row, mark Done.

## Outside actions

- Migration `20260929210000_client_schedule_rows` pushed — check: `supabase migration list --linked` — done

## Notes

- The data refreshes every time the client page opens (staleTime 0), because work is edited on other pages.
- A member without quotes/invoices access gets a 403 from that list; that type is simply left out.
- Property filter (Jobber has one) was not built; mention it to Jafar as a possible follow-up.
