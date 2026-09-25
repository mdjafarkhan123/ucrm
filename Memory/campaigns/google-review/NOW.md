# Google review — NOW

Goal: build the Google review campaign in `docs/google-review-campaign-owner-brief.md`.
Active part: 3 — Manual "Request a review". Behavior approved 2026-09-26 (brief § Contractor control, the four
"owner decision 2026-09-26" bullets).

Done and live: migrations `20260926090000_review_requests_manual_send.sql` + `20260926091000_...sender.sql`
(`get_review_request_context`, `create_review_request`, `cancel_review_request`; read their headers).
Checked in SQL against Raad: context works; field member refused on client page and unassigned job.

Next action — the app side, then browser-verify as owner and field member:
1. `src/lib/server/reviews/requests.ts`: render the chosen style (settings `message_styles` via
   `loadReviewSettings`; `{{review_link}}` → `reviewRequestUrl`, other variables filled), email HTML = escaped
   text with the link as an anchor (see `renderManualEmailHtml`); map RPC errors (P0001 consent/length,
   P0402 SMS balance, 55000 not ready, 42501, 23514, 23503) to plain messages.
2. Zod schema in `src/lib/server/validation/reviews.schema.ts`; routes under `src/routes/api/reviews/requests/`
   (GET context by job_id|client_id, POST create with idempotency key + optional send_at, POST [id]/cancel),
   all behind `requireOrganizationPermission(event, 'reviews.request')`. Refuse when no Google link is saved.
3. Panel component in `src/lib/components/reviews/` (Dialog; contact, `ComposerChannelMenu`, style, message
   via `SmsActionEditor`/`EmailActionEditor` with `REVIEW_MESSAGE_VARIABLES`, Send now/Schedule, "already
   asked on …" note, recent requests with Cancel when scheduled). Buttons on job page and client page; context
   query off until the button is hovered. Invalidate context after send/cancel.

Facts: Raad has no SMS number (SMS shows "not ready"); its default email sender is manual-only, which is why
manual requests use `allows_manual` (Part 4 automation must use `allows_automated`).
Flag for Jafar at report: operational review emails carry no unsubscribe link yet (suppression is honoured).

Known unrelated: `settings-business.spec.ts` expects 8 permission flags (stale). `npm run check` needs
NODE_OPTIONS=--max-old-space-size=8192; 3 "union type too complex" errors predate this. Never raise SQLSTATE
40001 for a stale edit (PostgREST retries forever); use P0409. Playwright vs `npm run dev`: wait ~9s first
visit. AppShell has a pre-existing unused `logoutIcon` lint error.
Part 2 leftover: Jafar to glance at Review settings → "Preview feedback page" while signed in.
