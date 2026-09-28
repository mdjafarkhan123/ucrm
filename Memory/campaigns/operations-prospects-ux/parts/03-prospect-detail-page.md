# Part 3 — Dedicated Prospect detail page

**Campaign:** operations-prospects-ux · **Plan:** none; approved behavior below
**Code:** `main`
**Done when:** the new page keeps every field, action, stage rule, confirmation, and cache update of today's
side panel, and row links, direct load, refresh, missing record, loading, error, partial failure, keyboard,
and mobile use all work.

**Approved behavior:** move the side panel's Prospect detail and owner actions to
`/jafar/prospects/[prospectId]`, following the Organizations detail page. No API, schema, authorization,
RLS, or business-rule change.

## Steps

- [x] Reinspect the Prospect page, routes, tests, actions, and cache updates
- [x] Account for every field, action, state, confirmation, notification, and cache
- [ ] Present the page plan and get Jafar's approval — asked 2026-09-28, answers pending
- [ ] Build the page, point list rows and prospect notifications at it, commit; stop before removing the
      old side panel

## Next

Wait for Jafar's answers to the question below. Then create
`src/routes/jafar/(protected)/prospects/[prospectId]/+page.svelte` from the side panel in
`src/routes/jafar/(protected)/prospects/+page.svelte`.

## Notes

- The first build (2026-09-27) was lost uncommitted and cannot be recovered; Jafar approved a from-scratch
  rebuild on 2026-09-28. Commit as soon as the page builds.
- Already-sent alert emails link to `/jafar/prospects?application=<id>`: the list page must forward it to the
  new page and still clear that prospect's unread notifications, leaving both link builders unchanged
  (`src/lib/jafar/notifications.spec.ts`). The navigation skeleton in
  `src/routes/jafar/(protected)/+layout.svelte` should check the prospect's own cache key, as it does for
  organizations.
- Question waiting for Jafar, word for word:

  > Here's my plan for the rebuilt prospect page. Each prospect gets its own page, like each organization
  > has. Clicking a prospect in the list opens it, and refresh, Back and bookmarks all work. At the top: a
  > link back to Prospects, the business name and its stage. Everything in today's side panel comes across
  > unchanged: the duplicate warning and its two buttons, contact and package details, all seven action
  > buttons in the same stages as now, the same forms and "are you sure?" pop-ups, setup-email status with
  > Send/Resend, and the full history. A prospect that doesn't exist shows "Prospect not found" with a way
  > back; a failed load shows Try again. Prospect notifications, in the bell and in alert emails you already
  > have, open the new page. No rules, checks or saved data change. The old side panel stays as a backup
  > until you've tried the new page, then it's removed.
  >
  > **Q1 - One page or tabs?** Organizations use tabs because they hold a lot; a prospect holds much less.
  > Recommended: one scrolling page with clear sections, so nothing hides behind a click.
  >
  > **Q2 - History open or folded?** Today "View private history" is folded to save room in the narrow
  > panel. Recommended: show details and history open on the new page; keep only the long, technical
  > original-form record folded.
  >
  > Reply "go" to build it this way, or tell me what to change.
