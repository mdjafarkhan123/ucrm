# Communications: Current Checkpoint

## Goal

Build secure contractor Communications with one shared Conversations model and independently gated email and Twilio channel tracks. Preserve the approved difference between package-included operational email and balance-funded phone/SMS.

## Active part

Parts 0–2 and 2B are closed. Part 3, operational outbound email, is approved and remains open.

## Exact next action

Connect a controllable signed-in browser, then browser-verify `/communications` as an owner/admin. The stale
tunnel-facing Vite process was replaced and the current repo is now served on port 5173. Open
`/communications` directly, then check the sidebar's **Inbox** link. The worker remains disabled; do not send
or invoke it.

## Current truth

- Approved email behavior is in `docs/contractor-email-contract.md`; shared inbox behavior and the pre-UI approval gate are in `docs/unified-inbox-behavior-contract.md`.
- Email uses isolated Brevo infrastructure and package allowances; it never deducts the Twilio Communication Balance. Marketing email, full inbound email, Gmail/Outlook sync, Meta, web chat, and Twilio remain separately gated.
- The worker route intentionally returns `503`; no contractor email has been sent. It remains fail-closed until the Part 3 activation gate passes.
- Part 2 sender/domain controls are browser-verified. Contractor sender changes require `conversations.manage_connections`; the atomic worker claim resolves stored sender/domain/member authority with no caller-supplied sender.
- Remote allowance authority and owner controls are applied. Both package allowance configuration and organization exception controls are browser-verified, but no active allowance period exists by default.
- Remote capacity claims reserve normal/protected-essential capacity before provider submission; missing allowance or exhausted capacity defers the outbox event. Database proof coverage passes.
- Manual client email is browser-verified: saved recipient, plain-text preview, queueing, and the queued/not-sent wording. The worker was not enabled.
- `communications_quote_delivery_intent` is applied. Its service-only command locks and re-resolves the published Quote, current client email, eligible automated sender/domain, recipient-scoped link, rendered content, and outbox event. `POST /api/quotes/[id]/email` accepts only an idempotency key and is rate-limited.
- The approved Quote UI plan is implemented locally: `QuoteEmailDialog.svelte` previews the server-controlled recipient, sender identity, subject, CTA, and secure-link fallback behavior. The Quote header exposes **Send email** only for published `awaiting_response`/`changes_requested` Quotes; drafts retain the offline **Mark as awaiting response** path. The browser sends only a fresh idempotency key and reports queued/not sent. Focused route tests and `npm run check` pass.
- Quote email authorization is aligned: the detail read model exposes `can_send_email` only when both
  `quotes.send` and `conversations.send` are effective; the header follows it; and the endpoint rejects a
  missing conversation permission with a truthful `403` before it creates a link, rate-limit record, or RPC
  call. Focused regression tests and the browser check with the under-authorized member pass.
- Jafar approved the implementation order for Communications UI on 2026-08-24: use a thin vertical slice.
  Create the smallest safe read seam first, then build the corresponding UI immediately with real data;
  neither a backend-only phase nor a mock-driven UI is the default.
- The approved email-only Inbox vertical slice is implemented locally: `/communications` reads existing
  delivery intents through `GET /api/communications/email-history`, uses a capped cursor-shaped query and
  a batch client lookup, and renders a three-pane Team Inbox. It exposes real queue/failure states only,
  has no compose/reply/channel simulation, and updates the main navigation and warm-route list.
- The stale tunnel-facing Vite process was stopped and the current repo was restarted successfully on
  `http://localhost:5173/`. A separate loopback-only Vite instance on port 5174 was preserved.
- Local migration `20260824141034_communications_inbox_read_index.sql` adds the `(organization_id,
  created_at desc, id desc)` inbox index and grants `conversations.view_team` to owner/admin. Linked
  Supabase CLI commands report extensive remote/local history divergence, but the remote history lists this
  exact version as applied. Supabase MCP token refresh failed before direct schema verification. Do not
  repair history or apply SQL out of band without resolving that anomaly.

## Blockers

Part 3 cannot close until later resend/audit and system-send slices complete. Current Meta, web-chat, and Twilio provider facts must be verified before their implementation tracks begin.

The local Inbox vertical slice still needs browser verification. No controllable in-app or extension browser
was connected after the Vite restart, so the signed-in owner/admin check could not run. Once a browser is
connected, verify the direct route and sidebar against the port 5173 server; if the route remains absent,
verify the browser/tunnel targets this `D:\Projects\Ucrm` development server rather than a stale process or
deployment. The normal linked push remains blocked by remote/local migration-history mismatch, but remote
history reports the Inbox version applied.

The positive Quote-email browser check remains deferred: a test member needs both `quotes.send` and
`conversations.send`. With that member, browser-retry Quote #34's email preview, obtain Jafar's confirmation
immediately before **Queue email**, then verify its queued/not-sent wording. Do not enable or call the worker.
No delivery intent or provider submission was created.


## Protected work

Preserve unrelated dirty work, especially the other agent's Settings work. Do not rewrite completed SMS decisions or create future campaign folders without an approved goal and roadmap.

## Required pointers

- `Memory/campaigns/communications/ROADMAP.md`
- `Memory/campaigns/communications/parts/3-operational-outbound-email.md`
- `docs/contractor-email-contract.md`
- `docs/unified-inbox-behavior-contract.md`
- `supabase/migrations/20260824120000_communications_quote_delivery_intent.sql`
- `src/routes/api/quotes/[id]/email/+server.ts`
- `src/routes/api/quotes/[id]/email/email.spec.ts`
- `src/lib/quotes/api.ts`
- `src/lib/components/quotes/QuoteEmailDialog.svelte`
- `src/routes/(app)/quotes/[id]/+page.svelte`

## Active-part completion gate

Part 3 must provide authorized manual and system sends with current work state, previews, secure links, allowance enforcement, and auditable resend behavior. The worker remains fail-closed until that part passes.
