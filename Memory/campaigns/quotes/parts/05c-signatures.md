# Part 5C: Signatures

5B2 gave a quote a decision history. This slice gives an approval a name on it. Two calls Jafar made on
2026-08-21, before implementation:

- **Signing is offered, not demanded.** Jobber's own rule: "Since signatures aren't required to approve a
  quote", the client may draw or type and approve either way, and a Client Hub setting turns it into a
  requirement account-wide (`jobber-03-quotes.md` §5). Jafar asked to follow Jobber, so approve stays
  possible without signing and the organization-wide requirement waits for Settings, which is off this
  campaign's path.
- **The staff pad is an in-person approval, not a separate act.** Signing on a phone at the kitchen table
  records an approval with method `in_person`, exactly like the existing verbal path, so a quote keeps one
  decision history. From a draft it publishes first, because a signature on an unpublished document is a
  signature on nothing.

## Outcome

A customer approving online can put their name to it by typing or drawing, a staff member closing in person
can collect that signature on their own device, and either way the signature is welded to one published
version, its document hash, and the one decision row that answer created. A material revision leaves every
old signature intact and none of them current.

## Approved behavior

- The customer's Approve step gains a signature area: **Type** and **Draw**, one at a time, with Clear. A
  typed signature stores the name; a drawn one stores a small private PNG plus the name typed beside it if
  given. Approve is enabled with or without a signature.
- **Request changes never asks for a signature.** Nobody signs a request to change something.
- Staff get **Collect signature** in the quote menu, in every status Jobber offers it, opening a pad
  dialog. Submitting approves the quote in person. No `Send your client a copy` checkbox: that is email,
  and Communications owns email.
- A signature records signer name, method (`typed`, `drawn`, `in_person`), signed time, the version's
  `document_hash` copied at signing, the decision it belongs to, and truncated IP/user agent. Verbal
  approval keeps recording no signature at all rather than a fabricated one.
- The signature and its decision are written by one database command in one transaction. There is no state
  where a quote is approved but the signature it was approved with is missing.
- Material revision does not delete signatures. The decision stops being current and its signature goes
  with it; the new version needs its own.
- Staff see `Signed by <name>` with the date where the quote already shows its decision, and can open the
  drawn image. The customer's answered page says the same back to them.
- Drawn images are private forever: no public URL, no presigned link, no shared cache. Staff read them
  through an authenticated stream route; the customer's own page never re-fetches theirs.

## Database and performance decisions before SQL

- `quote_signatures`: UUID id, duplicated `organization_id`, composite FKs to `(organization_id, quote_id)`,
  `(organization_id, quote_id, quote_version_id)` and `(organization_id, quote_decision_id)`. One signature
  per decision - unique on `(organization_id, quote_decision_id)` - because a decision is one answer by one
  person at one moment.
- No `is_current` column. Currency is the decision's, and duplicating it would be a second truth to keep in
  step. The read is `join quote_decisions ... where is_current`, already served by
  `quote_decisions_one_current_idx`.
- One index beyond the unique: `(organization_id, quote_id, signed_at desc)` for the quote's own history.
  No organization-wide signature list exists, so no index leads with organization alone.
- `document_hash` is copied onto the row, not read through the version, so a signature can prove which
  bytes were on screen without a join and without trusting a later row.
- The drawn PNG is an object key, not bytes in Postgres. Signature rows are read on every quote detail
  page; image bytes on that row would be dragged into every read that never displays them.
- The R2 upload happens before the command and outside any lock, per the contract's rule that external
  calls never occur while rows are locked. A refused command leaves an unreferenced object, deleted on a
  best-effort pass; an orphan object nobody can name is cheaper than a lock held across a network call.
- Commands: `submit_quote_customer_decision` grows optional signature parameters; a new
  `record_quote_in_person_signature` covers the staff pad. Both `security definer`, `anon` granted nothing,
  the public one granted only to `service_role`.

## Implementation checklist

- [x] Confirm columns, constraints, indexes, grants, and the one-signature-per-decision rule before SQL.
- [x] Migration: `quote_signatures`, customer command signature parameters, staff in-person command.
- [x] Run the migration performance/security gate before any API route work.
- [x] Server: PNG validation and size cap, server-side R2 put, key derivation, orphan cleanup.
- [x] Public approve route accepts a signature; staff signature route with Zod and permission checks.
- [x] Staff-only stream route for the drawn image.
- [x] Route tests: signed approve, unsigned approve, replay, oversized/forged image, wrong permission,
      revoked link, superseded version, and log redaction.
- [x] Run the API performance/security gate before UI work.
- [x] One `SignaturePad` component: Type/Draw, Clear, touch and mouse, used by both sides.
- [x] Customer approve step, staff Collect signature dialog, and the signed-by line on quote detail.
- [x] Svelte autofixer, targeted tests, check, formatting, and browser passes on both sides.

## Acceptance checks

- Approving with a typed name, with a drawn signature, and with neither all work and all record honestly.
- A signed approval and its decision appear together or not at all, including when the command refuses.
- Two taps on a slow phone produce one decision and one signature.
- Starting a new version leaves the old signature readable in history and no longer current, and the new
  version asks for a fresh one.
- The drawn image is unreachable without a session, has no shareable URL, and is not in any log line.
- A pretend PNG, a 5 MB PNG, and a data URL of another type are all refused before touching storage.
- Staff without `quotes.record_decision` cannot collect a signature.
- Preview still signs nothing.

## Non-discoverable risks

- A canvas signature from a phone can be large. Cap the drawn size on both sides and downscale before
  upload, or one signature is heavier than the whole quote document.
- `record_quote_decision` publishes a draft before answering. The in-person command must reuse that exact
  behavior rather than a second copy of it, or verbal and in-person approvals will drift apart.
- A typed signature is a name in a box and proves very little. Never present it to staff as more than what
  it is, and never render evidence back to the customer.
- Base64 in a JSON body is roughly a third larger than the file. The route's body limit must account for
  that or a legitimate signature fails with a confusing error.

## Source pointers

- `docs/quote-behavior-contract.md` §§ Versions edits and signatures, RLS and command boundary.
- `.claude/skills/jobber/jobber-03-quotes.md` §5 and §8.3 - optional signing, and the staff pad.
- `parts/05b2-view-tracking-and-customer-decisions.md` - the decision rows this binds to.
- `supabase/migrations/20260822090000_quote_customer_views_and_decisions.sql` - both decision commands.
- `src/lib/server/quotes/customer-decision.ts` - the shared public handler.
- `src/lib/server/storage/r2.ts` - object keys and streaming; needs a server-side put.
- `src/routes/(public)/q/[token]/files/[attachmentId]/+server.ts` - the private-file streaming shape.
