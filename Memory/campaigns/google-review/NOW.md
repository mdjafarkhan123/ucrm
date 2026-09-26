# Google review — NOW

Goal: build the Google review campaign in `docs/google-review-campaign-owner-brief.md`.
Active part: 3 — Manual "Request a review". Behavior approved 2026-09-26 (brief § Contractor control, the four
"owner decision 2026-09-26" bullets).

Built and committed: database (3 Part 3 migrations incl. `20260926100000_..._retry_lookup_fix.sql`), server
(`src/lib/server/reviews/requests.ts`, `/api/reviews/requests` GET+POST, `[id]/cancel`), panel
(`src/lib/components/reviews/RequestReviewButton.svelte` + `ReviewRequestForm.svelte`) on the job page header
and client page header. Proven live as owner (Raad): job #11 schedule → filled email saved → Cancel works;
client page picks latest completed job; Text tab says "no texting number".

Next action — finish the field-member browser check, then close Part 3:
1. Browser is currently signed in as the field member (`dev.jafarkhan@gmail.com`). Their only job (#20,
   `698bbe09-…`) is still active, so confirm job #20 shows NO "Request a review" button. They cannot open
   Robin's client page at all (access screen), so the client-page button needs no check for them.
2. Optional stronger check: in SQL, assign the field member to a visit on closed job #21 and see the button +
   panel work, then remove the assignment. Or accept the SQL scope check done last session.
3. Sign back in as the owner, then close Part 3 (read ROADMAP for Part 4 = automation + reminders).

Facts: Raad has no SMS number; manual email uses the default sender with `allows_manual` (Part 4 automation
must use `allows_automated`). The review link uses the address the contractor is browsing on (localhost in dev).
Flag for Jafar at report: operational review emails carry no unsubscribe link yet (suppression is honoured).

Known unrelated: `settings-business.spec.ts` expects 8 permission flags (stale). `npm run check` needs
NODE_OPTIONS=--max-old-space-size=8192; 3 "union type too complex" errors predate this. Pre-existing lint errors
in ClientDetailHeader (`messageReason`) and job page (`dateFormat`, `goto`). Never raise SQLSTATE 40001 for a
stale edit; use P0409. Playwright vs `npm run dev`: wait ~9s first visit.
Part 2 leftover: Jafar to glance at Review settings → "Preview feedback page" while signed in.
