# Invoice (and quote) email sends to the primary email only, not "+ billing contact"

**Deferred:** 2026-09-06, during Invoices 8b (batch deliver). Approved by Jafar as a known Jobber difference.

**What we do:** `public.enqueue_invoice_communication_email` resolves ONE recipient —
`client_contact_methods where kind='email' order by is_primary desc, created_at, id limit 1` — and sends there.
Quotes use the same single-recipient rule.

**What Jobber does:** sends each invoice to the client's **primary starred email + the billing contact** (two
recipients).

**Why deferred:** matching Jobber needs a distinct "billing contact" concept our data model does not have
(contact methods only carry an `is_primary` flag, no billing-contact role), and the change belongs to
single-send, not batch — 8b deliberately reuses the existing single-recipient rule unchanged.

**Reactivates when:** Jafar wants Jobber recipient parity. Then decide the data-model concept first
(billing-contact role on contacts), change single-send's recipient resolution, and batch inherits it for free.
