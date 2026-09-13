# Onboarding & Data Portability — import/export research

**Date:** 2026-09-13
**Owner:** Jafar
**Purpose:** Ground the launch roadmap's Part 2 (safe assisted import/export) in the proven industry pattern
before implementation. Sources: Jobber (help center + live tour), HubSpot (live end-to-end test import), and
our own client-duplicate code.

## Why this exists

Launch roadmap Step 2 gates the first paying customer: a contractor must be able to bring core records in
without duplicates, and take them out if they leave. This doc records the mature pattern and — more
importantly — the one place our own data rules force us to differ from it.

## The proven import flow (universal across Jobber, HubSpot, Stripe, Shopify, Mailchimp)

A staged wizard with a progress stepper. HubSpot's is the clearest reference; observed live end to end:

1. **Type** — which record type(s) are in the file; multiple types can be imported and associated in one run
   (HubSpot "Advanced import"). Single-object is a simpler "Quick import".
2. **Upload** — the file (.csv/.xlsx). Alongside the dropzone: a **mode selector** ("Create and update" /
   create-only / update-only), a downloadable **sample/example file**, header-language pick (feeds
   auto-mapping), and a duplicates explainer link. A stated **row cap** (Jobber: ~5,000 rows / 2.5 MB).
3. **Map** — a table, one row per file column: **file column → sample preview → auto-map status → our field
   (editable dropdown) → per-field "Don't overwrite existing value" toggle**. Columns auto-map on name match
   (observed: First/Last Name, Email, Phone, Company→Company Name, Street/City/State/Postal all matched with
   no manual work). Rows are **scanned for errors inline** as you map (a column with a bad/duplicate value
   shows an error count before you finish).
4. **Details** — name the import (it is logged in an **import history**), optional segment/list creation, and
   a **consent affirmation gate** ("these contacts expect to hear from me; not purchased/rented/appended")
   that **must be checked before Finish is enabled**.
5. **Result** — processed **asynchronously** ("we'll email you when finished"). A summary card reports
   **Import rows / New records / Updated records / New associations / Errors**, an **Errors tab** listing each
   failed row with an error type + impact, and **"Download errors as file" / "View rows with errors"**.

**Placement (Jobber, observed live):** Import, Export, and Merge are three sibling actions in the Clients list
header's **More Actions** menu — not buried in Settings. Merge/dedupe is a separate first-class tool.

**Live HubSpot test (4-row file):** 2 unique rows, 1 exact-duplicate row, 1 row with no email sharing a
phone. Result: **3 created, 1 rejected as "Duplicate row content", 0 updated.** The no-email/shared-phone row
**was created** — HubSpot dedupes contacts on **email only**; phone is not a dedupe key there.

## The critical divergence for us (do NOT copy HubSpot here)

Our schema enforces a **hard unique index** on `client_contact_methods (organization_id, kind,
normalized_value)` — i.e. **within one contractor, an email OR a phone can belong to only one client**
(`src/lib/server/clients/duplicates.ts`). HubSpot has no such phone constraint. Consequences for our import:

- Two rows sharing a phone (real: spouses/family) **cannot both** become clients holding that phone — the DB
  rejects the second. Rule: **first row wins the contact method; later rows import without it and are
  flagged**, never silently dropped, never crash the batch.
- Exact email/phone match against an existing client → operator choice is **Skip** or **Update existing**.
  "Import anyway as a new record" is impossible for a match and must not be offered.
- A row matching client A on email but client B on phone (conflict) → **held out for a human**, never guessed.
- A row with no email and no phone can't be matched; it imports as new but is **tagged with its source file +
  row id**, which is also the **idempotency/retry key** so a re-run or mid-batch crash never double-creates.
  (Matching and retry-safety are two separate problems — email/phone solves matching; the source-row tag
  solves retry.)

## Safeguards (carried into every phase)

- **No customer-facing side effects.** An import must not emit the events our automation / communications /
  review / dunning engines listen to: no welcome emails, no automations, no review requests, no balance-due
  chasing. Write records through a path that does not enqueue those.
- **Consent affirmation** before a run, mirroring HubSpot's gate.
- **Named, logged imports** with a history and a downloadable per-row error file.

## Export (define now, build later)

- **Records:** clients, contacts, contact methods, properties, price book, and their notes.
- **Relationships:** stable IDs so records link inside the package.
- **Files/attachments:** included, with a manifest.
- **Exclusions (named):** other tenants' data, internal-only cost/margin fields, system audit internals.
- **Link expiry vs package:** the download link is short-lived; the downloaded package is self-contained and
  the customer's to keep, regenerable on request.
- **Not a backup:** this readable export is a customer artifact, distinct from disaster-recovery backups
  (launch Step 9) and separately verified.

## Opening balances (its own financial gate)

Decide one model — unpaid invoices **or** a starting balance, never both for the same debt (double-count
risk). **Blocked on the launch financial-reconciliation audit (Step 3);** must not trigger dunning.
