# Client/Property deletion and issued-document history risk

**Date:** 2026-09-10
**Campaign:** paid-launch-trust, Part 8 (investigation only — no correction made)
**Scope:** every path where deleting, archiving, or editing a Client or Property could erase or rewrite
something an issued Quote, Invoice, Job, or Work Report already relies on.

---

## Part A — Client: no delete path exists yet, so nothing is broken today

There is **no hard-delete and no archive endpoint for a Client anywhere in the app.**
`src/routes/api/clients/[id]/+server.ts` exports only `GET`/`PATCH`; `src/routes/api/clients/+server.ts`
exports only `POST`/`GET`. The client list's Archive and Delete buttons are present but wired to nothing and
disabled (`src/routes/(app)/clients/+page.svelte:129,185,189`), with a comment explaining why: "Both bulk
actions are switched off until clients carry real work to archive or delete alongside."

The schema already carries `deleted_at`/`archived_at` on `clients`
(`supabase/migrations/20260816103906_client_property_data_model.sql:47-48`) and list/detail reads already
filter on them, but **nothing writes to either column** — this is a half-built soft-delete with no writer, not
a live feature.

**FK protection is already correct and in place:** `quotes.client_id`, `jobs.client_id`, `invoices.client_id`,
`invoice_payments...client_id`, and `requests.client_id` are all `ON DELETE RESTRICT` to `clients`. If a hard
delete were ever added, Postgres refuses it outright the moment any historical document references that
client. The one cascade in the graph is `properties.client_id → clients` **ON DELETE CASCADE** — irrelevant
today since nothing can hard-delete a client, but worth remembering if a hard-delete path is ever proposed:
cascading through to properties would then hit the RESTRICT walls on quotes/jobs at the property level anyway.

**No merge/dedupe exists.** `src/lib/server/clients/duplicates.ts` only warns about likely duplicates at
create/edit time; its own comment states it "never blocks a save and never selects or merges anything on the
office's behalf." No code path reassigns a quote/job/invoice from one client to another.

**Jobber comparison:** Jobber archives clients (soft-close via `ClientArchive`), never hard-deletes them
(`.claude/skills/jobber/jobber-01-clients-properties.md:118-119`). Our unused `archived_at`/`deleted_at`
columns already point at the same shape.

**Conclusion:** no client-deletion risk exists today because no client-deletion feature exists today. The risk
is entirely forward-looking: whoever eventually wires up that disabled button must not do so before Part B's
findings are fixed, because an archived client's historical documents must still render correctly, and today
several of those documents pull live client data rather than a frozen copy.

---

## Part B — Property: a real soft-delete exists, and live in-place edits are the actual risk

**Delete is real and soft**, not a gap: `DELETE /api/properties/[id]` calls `public.delete_property`
(`supabase/migrations/20260817134328_property_add_and_remove.sql:22-66`), which only sets `deleted_at = now()`
and promotes a new primary property — it never hard-deletes the row. `quotes.property_id`/`jobs.property_id`
are `ON DELETE RESTRICT`, but since delete is soft this constraint never fires; it's a dormant safety net, not
protection actually in use.

**The real risk is live in-place editing, not deletion.** `PATCH /api/properties/[id]`
(`src/routes/api/properties/[id]/+server.ts:11-53`) runs a direct `UPDATE public.properties SET
address_line1=…` against the same row a quote or job still points to by `property_id`. `update_client`'s
property block (`supabase/migrations/20260817030702_client_create_edit_foundation.sql:276-291`) does the same
thing when an address is edited from the client form. Neither path versions or snapshots the prior address —
it's a straight overwrite.

`invoices` has no `property_id` column at all — it only carries the frozen `service_properties` jsonb array,
so invoices have zero exposure to this. The exposure is specific to **quotes** and **staff-facing job/quote
screens**, covered next.

---

## Part C — Where the freeze pattern already exists, and the one place it's undermined

This campaign has already built three correct freeze patterns worth reusing rather than reinventing:

| Document | Frozen at | Builder | Live-join risk |
| --- | --- | --- | --- |
| Quote (customer copy) | version publish | `private.quote_customer_document` | None — reads only `quote_versions.*` |
| Invoice (customer copy + receipt) | issue | `private.invoice_customer_document` | None — reads only the invoice's own snapshot columns |
| Job signature | signing moment | `private.job_document_snapshot` | None — table is append-only by trigger, even against `TRUNCATE` |
| Work report (issued link) | link issue (Part 7, this campaign) | frozen into `job_report_access_links.frozen_document` | None once issued — preview-as-client still reads live by design |

**The one place the pattern breaks: staff-facing quote screens prefer the live join over the frozen
snapshot.** `quote_versions` already stores frozen `client_display_name` and `service_address_line1…country`
specifically so "a later client rename or address correction must not rewrite what a customer was shown"
(`20260820002436_quotes_pricing_foundation.sql:262-271`). But:

- The staff quote detail read (`QUOTE_SELECT` in `src/routes/api/quotes/[id]/+server.ts:15-19`) live-joins
  `clients` and `properties` alongside the frozen version columns.
- The quote detail page prefers the live value:
  `src/routes/(app)/quotes/[id]/+page.svelte:974-975,1314` —
  `name={saved.quote.client?.display_name ?? saved.version?.client_display_name ?? …}`.
- The quotes list page does the same: `src/routes/(app)/quotes/+page.svelte:206,367` shows
  `quote.client?.display_name` / the property's live address, not the frozen version text.

**Concrete failure case:** rename a client, or edit a property's address, after a quote has been sent. The
customer's own link (`/q/[token]`) and the "preview as client" screen still correctly show the frozen name and
address — those two share the same builder. But the **staff detail and list screens for that same quote now
show the new name/address**, silently disagreeing with what the customer actually received. 11 published
quote versions exist today carrying frozen text that the staff UI is already capable of overriding the moment
someone edits a client or property.

This is a staff-visibility drift bug, not a customer-facing data leak, and not blocked on any client/property
delete feature — it can be triggered today by a plain client rename or property address edit.

---

## Summary for Part 9

| # | Finding | Severity | Blocked on |
| --- | --- | --- | --- |
| D1 | Staff quote detail/list screens show live client name/property address instead of the frozen `quote_versions` snapshot, once a client is renamed or a property's address is edited after send | High | Nothing — prefer the frozen version columns already stored, same fix shape both places |
| D2 | Property and client-form address edits overwrite the property row in place with no versioning, which is what feeds D1 and any other live-join reader (job list/detail, request pricing) | Medium | D1's fix scope decision — do we snapshot on write, or only fix the readers that must stay frozen? |
| D3 | Client archive/delete is unbuilt (disabled buttons, unused `deleted_at`/`archived_at` columns) — not a risk today, but the read paths in D1 must be fixed before that button is ever turned on, since an archived client's old quotes/invoices must keep rendering correctly | Low (latent) | D1 |
| D4 | No client merge/dedupe exists — out of scope, nothing to fix | — | — |

Nothing here was corrected. This is evidence only, per Part 8's gate.

---

## Open question for Jafar before scoping Part 9

D1 has an obvious, low-risk fix: make the staff quote screens prefer the frozen `quote_versions` columns the
same way the customer-facing document already does (only fall back to the live join if the frozen field is
somehow blank). That matches Jobber's own model — an archived/renamed client doesn't rewrite history it
already handed a customer.

The one product call is **D2's scope**: do we leave property/client address edits as plain live overwrites
(accepting that any *other* live-reading screen, like the job list, will show today's address — which is
arguably correct for an active job) and just fix quotes' *display* to prefer their existing snapshot (D1)? Or
do we also want address edits themselves to leave a trail (an edit history on properties, similar to what
Part 7 built for invoices)? The first is the smaller, already-evidenced fix; the second is new scope this
campaign hasn't approved.

Recommend: fix D1 only for Part 9 (display bug, existing snapshot, no new schema), and leave property-edit
history as a deferred item unless Jafar wants it now.
