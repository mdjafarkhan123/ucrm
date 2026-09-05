# Invoices: Current Checkpoint

- Goal: Jobber-grounded invoicing and manual collection.
- Active part: **6b — send + delivery/view facts + receipt document/email.** 6a CLOSED 2026-09-05
  (browser-verified light + dark, no console errors, money math correct, print CSS clean).

## Exact next action

Present the 6b plan to Jafar for approval before building (non-trivial). 6b scope:
- `issue_invoice_access_link` command — fills recipient_name/email on `public.invoice_access_links` + rotates.
- Staff "links" read function (definer, hides token_hash) + a "Copy customer link" / "Send" entry point on
  the invoice detail header (mirrors quotes).
- Issue-on-send + Communications email enqueue, **idempotent**; record issue/delivery/view facts (public
  view-recorded ping on `/i/[token]`).
- Receipt document generated from accepted payment facts + emailed.
- Depends on: Communications email worker. Retrofit `CustomerQuoteDocument` onto the shared foundation stays
  a deferred follow-up (out of campaign — touches shipped quote code).

## Open item for Jafar

- **6a work is NOT committed to Git** (all files listed below are untracked/modified). Awaiting Jafar's go to
  commit as "Invoices 6a: customer invoice document, secure view, and Print/Save PDF". Two migrations already
  applied to the remote DB: `20260904170000_invoice_terms_billing_seam_and_permissions.sql`,
  `20260905160000_invoice_customer_document.sql`.
- Business identity = org name only (organizations has just `name`); mockup tagline + billing email/phone
  footer dropped, same as the shipped quote doc. A real business profile is a future schema addition.

## Essential pointers

- `docs/invoice-behavior-contract.md` — "Terms, delivery, and reminders"; Screens; D1–D5
- `Memory/campaigns/invoices/ROADMAP.md` — Part 6 decisions block + 6a (done) / 6b rows
- Patterns to mirror: `src/lib/server/quotes/access-links.ts`, quote preview route `(app)/quotes/[id]/preview/+page@.svelte`

Resume command: `read memory and continue the Invoices campaign`.
