# D3a Lead owners

**Done when:** a Lead assigned to Sam (`dev.jafarkhan+uplift-sales@gmail.com`) sends its reminder to Sam's email and bell, not Jafar's; removing Sam returns it to Jafar. Plan § 6 and § Team access hold Jafar's 2026-10-09 answers.

**Outside action:** database change `20261108090000_uplift_lead_owners` is applied to the live database (check: `select version from supabase_migrations.schema_migrations where name = 'uplift_lead_owners'`). Do not apply it again. App types regenerated from the live schema.

## Steps

- [x] Database: owner on each business, owner change command with history line, reminders and calls follow the owner, removal hands work back to Jafar, each person's bell, owner on Lead page and Leads list with filter.
- [x] Server: `/api/jafar/leads/[id]/owner` (choices + change), owner filter on the Leads list, bell reads and read-marks scoped to the viewer, teammates may open their bell, reminder worker sends in-app alerts to the owner's bell.
- [x] Screens: shared `components/jafar/OwnerPicker.svelte` (ClientPanel now uses it too), Owner first in the Lead page header, Owner column and filter on Leads, "Now owned by …" history line.
- [x] Unit tests written and passing (owner route, Leads filter, bell scoping, reminder recipient, gate).
- [ ] `npm run check` clean, lint/prettier on changed files.
- [ ] Database proof: as Jafar, hand a test Lead with a due follow-up to Sam; confirm `platform_reminders.recipient_member_id` is Sam's id; book a call and confirm it is Sam's; remove-then-restore is NOT safe on Sam (removal is final) — prove removal on a throwaway invited-and-accepted teammate instead, or in a rolled-back transaction.
- [ ] Browser screen check (design skill): Lead page owner picker, Leads Owner column/filter, Sam's bell — desktop and phone.
- [ ] Speed: Leads list with owner filter on the 50k lab data (`stages/C-your-day.md` baseline method).
- [ ] Mark Done in `stages/D-team.md`, delete this note.

**Next:** run `npm run check` and fix anything it reports, then the database proof above.
