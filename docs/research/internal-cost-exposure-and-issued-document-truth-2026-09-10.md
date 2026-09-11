# Internal cost exposure and issued-document truth

**Date:** 2026-09-10
**Campaign:** paid-launch-trust, Part 6 (investigation only — no correction made)
**Scope:** every payload/document path where internal cost could reach someone who may not see it, and
every path where an issued customer document could drift from what was originally sent.

---

## Part A — Customer-facing document paths: clean

There are exactly four doors a stranger with a link can walk through, and each one funnels through a single
private builder function in the database. All four were read in full.

| Door | Builder | Carries cost or margin? |
| --- | --- | --- |
| `/q/[token]` quote | `private.quote_customer_document` | No |
| `/i/[token]` invoice | `private.invoice_customer_document` | No |
| `/w/[token]` work report | `private.job_report_customer_document` | No |
| `/r/[token]` payment receipt | receipt resolver | No |

None of the four selects `unit_cost_minor`, `line_cost_total_minor`, or any margin figure. Each builder is
`private`, is revoked from `public`/`anon`/`authenticated`/`service_role`, and is reached only from inside a
security-definer resolver. Staff "Preview as client" calls the same builder, so the preview and the customer
copy cannot drift.

Money is withheld by never entering the payload (`include_money`), not by hiding it in the browser.

**No customer-facing cost leak was found.**

---

## Part B — Internal cost exposure: two real gaps

Quotes and jobs solve this the right way, and there is a working precedent in the codebase to copy:

- `quote_version_lines` and `job_line_items` have their money columns **revoked from the `authenticated`
  grant** (migration `20260831135855`). Cost reaches staff only through `public.quote_line_money` /
  `public.job_line_money`, which check `quotes.view_cost` / `jobs.view_cost` and return an empty object
  otherwise.
- `public.job_costing` refuses outright without `jobs.view_cost`.

Two tables never got that treatment. Live check against the database:

```sql
select table_name, column_name
from information_schema.column_privileges
where grantee = 'authenticated' and privilege_type = 'SELECT'
  and column_name in ('unit_cost_minor','line_cost_total_minor');
```

Returns exactly three rows: `catalog_items.unit_cost_minor`, `request_pricing_lines.unit_cost_minor`,
`request_pricing_lines.line_cost_total_minor`. Nothing else.

### B1 — Request pricing hands cost to office, sales, and now assigned field

`GET /api/requests/[id]/pricing` selects `unit_cost_minor` and `line_cost_total_minor` into the response
(`src/routes/api/requests/[id]/pricing/+server.ts:20-22`). There is no `quotes.view_cost` check anywhere on
the read — only `requireOrganization` plus RLS, and RLS filters rows, not columns.

The row filter is `private.can_view_request(organization_id, request_id)`. Roles holding `requests.view`:
owner, admin, finance, office, sales, field. Roles holding `quotes.view_cost`: owner, admin, finance only.

So **office and sales** receive internal cost on every request pricing read, and — because Part 3 of this
campaign widened field visibility to assigned requests — **a field member assigned to a request's assessment
now receives it too**. Part 3 did not create the leak, but it enlarged its audience.

The same rows are also readable directly through PostgREST with the member's own token, so this is not just
an API-shape problem.

Live data: 2 of 7 `request_pricing_lines` rows currently carry a non-zero cost, so this is real, not
theoretical.

### B2 — The price book's cost gate is bypassable

`src/lib/server/quotes/selects.ts` correctly picks a cost-free column list when the member lacks
`quotes.view_cost`, so the app UI is clean. But the RLS policy on `catalog_items` is:

```
organization_id in (select private.permitted_organizations('catalog.view'))
```

`catalog.view` is held by owner, admin, finance, **office and sales**. Since `unit_cost_minor` is still in the
`authenticated` select grant, office and sales can read the price book's cost column directly through
PostgREST and bypass the server-side select entirely. 2 catalog items currently carry a non-zero cost.

### B3 — Why the obvious fix is blocked (carried over, still true)

`PATCH /api/requests/[id]/pricing` replaces the whole line set and its payload carries no stable line id, so
a redacted read cannot round-trip: a cost-blind member's save would write zeros over the owner's real costs.
`withCatalogCost` (`src/lib/server/quotes/catalog-cost.ts`) patches this only for lines that name a catalog
item and arrive with no cost — new price-book lines. A hand-typed line's cost would still be lost.

Part 7 must decide one of two things before narrowing the read: either the save payload gains a stable line
id, or `replace_request_pricing_lines` resolves untouched costs itself from the existing rows.

---

## Part C — Issued-document truth

### C1 — Quotes: immutable, correct

`quote_versions` and all three child tables carry `before insert/update/delete` triggers
(`private.reject_published_quote_version_change`, `private.reject_published_quote_child_change`) that raise
`P0409` once the version's status is `published`. The customer document reads the frozen version row, and
the business name comes from `version_row.organization_name` — a snapshot, so a later rebrand does not
rewrite a quote the customer already holds. 11 published versions exist and none can be altered.

The only live-resolved parts are the quote's own progression facts (status, sent_at, decision, decided_at),
which is correct, and attachment file bytes, which are served live by object key.

### C2 — Invoices: editable after issue, and the "draft only" rule lives only in the browser

An invoice freezes `customer_snapshot`, `billing_address_snapshot` and `service_properties` at issue, so a
later client rename or address change never rewrites the bill. Good. But the **lines and money are read live**
by `private.invoice_customer_document` from `public.invoice_lines` and the `invoices` row.

Four commands can change an issued invoice's document:

| Command | Route |
| --- | --- |
| `replace_invoice_lines` | `PATCH /api/invoices/[id]/lines` |
| `set_invoice_discount` | `PATCH /api/invoices/[id]/discount` |
| `set_invoice_tax` | `PATCH /api/invoices/[id]/tax` |
| `update_invoice_details` | `PATCH /api/invoices/[id]` |

All four call `private.lock_invoice_for_edit`, which refuses only a **voided** or **replaced** invoice, a
missing permission, and a stale revision. It does **not** refuse an issued one. All four then call
`private.retain_prior_invoice_document`, which writes the complete previous document into the event log as
`invoice.document_edited` — so history is kept.

The only thing stopping an edit is the Svelte page:
`src/routes/(app)/invoices/[id]/+page.svelte:95` computes `editable` as draft-only. Any member with
`invoices.edit` + `invoices.view_price` can call the API route (or the RPC) directly on an issued invoice and
change what the customer's live link shows.

Two consequences, both unaddressed today:

1. **No customer-visible revision marker.** `private.invoice_customer_document` emits no revision, no
   "revised on", no edit history. A customer told they owe £500 can open the same link later and see £900
   with nothing indicating the bill changed.
2. **No customer notice.** Nothing re-sends or flags the change. The invoice email carries a link rather than
   embedded amounts (`src/lib/server/communications/invoice-email.ts`), which limits the contradiction to
   link-vs-memory rather than link-vs-email — but a printed or saved copy would still disagree.

The contract disclaimer is the one field already locked after issue (`20260906130000`), which shows the
intended rule exists; it was simply never applied to lines, discount, tax, or details.

Live state: 16 issued invoices, 16 frozen documents, **0 `invoice.document_edited` events**. Nobody has
exercised this yet. It is a latent capability, not damage already done.

### C3 — Work reports: live by design

`private.job_report_customer_document` resolves photos, checklist answers and job lines live, and its own
comment says so deliberately. A report link already sent to a customer will show today's photos and today's
line list, not the ones present when the link went out. This is a stated design choice rather than an
oversight, but it is worth Jafar confirming it is what he wants for a document a customer may treat as a
record of work performed.

---

## Summary for Part 7

| # | Finding | Severity | Blocked on |
| --- | --- | --- | --- |
| B1 | Request pricing read hands internal cost to office, sales and assigned field | High | Line-identity decision (B3) |
| B2 | `catalog_items.unit_cost_minor` readable directly by office and sales | High | Nothing — mirror the `quote_line_money` pattern |
| C2 | Issued invoice lines/discount/tax/details editable via API; no customer revision marker | High | Resolved — see below |
| C3 | Work reports resolve live after being sent | Medium | Resolved — see below |

Nothing here was corrected. Correction and verification are Part 7.

---

## Product decisions — follow Jobber (Jafar, 2026-09-10)

Jobber's behavior on both open questions, from the skill reference plus a read-only live check recorded in
`.claude/skills/jobber/jobber-05-invoices-payments.md`:

**C2 — issued invoices.** Jobber keeps line items editable after issue *and* after full payment, with no
warning. Its safety is not a lock: it is an **Invoice History** panel showing every edit with who, when, and
a field-level before → after diff. Nothing customer-facing marks the invoice as revised.

Decision: match the shape, keep our approved redline where it already departs.

1. **Do not lock the issued invoice.** Editing stays allowed — that is Jobber, and locking it would collide
   with the standing deferred complaint that issued invoices cannot be corrected from the browser.
2. **Move the rule out of the browser.** Today `editable` is draft-only in
   `src/routes/(app)/invoices/[id]/+page.svelte:95` and nothing enforces it server-side. The server becomes
   the authority; the UI stops being the only gate.
3. **Surface the history we already store.** `invoice.document_edited` already captures the complete prior
   document via `private.retain_prior_invoice_document`. It is written and never shown. Part 7 renders it as
   Jobber's history panel does.
4. **Keep the redline for money.** Per the approved invoice redline, corrections that change what the
   customer owes go through reversal/replacement rather than a silent in-place rewrite. Wording and
   presentation edits behave like Jobber's.
5. **No customer-facing revision marker.** Jobber shows the client nothing, and inventing one is not parity.

**C3 — work reports.** Jobber has no standing live customer work-report link. Its nearest equivalent is
deliberately attaching selected notes and photos to a quote or invoice email — a snapshot fixed at send time
(`jobber-04-jobs-visits-scheduling.md` §9). Our report link resolving photos, checklist answers and job lines
live is therefore *not* Jobber parity.

Decision: freeze the report content at send, not just the selection. The customer's copy should show what was
selected and present when the link went out.
