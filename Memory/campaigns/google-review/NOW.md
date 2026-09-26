# Google review — NOW

Goal: build the Google review campaign in `docs/google-review-campaign-owner-brief.md`.
Active part: 4B — automatic ask. Read `parts/04-automation.md` (4B section).

State 2026-09-26: 4B engine half committed (`ea9840c`) and its migration is live
(`20260926160000_review_request_automatic_ask.sql`). Performance design done (verdict in the packet).

Next action:
1. Builder UI in `src/lib/components/settings/automation/RecipeBuilder.svelte` (packet § 4B remaining).
2. Show the new request status `not_sent`, stop reason `recently_asked` and `origin` in
   `src/lib/reviews/requests.ts` labels + `ReviewRequestForm.svelte` history.
3. Worker spec for `action_due_review_request`; SummaryRail / RecipeDetailView / activation-preview labels.
4. Browser-verify, then the performance verification items in the packet.

Facts: Raad's only email sender is manual-only (`allows_automated` false), so automatic email refuses with
"not set up to send automatic messages"; Raad has no SMS number. Ask Jafar before changing Raad's sender.
Known unrelated: `npm run check` needs NODE_OPTIONS=--max-old-space-size=8192; 3 "union type too complex"
errors predate this. Never raise SQLSTATE 40001 for a stale edit; use P0409. Supabase CLI is `npx supabase`.
