# Google review — NOW

Goal: build the Google review campaign in `docs/google-review-campaign-owner-brief.md`.
Active part: 1 — Review settings (ROADMAP.md entry 1). Built and committed, NOT yet browser-verified.

Done: migration `20260925200000_google_review_settings.sql` (applied live: reviews.* permissions on the
`growth.reputation` feature, `review_settings`, `save_review_settings`); API `/api/reviews/settings`; page
`/reviews/settings` (+ Settings home card, team-access "Reviews" controls).

Next action:
1. Apply `20260925210000_review_settings_conflict_errcode.sql` (`npx supabase db push --linked`; the agent's
   push was blocked by the permission gate — Jafar runs it or approves). It swaps the stale-save errcode
   40001 -> P0409: PostgREST auto-retries 40001 forever, so a stale save hung and looped in the database.
2. Re-run the two-tab test (stale tab must show "Someone else saved..."), then field role gets 403.
   Already verified in browser as Raad owner: defaults load, bad/good Google link, routing warning
   (keep off / accept), questions + helper text + add question, message style edit, save, reload.
3. Close Part 1; start Part 2 (customer feedback page).

Known unrelated: `settings-business.spec.ts` expects 8 permission flags; the API already sent 11 before
this campaign (stale test).
`npm run check` needs NODE_OPTIONS=--max-old-space-size=8192; its 3 "union type too complex" errors
exist without the reviews route (not ours).
Five older baseline functions also raise 40001 and would hang the same way on a stale save
(apply_organization_limit_exception, record_member_identity_cleanup_step, release_member_identity_cleanup,
rotate_website_chat_widget_public_token, update_website_chat_widget) — reported to Jafar, not owned here.
