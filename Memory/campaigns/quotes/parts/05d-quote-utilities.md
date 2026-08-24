# Part 5D: Quote utilities

Packages are gone and a quote's document sections now follow Jobber's composer (both closed earlier this
session). This slice finishes the header menu Part 5 has been building toward status by status, plus the
list page's stubbed bulk Archive button. Three calls Jafar made on 2026-08-21, before implementation,
answered "follow Jobber" for the first two:

- **No new permission.** The `archive_quote`/`restore_quote` commands already built (Part unclear, ahead of
  UI) gate on `quotes.edit`, not the `quotes.archive` the contract only ever proposed. Jobber's own
  documented split is coarse — Office/Sales get one bundled "edit quotes" grant; only *seeing cost* is its
  own permission (`jobber-03-quotes.md` §1.1 note). Delete and Create Similar stay on `quotes.edit` too.
  `docs/quote-behavior-contract.md` § Staff permissions is corrected to drop the proposed `quotes.archive`
  row.
- **Delete stays scoped to direct-creation drafts.** Jobber lists Delete in every status, but that assumes a
  quote nobody else's record points at. Jobber never documents what happens to the originating Request when
  the Quote it produced is deleted, and a Request's own Converted status is terminal and never reopens
  (`jobber-02-requests-leads.md` §1.2, "Final status — like Quote Converted"). Deleting a Request-converted
  draft would leave that Request permanently Converted and pointing at nothing. So eligibility excludes any
  quote with a `request_id`, regardless of publish history — those stay archive-or-keep, never delete.
- **Create Similar starts clean.** A new quote, new number, new Opportunity, copied Client/Property/lines/
  document sections — no `request_id`, no version history, no decision. Matches Jobber's own quote being "a
  genuinely new one that happens to start full."

## Outcome

The header menu Part 5 has been assembling since 5A finally matches Jobber's own status-by-status shape
(`jobber-03-quotes.md` §8.3), narrowed everywhere our immutable-version architecture requires it: Create
Similar Quote works from any status; Archive/Restore replace the disabled stub on both the detail header and
the list's bulk bar; Delete appears only on the handful of drafts that are safe to remove outright. Convert
to Job and Send as Email keep saying nothing, same as today — Jobs and Communications are still off this
campaign's path.

## Approved behavior

- **Create Similar Quote** — available in every status, including Archived. Creates a brand-new `draft`
  Quote: new number, new Opportunity (parked off the Pipeline board exactly like `create_quote` already
  parks one), same Client/Property. Copies the source's *current readable version* (its draft if one exists,
  otherwise its published version) the same way `clone_quote_version_to_draft` copies a revision: lines,
  introduction, client message, contract disclaimer, discount, tax, and version-attachment rows pointing at
  the same underlying files. Title becomes `"<original title> (copy)"`. Never copies `request_id`, and never
  copies decision, signature, or access-link history — there is none to copy, this is version 1 of a Quote
  that has never been shown to anyone. Lands on the new quote's own page.
- **Archive** — offered on any non-`converted` status the quote is not already in, on both the detail header
  menu and the list's bulk bar. Approved quotes ask for a reason (already required by `archive_quote`);
  every other status archives in one click, matching `Mark as Awaiting Response`'s own one-click precedent.
  Bulk archive walks the selection and skips (without failing the batch) anything `converted` or already
  `archived`, reporting how many of the selection actually moved.
- **Restore** — offered only when `status = 'archived'`. One click, no dialog (`restore_quote` already
  refuses a bad target on its own — no Property/Client validity to duplicate client-side).
- **Delete** — offered only when `status = 'draft'`, `request_id is null`, and the quote has never had a
  version leave draft (no `quote_versions` row for it in any status but `draft`). One confirulation dialog
  naming the quote ("Delete “<title>”? This cannot be undone.") — no reason field, this is not Archive.
  Deleting removes the quote, its draft version, its lines, its version-attachments, and its parked
  Opportunity in one statement; the quote number stays retired, per the counter's own "never reused" rule.
  Not offered anywhere else — an eligible-but-archived draft shows Restore, not Delete, until it is a draft
  again.
- **The finished menu**, folded into the existing `quoteMenuItems` derivation next to what 5A–5C already
  built (send, mark approved/declined, collect signature, start new version, copy customer link, preview,
  print, convert to job):
  - Every status: Create Similar Quote, Preview as client, Print or save PDF.
  - Not `converted`, not already `archived`: Archive.
  - `archived` only: Restore.
  - Delete-eligible only: Delete.
  - `converted`: none of the above four beyond Create Similar Quote and preview/print — nothing here
    reopens or removes terminal work.
- The list's bulk bar swaps the disabled `Archive` button for a live one the moment any selected row is
  archivable, and drops the `bulkReason` tooltip text entirely once it has nothing left to explain.

## Database and performance decisions before SQL

- `create_similar_quote(target_quote_id uuid)`: `security definer`, gated on `quotes.edit` against the
  *source* quote's organization, mirrors `create_quote` for the `quotes`/`opportunities` inserts and
  `clone_quote_version_to_draft` for the version/lines/attachments copy — one new function, not a rewrite of
  either. Reads the source's draft version if `draft_version_id is not null`, else its
  `current_published_version_id`; refuses only if neither exists (a quote with no version at all should not
  occur, but the function still names the failure rather than crashing on a null lookup).
- `delete_quote(target_quote_id uuid)`: `security definer`, gated on `quotes.edit`, locks the quote row
  `for update`, then refuses with `errcode = 'check_violation'` unless `request_id is null` and no sibling
  `quote_versions` row for this quote has `status <> 'draft'`. Passing that check, a single
  `delete from public.quotes where id = ...` is enough — `quote_versions`, `quote_version_lines`,
  `quote_version_attachments`, and `opportunities.quote_id` all already cascade
  (`20260820161041_quote_professional_proposals_foundation.sql`, `20260820002553_quotes_request_conversion.sql`).
  The one remaining draft version row is never `published`, so
  `reject_published_quote_version_change`/`reject_published_quote_child_change` never fire — no need to
  disable or route around either guard.
- No new columns. `archive_quote`/`restore_quote` and their columns (`archived_at`, `archive_reason`,
  `previous_status`) already exist and are unchanged by this part.
- Bulk archive is a loop of the existing single-row `archive_quote` RPC from one API route, not a new SQL
  function — the row count here is a UI selection (tens, not thousands), and a per-row permission/status
  check that already exists is worth more than a bespoke bulk statement duplicating its guard logic.

## Implementation checklist

- [x] Correct `docs/quote-behavior-contract.md` § Staff permissions: drop the proposed `quotes.archive` row,
      note archive/restore/delete/create-similar all read `quotes.edit`.
- [x] Migration: `create_similar_quote`, `delete_quote`; grants to `authenticated` only, revoked from `anon`.
      (`20260822150000_quote_similar_and_delete.sql`, corrected in place twice after the performance gate and
      a live-tested bug — see below.)
- [x] Run the migration performance/security gate before any API route work. Caught and fixed a real seq
      scan (line/attachment copy predicates now match the `(organization_id, quote_id, quote_version_id)`
      index prefix) and a real bug (`ORDER BY "id" is ambiguous` on the unaliased attachments copy — the
      lines copy already aliased its source table, the attachments one didn't). Both fixed before any route
      called the function; the ambiguity bug was actually caught live in the browser pass below, not the
      gate itself — worth remembering next time a copy query is written without a source alias.
- [x] `POST /api/quotes/:id/similar`, `DELETE /api/quotes/:id`, `POST /api/quotes/bulk-archive` (10-wide
      `Promise.all` batches, not one connection per row and not full-sequential).
- [x] Route tests: `src/routes/api/quotes/[id]/similar-and-delete.spec.ts` (Create Similar's no-body call and
      404 translation, Delete's 23514→422 field error and 404 translation, both routes' 403 short-circuit
      without touching the RPC) and `src/routes/api/quotes/bulk-archive/bulk-archive.spec.ts` (invalid JSON
      and empty-selection 422s, partial success on a mixed selection, one failed row not aborting the batch,
      a 12-id selection crossing the 10-wide concurrency batch, the 403 short-circuit). These are route-layer
      tests against a mocked RPC — they check permission gating, request parsing, and error translation, not
      the SQL itself (already covered by the migration performance gate and the live browser pass above). 13
      tests, all passing; `npx prettier --check` clean; no new TypeScript errors.
- [x] Run the API performance/security gate before UI work.
- [x] Detail header: Create Similar Quote, Archive (with the Approved reason prompt), Restore, Delete (with
      its confirm dialog) added to `quoteMenuItems` in `src/routes/(app)/quotes/[id]/+page.svelte`.
- [x] List page: bulk bar's `Archive` button wired to the new bulk route; `bulkReason` dropped; the Status
      filter's existing `archived` option round-trips as expected — confirmed live, see below.
- [x] Svelte autofixer (clean on both pages — the two flagged issues are pre-existing standalone-tool
      artifacts on SCSS syntax the project's own `svelte-check` doesn't see), `npx svelte-check` (0 errors),
      `npx prettier --check` (clean) on every touched file.
- [x] Browser pass, live, on quote #1 (Panel upgrade quote) and #31 (Kitchen rewire quote, Approved):
      Create Similar Quote → new Quote #35, same client/property/lines/photo/subtotal, fresh Opportunity, no
      request/version lineage; Delete on that fresh copy → confirm dialog → removed, Draft count back down;
      Archive on an Approved quote → reason required, Archive disabled until typed, archived; Restore →
      back to Approved with its original facts intact; list bulk-archive on a 2-item mixed selection (one
      Draft, one Approved) → "1 archived, 1 skipped", Approved one correctly left alone. Not yet exercised
      live: Delete correctly hidden for a Request-converted draft (derived condition is
      `!saved.quote.request_id`, same shape as the already-tested checks, not separately clicked through).

## Acceptance checks

- Create Similar Quote from a draft, from an awaiting-response quote, and from an approved quote all land on
  a new quote #, in Draft, with the same lines/sections and a fresh unlinked Opportunity — none of the three
  carry the source's `request_id`, version history, or decision.
- Archiving an approved quote without a reason is refused; with one, it archives.
- Archiving a converted quote is never offered.
- Restoring an archived quote returns it to a sane status and the quote is immediately editable again.
- Delete is offered only on an untouched, directly-created draft; disappears the moment that draft is
  published, revised from a Request, or archived while still eligible (Restore replaces it there).
- Deleting removes the quote from the list and its Opportunity from the Pipeline with nothing orphaned.
- Bulk-selecting a mix of archivable and already-terminal quotes archives only what can move and says so.
- Every one of the above refuses cleanly for someone without `quotes.edit`.

## Non-discoverable risks

- `create_similar_quote` must create its own `opportunities` row exactly like `create_quote` does — Sales
  Pipeline expects one parked card per Quote (`opportunities_quote_unique`), so skipping this silently would
  leave a Quote the Pipeline never learns about the moment that campaign resumes.
- The eligibility check for Delete must read sibling `quote_versions` rows, not just the quote's own
  `status` column — a quote that was published, then declined, then revised back to `draft` still has a
  `published`/`superseded` row in its history and must never qualify.
- `delete_quote`'s cascade depends on three separately-added foreign keys already carrying
  `on delete cascade`. Confirm each one again at the migration performance gate rather than trusting this
  packet's read of them — a `restrict` slipped into any of the three turns a normal delete into a users
  facing 500.
- The bulk archive route must not raise on a single ineligible row inside the loop — a naive
  `for id of ids: rpc(...)` that lets the first failure abort the transaction turns "archive what you can"
  into "archive nothing and say why is buried in a stack trace."

## Source pointers

- `docs/quote-behavior-contract.md` §§ Lifecycle, Staff permissions.
- `.claude/skills/jobber/jobber-03-quotes.md` §8.3 — the status-by-status menu this closes out.
- `.claude/skills/jobber/jobber-02-requests-leads.md` §1.2 — Request's own terminal Converted status.
- `supabase/migrations/20260820160000_quote_workspace_commands.sql` — `create_quote`, `archive_quote`,
  `restore_quote`.
- `supabase/migrations/20260822140000_quotes_drop_packages.sql` — current `clone_quote_version_to_draft`,
  the field list `create_similar_quote` mirrors.
- `supabase/migrations/20260820002553_quotes_request_conversion.sql` — `opportunities.quote_id`, its unique
  index and cascade.
- `supabase/migrations/20260820161041_quote_professional_proposals_foundation.sql` — the published-row
  guard triggers `delete_quote` must never trip.
- `src/routes/(app)/quotes/[id]/+page.svelte` — `quoteMenuItems`, the menu this packet finishes.
- `src/routes/(app)/quotes/+page.svelte` — `bulkReason`, the stubbed bulk Archive button.
- `src/lib/quotes/statuses.ts` — status labels/tones, already covering `archived`.
