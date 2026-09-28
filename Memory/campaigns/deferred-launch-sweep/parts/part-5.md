# Part 5 — Complete customer documents

**Campaign:** deferred-launch-sweep · **Plan:** Memory/deferred/invoice-email-sends-to-primary-only-not-billing-contact.md (spec; deleted when this ships)
**Code:** `main`
**Done when:** invoices and quotes email both the client's primary address and a separate billing-contact
address (when one is set), browser-verified on Raad LTD, and the deferred note is deleted.

## Steps

- [x] The three earlier Part 5 items are done (line-photos note closed, client-documents-completeness
      researched against Jobber and closed, quote line item Lightbox added) — see ROADMAP.md Part 5 line.
- [x] Asked Jafar whether to build Jobber's "primary + billing contact" invoice/quote email parity now
      (the one remaining Part 5 item). He said build it.
- [x] Designed the data model: a second flag `is_billing_contact` on `client_contact_methods` (kind='email'
      only, one per client, never the same row as the primary email — enforced by two new check constraints
      and a partial unique index).
- [x] Wrote migration `20260928200000_invoice_quote_billing_contact_email.sql`: adds the column/constraints/
      index; updates `create_client` and `update_client` to read an optional `billing_email` payload field
      the same way they already handle `email`/`phone`; updates `enqueue_invoice_communication_email` and
      `enqueue_quote_communication_email` to also queue a second send to the billing contact, each with its
      own access-link token (two new trailing optional parameters on each function, defaulted to null, so
      the six/six-argument callers that exist today keep working even before the routes are touched).
      Applied to the database 2026-09-28 (verified via `supabase migration list --linked` before and after —
      remote now shows `20260928200000`).
- [x] Apply the migration: `npx --no-install supabase db push --linked --dry-run` first, then for real.
- [ ] `src/lib/server/validation/foundation.schema.ts`: add `billing_email` to `clientWriteSchema` (same
      shape as `email`), plus a `superRefine` check that it differs from `email` (case-insensitive) when
      both are set.
- [ ] `src/lib/server/clients/duplicates.ts`: `DuplicateMatch.matched_on` gains `'billing_email'`;
      `findExactDuplicates` takes an optional `billingEmail` input and checks it against
      `client_contact_methods` (kind='email') separately from `email`, tagging matches by which *input*
      field they came from (not by the DB `kind`, which is the same for both) so the field error lands on
      the right input. Add `billing_email: 'billing email'` to `FIELD_LABEL`.
- [ ] `src/routes/api/clients/+server.ts` (POST) and `src/routes/api/clients/[id=uuid]/+server.ts`
      (GET/PATCH): pass `billing_email`/`billingEmail` through to `findExactDuplicates`; GET must select
      `is_billing_contact` on `client_contact_methods` and add a derived `billing_email` field to the
      response the same way `primaryOf()` derives `email`/`phone`.
- [ ] `src/lib/clients/api.ts`: add `billing_email?: string` to `ClientWriteValues`, `billing_email: string`
      to `ClientIdentityDraft`, `billing_email: string | null` to `ClientDetail`, and `is_billing_contact:
      boolean` to the `contact_methods` item type.
- [ ] UI, three places: `ClientDetailsForm.svelte` (the block-dialog editor — add a "Billing email
      (optional)" field near email/phone, hint "Also send invoices and quotes here"); `ClientForm.svelte`
      (the full create/edit page — same field in `FormState`/`blankForm`/`formFromClient`/`buildValues`);
      `(app)/clients/[id=uuid]/+page.svelte`'s `identityOf()` (add `billing_email: source.billing_email ??
      ''`). `ClientDetailHeader.svelte`: show a fourth fact "Billing email" only when `client.billing_email`
      is set (Jobber-style: an edge-case field, not shown when empty).
- [ ] `src/lib/server/communications/invoice-email.ts` / `quote-email.ts` already export cheap, pure link
      generators — no change needed there. Update the three call sites to generate a **second** link and
      pass it as the new trailing RPC params, only spent if a billing contact exists:
      `src/routes/api/invoices/[id=uuid]/email/+server.ts`, `src/routes/api/invoices/batch/deliver/
      +server.ts` (per invoice, inside its existing loop), `src/routes/api/quotes/[id=uuid]/email/
      +server.ts`.
- [ ] Browser-verify on Raad LTD: add a billing email on a real client (different from primary), send an
      invoice and a quote, confirm two emails were queued/sent (Communications → Sent, or the outbox), and
      confirm the billing contact's link opens the same document.
- [ ] Delete `Memory/deferred/invoice-email-sends-to-primary-only-not-billing-contact.md` and its `ROADMAP.md`
      mention once shipped and verified; mark Part 5 done with the date.

## Next

Apply the migration (dry-run first), then work the unchecked steps above in order — the Zod/duplicates
layer before the routes, the routes before the UI, so each step can be sanity-checked (`npm run check`)
before the next depends on it.

## Notes

- The DB already has a `client_contacts` table (named additional contacts, e.g. spouse/property manager)
  with its own `client_contact_methods` rows, but it has **no CRUD UI anywhere in the app** — building one
  was ruled out of scope for this deferred item. The billing contact is deliberately just a second flagged
  email on the client's own contact methods, not a new named-contact feature.
- `client_contact_methods_org_value_unique_idx` makes every email unique **across the whole organization**,
  not just per client — this already applied to primary emails and now applies to a billing email too. Not
  a new limitation, just inherited.
- Each recipient gets their own access-link token (never a shared secret between the primary and billing
  addresses) — this is why the routes must generate two links, not reuse one.
