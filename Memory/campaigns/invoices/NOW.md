# Invoices: Current Checkpoint

- Goal: Jobber-grounded invoicing and manual collection.
- Active part: **4b — the new-invoice form and the detail page.** 4a (list read model + list screen)
  **COMPLETE, verified, and committed 2026-09-05 (`d947a3a`).** Part 4 was split into 4a/4b on Jafar's
  approval and committed 2026-09-05 (`d947a3a`); draft lifecycle action for 4b is **Mark as Sent + Delete** (email Send is Part 6, Collect Payment
  Part 7).

## Exact next action

Plan and build **4b**: `src/routes/(app)/invoices/new/+page.svelte` (new-invoice form) and
`src/routes/(app)/invoices/[id]/+page.svelte` (detail). Mirror the Jobs/Quotes form shell and detail layout;
reuse shared `work/` components (WorkRecordHeader, ClientPicker, RecordDiscountCard, RecordTaxCard) and the
line editor. Then **wire the list**: in `(app)/invoices/+page.svelte` enable the New Invoice button
(`href={resolve('/(app)/invoices/new')}`) and make rows navigate (`onRowActivate` + client link to
`resolve('/(app)/invoices/[id]', {id})`) — both are deliberately disabled/absent in 4a because those routes
did not exist yet (typed `resolve()` would fail the check). Add both routes to the warm list in
`(app)/+layout.svelte`.

Commands to call (all built in 3a–3c, `public.*`): `create_invoice_draft`, `update_invoice_details`,
`replace_invoice_lines`, `set_invoice_discount`, `set_invoice_tax`, `issue_invoice` (= Mark as Sent, method
`marked_sent`), `delete_invoice_draft`. Totals via `invoice_money`; client balance via
`client_account_balance`. All writes go through new Zod-validated `/api/invoices/*` routes with
expected-revision + idempotency, following the Jobs command routes.

## Blockers and non-obvious risks

- **List/counts are RPCs, not a view.** Invoice status needs money the reader may not select, so 4a serves
  the list via `public.invoice_list_page(...)` (SECURITY DEFINER, set-based status, keyset paged) and the
  overview via `public.invoice_status_counts(org)` (SECURITY DEFINER, set-based). A per-row plpgsql reader
  timed out at 40k; the set-based form is 3.4ms unfiltered / ~150–190ms full-scan. Do not reintroduce a
  per-row derived-status view.
- **One status rule:** `private.invoice_live_status(...)` (pure, immutable, no `SET search_path` so it stays
  inlinable — matches `job_derived_status`). `private.invoice_status_label` now delegates to it. Keep any new
  status reader on this one rule.
- The three advisor WARNs on the new functions (`authenticated_security_definer_function_executable` ×2,
  `function_search_path_mutable` on the pure helper) are the codebase's accepted patterns (same as
  `invoice_money`, `job_derived_status`). Do not "fix" them — revoking execute would break the gated reads.
- Remote migration versions are assigned by the MCP tool; always apply through `mcp__supabase__apply_migration`,
  never `supabase db push`.
- No local Postgres: run pgTAP by pasting the whole test file into `mcp__supabase__execute_sql` (it wraps
  itself in begin/rollback; end with a `finish()` aggregate as the last row-returning statement).
- Money columns (`total_minor`, etc.) are not granted to `authenticated`; read totals only through
  `invoice_money` (gated on `invoices.view_price`), never off the table.

## Essential pointers

- `docs/invoice-behavior-contract.md` — D1–D5 and the Screens section (New/Detail layout)
- `.claude/skills/jobber/jobber-08-screen-patterns.md` — screen behavior; `Design/` for the blueprint
- `src/routes/(app)/jobs/new/+page.svelte`, `jobs/[id]/+page.svelte`, `src/lib/jobs/api.ts` — the template
- `src/lib/invoices/{api,statuses}.ts`, `src/lib/server/validation/invoices.schema.ts` — extend for 4b
- `Memory/campaigns/invoices/ROADMAP.md` — read only to select/plan the next part

Resume command: `read memory and continue the Invoices campaign`.
