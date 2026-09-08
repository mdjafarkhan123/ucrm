# Jobs Part 15d — Collected job signatures and immutable signed evidence

Status: **Approved by Jafar 2026-09-08.** Not yet implemented. Split into 15d-1 (database + API +
server tests) then 15d-2 (signature-pad UI + browser verification).

## Context

**Why this exists.** A contractor's crew finishes work at a customer's property and needs the
customer to sign off — "yes, this was done." Or before starting change-order work, they need a
signature authorizing it. Today the app has no way to capture that. Jobber does it with a **Job →
More → "Collect Signature"** action that opens a Signature Pad (draw or type a name) and stores a
signed job PDF as an internal note.

**What 15d delivers.** A staff member collects a signature against a job (optionally noting which
visit they were on). The signature is bound to a **frozen snapshot of the job document as it stood
at that moment** plus a SHA-256 hash of it, so later edits to the job's scope, price, or schedule
can never make the signed evidence lie. The record is **append-only** — the database refuses every
update and delete. It shows on the Job detail page and in the combined Job history.

**What 15d is NOT.** It is not the customer-facing Work Report (that is Part 15e, which owns the
curated report, secure share link, and share history). It is not a checklist field type (cut from
15c on purpose — "signature is 15d's own subject"). No PDF file is generated — this app **runs no
server PDF engine** by an explicit past decision (Invoices Part 6); customer documents here are
hosted pages you can browser-print, never attached files.

**Contract change this requires.** `docs/jobs-behavior-contract.md` currently says (Field records
section): *"Signature capture attaches a Job PDF to the Job's notes rather than inventing a new
record type."* That predates the 15d roadmap ambition ("signer, collector, time, frozen document
snapshot are auditable; later Job edits cannot rewrite signed evidence") and is unbacked by infra
(no PDF engine, no job-document renderer). 15d **supersedes that line** with a dedicated append-only
`job_signatures` record. Jafar approved this amendment with the plan; write the amended wording into
the contract in the 15d-1 migration turn.

## What mature field-service tools actually do (research, Sept 2026)

Jafar's instruction was "follow what Jobber / mature industries do." Findings:

- **Jobber (lighter model).** Signature pad → a **signed job PDF saved as an Internal Note** on the
  job; "Send your client a copy" emails that PDF. The signed PDF note **can be deleted** from the
  note's ⋯ menu. Job deletion is not blocked by a signature (it's just a note). Collection is
  available at any status, prominent in "requires invoicing".
- **Housecall Pro (structured model).** **Signature *types*** — "Before work starts", "After work is
  complete", "Custom" — collected per job (**up to 3**). Each collected signature records **the
  type, the signer's name ("Approved by…"), the date, and the amount that was approved**. It shows
  on **the invoice and the job record**. It renders **grey when collected at the current job price,
  red when the job price has since changed**, and the pro is prompted to **re-collect**. Removing a
  signature type from settings **"will not affect any already collected signatures"** — captured
  ones are retained.
- **Our own quote signatures** are deliberately *stronger* than Jobber: bound to a frozen version +
  document hash, append-only, "material revision never deletes an old signature — it makes it
  non-current, preserves the signed version, and requires a new one."

**How this resolves the three delegated questions:**

| Question | Resolution (following the mature/structured model) |
| --- | --- |
| **What's frozen** | Job identity + client + property + **line items with descriptions, quantities and prices** + **job total** + a **signature type** (Work authorization / Work completion / Other) + the exact statement shown above the line + signer + date + SHA-256 hash. Money is on it — HCP freezes "the amount that was approved", and the signed doc appears on the invoice. |
| **Job deletion with signatures** | A job with collected signatures **cannot be hard-deleted** — same rule already intended for jobs with invoices. It can still be closed/archived. A **considered deviation from Jobber specifically** (which treats the signature as a throwaway note): 15d's own name is "immutable signed evidence", and ServiceTitan-class tools plus our own quote signatures work this way. |
| **Mistaken / stale signatures** | **No edit, no delete, no void** — matching HCP and Jobber, neither of which offers one. Instead the card **flags a signature whose frozen document no longer matches the job's current state** ("The job has changed since this was signed") and offers **"Collect a new signature"**. Old signatures stay as history; the fresh one sits alongside. This is HCP's grey/red pattern and it is how "later edits cannot rewrite signed evidence" becomes *visible*. |

No configurable signature-type library (HCP has one; that's a Settings surface we don't need) — a
fixed 3-value enum plus an editable statement is the minimal correct version.

## The standard mechanism, and who builds it this way

Every piece of 15d is a port of something already shipped in this repo:

| Need | Proven pattern we copy | Source |
| --- | --- | --- |
| Signature record + drawn-image reference | `quote_signatures` table | `supabase/migrations/20260821055755_quote_signatures.sql` |
| Draw a signature in the browser | `SignaturePad.svelte` (already generic) | `src/lib/components/quotes/SignaturePad.svelte` |
| Validate + store the PNG server-side (no presigned URL) | `decodeSignatureImage` + `putObject` | `src/lib/server/quotes/signatures.ts`, `src/lib/server/storage/r2.ts` |
| Serve the drawn image privately | authenticated streaming route | `src/routes/api/quotes/[id]/signature/[signatureId]/image/+server.ts` |
| Frozen document snapshot + SHA-256 hash | `freeze_quote_version` / `invoice_document_snapshot` (`encode(extensions.digest(canonical::text,'sha256'),'hex')`) | `supabase/migrations/20260820161041_*`, `20260904190000_*` |
| "Later edits cannot rewrite it" | `BEFORE UPDATE OR DELETE` + `BEFORE TRUNCATE` trigger that raises; RLS on, `revoke all from anon, authenticated`, `grant select` only | `job_costing_events` (14a) `supabase/migrations/20260908170000_*`, `invoice_events` `20260904180000_*` |
| Snapshot-on-capture (copy, never reference) | `attach_job_checklist` copies template rows into the job's own copy | `supabase/migrations/20260911100000_job_checklists_foundation.sql` |
| Field-record permissions + derived visibility | `field_records.record` / `field_records.manage_team`, `private.can_view_job` | `supabase/migrations/20260909100000_field_records_on_jobs_and_visits.sql` |
| Scope-aware RLS that hoists once per statement | inline `current_permission_scope('jobs.view')` + `is_assigned_to_job`, denormalized `job_id` | `supabase/migrations/20260910120000_*`, 15c policies |
| History surfaces it automatically | write an `activity_events` row (`entity_type` `job`/`visit`) → `job_combined_history` unions it | `supabase/migrations/20260910110000_job_combined_history.sql` |
| API route shape | gate `jobs.view` at the route, real authority in a `SECURITY DEFINER` RPC; `{ error, field_errors }`; SQLSTATEs P0400/P0404/P0409/P0410 | `src/routes/api/jobs/[id]/expenses/+server.ts`, `src/lib/server/api/errors.ts` |

## 15d-1 — database + API + server tests

### Migration — `supabase/migrations/2026091x100000_job_signatures_foundation.sql`

**Table `public.job_signatures`** (one table, no children):

- `id` uuid pk; `organization_id` uuid not null → organizations (cascade); `job_id` uuid not null,
  composite FK `(organization_id, job_id)` → `jobs`; `visit_id` uuid nullable, composite FK →
  `job_visits`, `on delete set null` (context only — "the crew was on Tuesday's visit").
- `signature_type` text not null check `in ('work_authorization','work_completion','other')`.
- `signer_name` text not null (1–120); `signer_role` text nullable (1–60, free text e.g.
  "Homeowner"); `statement` text not null (1–500) — the exact sentence shown above the signature
  line, preset from `signature_type` and editable by the collector.
- `method` text not null check `in ('typed','drawn')`.
- `document_snapshot` jsonb not null — the frozen job document **including line prices and the job
  total** (HCP freezes "the amount that was approved").
- `document_hash` text not null check `~ '^[0-9a-f]{64}$'` — SHA-256 of the canonical snapshot,
  computed in the command with `extensions.digest`, copied in so the row proves itself.
- `image_object_key` text nullable (drawn only, `<org>/job-signatures/<job>/<uuid>.png`);
  `image_byte_size` integer nullable (1–262144); check couples method ↔ image exactly like
  `quote_signatures_image_matches_method`.
- `evidence` jsonb not null default `'{}'` — truncated IP + user-agent of the collecting device.
- `collected_by` uuid → auth.users `on delete set null`; `collected_at` timestamptz not null
  default now().
- `unique (organization_id, id)`.
- Indexes: `(organization_id, job_id, collected_at desc, id desc)`; partial
  `(organization_id, visit_id) where visit_id is not null`.

**Append-only guard** — copy `private.job_costing_events_are_append_only()` in shape:
`private.job_signatures_are_append_only()` raising `insufficient_privilege`; triggers
`BEFORE UPDATE OR DELETE` (per row) **and** `BEFORE TRUNCATE` (per statement). The trigger must
allow the org-purge cascade the same way the patched history tables do — permit `DELETE` when
`current_setting('app.organization_purge_in_progress', true) = 'true'`, block `UPDATE`
unconditionally forever (see `20260815042737_fix_organization_purge_missing_immutable_bypasses.sql`).

**RLS** — SELECT-only policy, no write policy (all writes via the command). Spell the scope rule
inline so it hoists once per statement (15a-4 lesson):
```
organization_id = (select private.current_organization())
and (
  (select private.current_permission_scope('jobs.view')) = 'all'
  or ((select private.current_permission_scope('jobs.view')) = 'assigned'
      and private.is_assigned_to_job(organization_id, job_id))
)
```
`revoke all on public.job_signatures from anon, authenticated;` then `grant select (...)` on the
non-image, non-snapshot columns to `authenticated`. `document_snapshot` and `image_object_key` are
never granted — reached only through the read models / streaming route.

**Command `public.collect_job_signature(...)`** — `SECURITY DEFINER`, `set search_path =
pg_catalog, public`:
1. `caller := (select auth.uid())`; not-null else `insufficient_privilege`.
2. `private.member_has_permission(org, caller, 'field_records.record')` else `insufficient_privilege`.
3. `private.can_view_job(org, job)` else `insufficient_privilege`.
4. If `visit_id` given, verify the visit belongs to `(org, job)` (`P0404` otherwise).
5. Validate `method` ↔ `image_object_key` coupling (`P0400` / `check_violation`).
6. `select ... from public.jobs where id = job for update` (consistent lock order; the PNG was
   already uploaded before this call, so no network I/O under the lock).
7. Build `document_snapshot` with explicit `jsonb_build_object(...)` (fixed key order → stable
   hash) from the job row + `job_line_items` + `job_money` (or the job total reader) + the visit
   row when given. `document_hash := encode(extensions.digest(document_snapshot::text, 'sha256'),
   'hex')`.
8. Insert `job_signatures`.
9. Insert `activity_events` — `entity_type` = `visit` if `visit_id` else `job`, `event_type`
   `job.signature_collected`, summary `"Collected {signer_name}'s signature ({signature_type})"`,
   `actor_user_id` = caller, `metadata` `{signature_type, method, visit_id, has_image}`. This is
   what puts it in Job history.
10. Return `jsonb_build_object('id', ..., 'collected_at', ..., 'has_image', ...)`.

`revoke all ... from public; revoke execute ... from anon; grant execute ... to authenticated`
(staff-collected — not a customer/service-role command).

**Read models** — because the snapshot carries money, follow the house rule (money never in a
plain grant):
- `public.job_signatures_for_job(target_job_id)` — `SECURITY DEFINER`, checks `can_view_job`.
  Returns each signature's shape (id, `signature_type`, `statement`, `signer_name`, `signer_role`,
  `method`, `has_image`, `collected_at`, `collected_by`, visit label) **plus an `is_stale`
  boolean** = the signature's stored `document_hash` no longer equals a freshly computed hash of
  the job's current document (HCP's grey/red). No money, no raw snapshot here.
- `public.job_signature_document(target_signature_id)` — `SECURITY DEFINER`, checks `can_view_job`;
  returns the frozen `document_snapshot` with the **priced lines and total included only when the
  caller holds `jobs.view_price`**, stripped otherwise. This is the "view what was signed" panel.

**Deletion behaviour.** No `delete_job` command exists yet (job hard-deletion is not implemented;
the standalone Close Job / delete flow is deferred in the roadmap). Two things follow:
1. The append-only trigger already makes a raw job delete fail for a job that has signatures.
2. When `delete_job` is eventually built, it **must** check `exists(select 1 from
   public.job_signatures where organization_id = ... and job_id = ...)` and refuse with a friendly
   P0410 before the delete — exactly alongside the intended "refused when Invoices exist" check.
   Record this in the contract's lifecycle table so it is not forgotten.

**No void, no edit, no delete of a collected signature** — matches HCP and Jobber. A stale one is
flagged by `is_stale` and the crew re-collects; the old row stays as history.

**No new permission keys.** No org "require a signature" setting (Jobber jobs have none).

Then `npm run db:types`.

### API routes (all gate `jobs.view` at the route; the RPC is the real authority)

- `POST /api/jobs/[id]/signatures` — Zod `collectJobSignatureSchema`; if a drawn image, run
  `decodeSignatureImage` and `putObject` **before** the RPC and outside any lock; call
  `rpc('collect_job_signature', ...)`; on RPC error, `discardSignatureImage(objectKey)` and map
  via `signatureWriteError`. → `src/routes/api/jobs/[id]/signatures/+server.ts`
- `GET /api/jobs/[id]/signatures` — `rpc('job_signatures_for_job', ...)`, batch-resolve actor
  names via `profiles`, return `{ signatures }` with `PRIVATE_READ_HEADERS`.
- `GET /api/jobs/[id]/signatures/[signatureId]/image` — mirror the quote image route exactly
  (read the row through the member's own supabase client so RLS decides existence; the URL's job
  id must match the signature's `job_id`; stream via `getObjectStream`; `cache-control: private,
  max-age=3600`, `x-content-type-options: nosniff`, `referrer-policy: no-referrer`).
- `GET /api/jobs/[id]/signatures/[signatureId]/document` — `rpc('job_signature_document', ...)`,
  returns the frozen snapshot shaped by `jobs.view_price`, `PRIVATE_READ_HEADERS`.
- No void/delete route.

### Server support code (15d-1)

- `src/lib/server/signatures/errors.ts` — `signatureWriteError` / `signatureReadError`
  (P0400/P0404/P0409/P0410/42501 → HTTP, copy `src/lib/server/checklists/errors.ts`).
- `src/lib/server/validation/signatures.schema.ts` — `collectJobSignatureSchema` (signature_type,
  signer_name, optional signer_role, statement, method, optional image data-URL, optional
  visit_id); limits mirror the migration.
- `decodeSignatureImage` / PNG validation: extract to `src/lib/server/storage/signature-image.ts`
  with a `buildJobSignatureObjectKey(orgId, jobId)` added to `r2.ts`; the quote server file
  (`src/lib/server/quotes/signatures.ts`) re-exports or keeps its thin wrapper.
- `src/lib/signatures/api.ts` (client) — query keys `jobSignaturesKey(jobId) =
  ['signatures','job',jobId]` and `jobSignatureDocumentKey(sigId)`, `fetchJobSignatures`,
  `fetchJobSignatureDocument`, `collectJobSignature`; `SignatureApiError` parsing `{ error,
  field_errors, reason }` (copy `src/lib/checklists/api.ts` shape).

### 15d-1 verification (server-only)

- DB tests: append-only (`update`/`delete`/`truncate` all raise; org-purge cascade with the flag
  set still works); cross-tenant `job_id` / `visit_id` rejected; `method`/`image` coupling check;
  `document_hash` deterministic and snapshot-sensitive; `is_stale` flips true after a scope/price
  edit; RLS across owner / office / finance / Field-assigned / Field-unassigned / non-member /
  anon (a Field member reads only assigned-job signatures and cannot `collect_job_signature` on an
  unassigned job); `job_signature_document` strips prices without `jobs.view_price`.
- Route/command tests: permission shaping on every route; Zod rejection returns
  `{ error, field_errors }`; a refused RPC leaves no orphaned R2 object (the discard path runs).
- `npm run check`, `npx prettier --check` on touched paths, `npm run test:unit`, `npm run build`.
- 15d-1 leaves a working, tested backend with no UI — nothing half-written.

## 15d-2 — signature-pad UI + browser verification

### Shared signature code (small promotion out of the Quotes folder)

`SignaturePad.svelte` is already written generically ("One pad, both sides of the quote"). Move it
and its value helper to a neutral home and repoint the two existing quote imports — the one place
15d touches non-Jobs code, and a refactor rule 9 ("no duplicated UI") wants anyway:

- `src/lib/components/quotes/SignaturePad.svelte` → `src/lib/components/ui/SignaturePad.svelte`
- `src/lib/quotes/signature.ts` → `src/lib/signatures/signature.ts` (`SignatureValue`,
  `emptySignature`, `signatureIsWhole`, `signatureIsGiven`)
- Repoint: `src/lib/components/quotes/CollectSignatureDialog.svelte`,
  `src/routes/api/quotes/[id]/signature/+server.ts` (if it imports the type).

If Jafar prefers zero churn in Quotes, the fallback is a cross-folder import — noted, not
recommended.

### New Jobs components + wiring

- `src/lib/components/jobs/CollectJobSignatureDialog.svelte` — mirrors
  `CollectSignatureDialog.svelte`. A `signature_type` picker (Work authorization / Work completion /
  Other) that presets the editable `statement` ("I authorize the work described above to proceed" /
  "I confirm the work described above has been completed to my satisfaction" / blank). Shows the
  document about to be signed — identity, work list, **and the total** — built client-side from job
  data already on the detail page. Optional visit picker, `SignaturePad`, Cancel / "Save
  signature". Mounts only while open (clean pad each time); uploads the drawn PNG through the POST
  route. No customer-copy checkbox (15e owns that).
- `src/lib/components/jobs/JobSignaturesCard.svelte` — rail card. Eager `createQuery` on
  `jobSignaturesKey(jobId)`; "Collect signature" button `onhover`-warms the query and
  `onclick` opens the dialog. Each row: "{signature_type} · {signer_name} · {date}", with a
  **"Job changed since signing"** marker when `is_stale` and a "Collect a new signature" prompt.
  Clicking a row opens a read-only "Signed document" panel (`GET .../document` rendered +
  `<img src="/api/jobs/{id}/signatures/{sigId}/image">` for drawn). Empty state matches the
  checklist card's.
- `src/routes/(app)/jobs/[id]/+page.svelte` — mount `<JobSignaturesCard>` in the `rail()` snippet
  near the Notes/History cards. Pass `jobId={saved.job.id}`, `canRecord={saved.can_record_field_records}`,
  `visits={...}` (already in the payload for `JobVisitsSection`). No change to
  `src/routes/api/jobs/[id]/+server.ts` — the permission flags it needs are already returned.
- After a successful collect: `queryClient.invalidateQueries({ queryKey: jobSignaturesKey(jobId) })`
  and `queryClient.invalidateQueries({ queryKey: jobEventsKey(jobId) })` (history).
- Load `.claude/skills/svelte/SKILL.md` before writing components; load `.claude/skills/design/SKILL.md`
  and `.claude/skills/bits-ui/SKILL.md` (Dialog wrapper) before the UI.

### 15d-2 browser verification (owner + Field, desktop + ~520px)

1. Owner opens a job → Signatures card → Collect signature → pick "Work completion", type a name →
   Save → row appears, Job history shows "Collected …'s signature (work_completion)".
2. Owner collects a **drawn** signature on a specific visit → the drawn image renders in the
   signed-document panel; reload → still there.
3. Edit the job's scope/price afterwards → the row shows "Job changed since signing"; open the
   signed document → the snapshot and total are unchanged from what was signed.
4. Field member without `jobs.view_price` opens the signed document → sees the work list, no prices.
5. Assigned Field member collects a signature; unassigned Field member sees neither the job nor
   its signatures.
6. `npm run check`, `npx prettier --check` on touched paths, `npm run build` green, console clean.

## Not in scope (explicit)

- No PDF file, no job-document renderer, no customer share link/email — **Part 15e**.
- No signature column/badge on the Jobs or Visits **list** — reads stay bounded to one job, so
  no `performance-review` gate fires (same as 15c). A list indicator later is its own item and
  triggers the `performance-review` design branch first.
- No offline capture/queue — **Part 15f**.

## Decisions (settled)

1. **Signed snapshot captures** the priced job document + total + signature type + statement (HCP's
   "amount that was approved"). Money in the snapshot is read back behind `jobs.view_price`.
2. **A job with signatures cannot be hard-deleted** — enforced by the append-only trigger now, and
   an explicit check in `delete_job` when that command is built.
3. **No void/edit/delete of a signature.** Stale ones are flagged (`is_stale`) and re-collected.
4. **Customer copy is left out of 15d** — Part 15e owns customer delivery (Jafar's call).

## Implementation notes discovered while scoping

- **No `delete_job` command or `DELETE /api/jobs/[id]` route exists.** Job hard-deletion is not
  built. `jobs.delete` is seeded as a permission key but has no behavior. Decision 2 therefore
  lands as (a) the append-only trigger + (b) a documented rule for the future `delete_job`.
- **Org-purge bypass pattern:** append-only triggers permit `DELETE` only when
  `current_setting('app.organization_purge_in_progress', true) = 'true'`; `UPDATE` stays blocked
  forever. Copy this into `job_signatures_are_append_only()`.
- **`extensions.digest`** — pgcrypto lives in the `extensions` schema in this project. `freeze_quote_version`
  uses `encode(extensions.digest(canonical::text, 'sha256'), 'hex')`.
- **`private.member_has_permission(org, user, key)`** is the 3-arg permission check used inside
  commands; RLS policies use `private.current_permission_scope(key)` + `private.is_assigned_to_job`.
- **15c migration `supabase/migrations/20260911100000_job_checklists_foundation.sql` is the closest
  structural template** — command shape, RLS wording, `comment on` prose, SQLSTATE protocol.
- **`SignaturePad.svelte` + `src/lib/quotes/signature.ts` + `src/lib/server/quotes/signatures.ts`
  + `src/routes/api/quotes/[id]/signature/**`** are the working quote-signature feature to port.
