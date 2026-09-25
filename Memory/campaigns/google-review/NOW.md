# Google review — NOW

Goal: build the Google review campaign in `docs/google-review-campaign-owner-brief.md`.
Active part: 1 — Review settings (ROADMAP.md entry 1). Built and committed, NOT yet browser-verified.

Done: migration `20260925200000_google_review_settings.sql` (applied live: reviews.* permissions on the
`growth.reputation` feature, `review_settings`, `save_review_settings`); API `/api/reviews/settings`; page
`/reviews/settings` (+ Settings home card, team-access "Reviews" controls).

Next action:
1. `npm run check` shows 3 "union type too complex" errors (OpportunityBriefDrawer, (app)/+layout warm list,
   invoices/new). Stash all Part 1 files and re-run to learn if the new route caused them; fix if so.
2. Raad LTD is on Starter (no `growth.reputation`): grant the feature via the Jafar panel override, then
   browser-verify as owner: load defaults, bad/good Google link, routing warning on/off, edit questions and
   styles, save, reload, two-tab conflict (409), field role gets 403.
3. Close Part 1; start Part 2 (customer feedback page).

Known unrelated: `settings-business.spec.ts` expects 8 permission flags; the API already sent 11 before
this campaign (stale test).
