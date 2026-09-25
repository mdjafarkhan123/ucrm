# Google review — NOW

Goal: build the Google review campaign in `docs/google-review-campaign-owner-brief.md`.
Active part: 1 — Review settings (ROADMAP.md entry 1). Built and committed, NOT yet browser-verified.

Done: migration `20260925200000_google_review_settings.sql` (applied live: reviews.* permissions on the
`growth.reputation` feature, `review_settings`, `save_review_settings`); API `/api/reviews/settings`; page
`/reviews/settings` (+ Settings home card, team-access "Reviews" controls).

Next action:
1. Browser-verify as Raad LTD owner (Raad already has Reviews via its package; the Jafar panel now lists it):
   load defaults, bad/good Google link, routing warning on/off, edit questions and styles, save, reload,
   two-tab conflict (409), field role gets 403. The agent cannot type passwords, so Jafar must sign the
   Chrome window into the contractor owner account first.
2. Close Part 1; start Part 2 (customer feedback page).

Known unrelated: `settings-business.spec.ts` expects 8 permission flags; the API already sent 11 before
this campaign (stale test).
`npm run check` needs NODE_OPTIONS=--max-old-space-size=8192; its 3 "union type too complex" errors
exist without the reviews route (not ours).
