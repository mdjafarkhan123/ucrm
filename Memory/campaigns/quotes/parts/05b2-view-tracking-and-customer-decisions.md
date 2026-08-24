# Part 5B2: Public view tracking and customer decisions

The second half of 5B. 5B1 gave the customer a door and a document; this slice lets them answer. Jafar
settled two scope calls on 2026-08-21 before implementation:

- **Two customer buttons, not three.** Approve and Request changes only, matching Jobber's client rail
  (`jobber-03-quotes.md` §8.3). Declining stays a staff-recorded offline outcome, because a Decline button
  gives an unsure client a one-click way to end the job instead of asking a question. The behavior contract
  keeps declining as a valid customer transition; the UI simply does not offer it yet.
- **Expiry is enforced, not authored.** Links already carry an optional `expires_at` and the resolver
  already refuses expired ones. This slice adds the honest expired page. No quote-level valid-until date,
  no extend flow, and therefore no derived Expired label - that needs a version-level date on the customer's
  document and belongs with the send work.

## Outcome

A customer opening a real link is recorded as having seen the document, can approve it or ask for changes,
and sees an honest result afterwards. Staff see when the client opened it and what they answered. Every
decision is an immutable version-bound fact, and replaying one never produces a second answer.

## Approved behavior

- **First meaningful view** is stamped once, by an explicit browser call after the document renders - never
  by the page GET, a HEAD, a scanner, or a link preview. Later opens bump a last-seen time and a counter.
  Only the first view writes an activity event; repeat opens would flood a feed staff read for real events.
- **Decisions are facts, not just a status.** `quote_decisions` holds every approve, change request, and
  decline, bound to organization, quote and published version, with actor kind (`customer` or `staff`),
  note, and safe evidence (truncated IP and user agent). At most one current decision per quote. 5C
  signatures bind to a decision row.
- The existing staff offline command writes the same table, so a quote has one decision history rather than
  a staff one and a customer one.
- **Approve** moves an awaiting quote to `approved` and stamps `decision_method = 'online'`. **Request
  changes** moves it to `changes_requested`, keeps the customer's message, and closes the buttons until
  staff republish. A repeat of the same answer on the same version returns the first result.
- A decision is refused when the link is revoked, expired, points at a superseded version, or the quote is
  archived, already decided, or not awaiting an answer. Every refusal reads as one plain sentence to the
  customer and reveals nothing about the organization.
- **Expired** is the one distinguishable unavailable state, per the contract. Everything else stays the
  single generic page.
- Public endpoints carry per-IP and per-token limits on the existing `check_rate_limit`. Tokens, notes, and
  customer content never enter a log line.
- Preview keeps rendering the same buttons disabled, so staff see exactly what the client is asked.
- No Pipeline outcome, Communications message, deposit, signature, or Job conversion in this slice.

## Database and performance decisions before SQL

- `quote_decisions`: UUID id, duplicated `organization_id`, composite FKs to `(organization_id, quote_id)`
  and `(organization_id, quote_id, quote_version_id)`. One partial unique index enforces at most one current
  decision per quote. Read path is by quote, so the one index leads with organization and quote.
- View state lives as three columns on `quote_access_links`, not a views table: the customer path already
  finds that row by unique token hash, so recording a view is one update by primary key with no new index.
  A per-view history table would grow without bound for a number nobody reads.
- Both public commands are `security definer`, revoked from `public`/`anon`/`authenticated`, granted only to
  `service_role`. The token hash stays the only public seam.
- The decision command locks the quote first, exactly like every other quote command, so it queues behind a
  concurrent publish instead of deadlocking. Business conflicts answer `P0409`, never `40001`.
- No aggregate, no materialized view, no new N+1: the whole customer decision is one round trip.

## Implementation checklist

- [x] Confirm columns, constraints, indexes, grants, and the decision uniqueness rule before writing SQL.
- [x] Migration: `quote_decisions`, link view columns, `record_quote_link_view`,
      `submit_quote_customer_decision`, and the staff command rewritten to write the same history.
- [x] Extend `resolve_quote_access_link` to name the expired case and nothing else.
- [x] Run the migration performance/security gate before any API route work.
- [x] Public routes `view`, `approve`, `changes` with Zod bodies, rate limits, and redacted failures.
- [x] Route tests: replay, wrong/revoked/expired/stale-version tokens, rate limit, log redaction, and a
      refusal that leaks nothing.
- [x] Run the API performance/security gate before UI work.
- [x] Customer page: live buttons, confirm step, answered state, expired page, and the recorded view call.
- [x] Staff side: opened-by-client and decision facts where the quote already shows its history.
- [x] Copy customer link in the staff menu, because none of this was reachable from the app without it.
- [x] Svelte autofixer, targeted tests, check, formatting, build review, and browser passes.

## Acceptance checks

- Opening a link stamps a first view once; opening it five more times does not move that time or add five
  activity events.
- A HEAD request, a page GET alone, and a malformed token record nothing.
- Approving twice, or approving from two tabs at once, produces one decision row and one activity event.
- A decision through a revoked, expired, or superseded link changes nothing and says nothing about the org.
- The staff offline command and the customer command land in the same history table.
- The customer page after an answer offers no way to answer again.
- Preview still cannot submit anything.

## Non-discoverable risks

- The view call is a POST from the customer's browser and is therefore forgeable by anyone holding the
  token. That is acceptable - it proves the link was opened, not who opened it - and it must never be
  presented to staff as proof the client personally read the quote.
- Recording evidence means storing a truncated IP and user agent. Truncate before the value reaches the
  database, and never render either back to the customer.
- `record_quote_decision` already publishes a draft before answering it. The customer command must never do
  that: a customer can only answer a version they were actually sent.
- Rate limiting a public POST by IP alone punishes a whole office behind one address; key by token hash as
  well so one client's retries cannot lock out another's.

## Source pointers

- `docs/quote-behavior-contract.md` §§ Lifecycle, Recipients, RLS and command boundary.
- `parts/05b1-secure-access-and-customer-renderer.md` - the inherited access path.
- `.claude/skills/jobber/jobber-03-quotes.md` §8.3 - the two-button customer rail.
- `supabase/migrations/20260821160000_quote_publication_and_decisions.sql` - the staff decision command.
- `supabase/migrations/20260821180000_one_customer_document_two_readers.sql` - the shared builder.
- `src/lib/server/security/rate-limit.ts` - the existing bucket helper.
