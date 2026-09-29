# Part 4 — Held-booking status ("Needs approval")

**Spec:** `Memory/deferred/request-needs-approval-status-has-no-label.md`. Jafar: "Follow Jobber". Jobber
(help.getjobber.com "Requests and Bookings Settings"): held bookings read **Needs approval**, listed first in
the Requests Overview; the office clicks **Accept and Schedule** to confirm, or Mark as lost to decline.

**Decisions:** booking the assessment is the approval — it moves `needs_approval` to `unscheduled`, as it
already did for `new`, so the request can then be converted and moved in the pipeline. Tone: warning (orange).

## Steps

- [x] Label, tone, stored-status list (`src/lib/requests/statuses.ts`); status filter branch + open list
      (`src/lib/server/requests/status.ts`, spec updated); Overview row first (`requests/+page.svelte`)
- [x] Assessment route flips `needs_approval` → `unscheduled` (`api/requests/[id=uuid]/assessment/+server.ts`)
- [x] Detail page: button "Accept and schedule"; Assessment fact shows the customer's requested time
- [ ] `svelte-check` (only the 3 known union-type errors are allowed)
- [ ] Browser check on Raad LTD's "M5Gate Test" request: orange badge in list, Status filter finds it,
      Overview shows it; open it, Accept and schedule, then it reads Upcoming and can convert. Desktop + phone.
- [ ] Close: delete the deferred note + INDEX row, mark Done in ROADMAP, delete this note

**Next:** run `svelte-check`, then the browser check above. The code is committed on `main`.
