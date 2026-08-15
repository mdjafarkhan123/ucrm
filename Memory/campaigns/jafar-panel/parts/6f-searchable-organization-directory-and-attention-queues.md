# Part 6F: Searchable Organization Directory and Attention Queues (closed)

## Approved behavior

Source of truth: `docs/jafar-completion-contract.md`, "Commercial control decisions".

- Search matches organization name, slug, and every owner-role member's email; paginate by
  `created_at, id` descending, default page size 50.
- Attention means a real owner action is waiting. Suspension alone is not attention.
- Reasons: `access_overdue`, `expiring_soon`, `administrator_missing`,
  `administrator_ownership_unclear`, `setup_or_recovery_failed`, `legacy_review`.
- No owner and multiple owners are separate reasons; search matches every owner email when
  ownership is unclear.
- Expired free access with no paid coverage becomes `access_overdue` until access is granted,
  paid coverage is recorded, or the organization is suspended. Gated to `lifecycle_status = active`
  only — a pending_setup or suspended organization is never `access_overdue`.
- `expiring_soon` fires when temporary free access or a package (feature/limit) exception expires
  within 7 calendar days in the organization's own commercial timezone. No dismissal action.
- Totals count unique organizations; a directory row shows every current reason; one reason filter
  may be selected at a time.

## What was built

- `supabase/migrations/20260814130000_owner_organization_directory.sql`: index
  `organizations (created_at desc, id desc)` plus `public.owner_organization_directory(...)`, a
  `security definer`, `language sql stable` function granted to `service_role` only (revoked from
  `anon`/`authenticated`). It joins `organization_members` + `auth.users` to search owner email —
  the reason this had to be a database function rather than plain PostgREST: per-row Auth admin API
  calls don't scale to a list screen.
- `supabase/tests/database/owner_organization_directory.sql`: 26 pgTAP assertions (privileges, one
  fixture per attention reason, owner-email search, reason filter, three-page cursor walk). Verified
  live against the remote database inside a rolled-back transaction (26/26 passed) since this
  session had no local Supabase/psql CLI.
- `src/lib/server/validation/organization-directory.schema.ts`: Zod query schema (`search`,
  `attention_reason` enum, `cursor`, `limit`).
- `src/routes/api/jafar/organizations/+server.ts`: GET now calls the RPC instead of a plain
  `organizations` select. The page cursor is an opaque base64url token of `{created_at, id}` built
  server-side from the function's `next_cursor` — the browser never sees raw keyset values.
- `src/routes/jafar/(protected)/organizations/+page.svelte`: debounced (300ms) server search,
  attention-reason `Select` (options carry live counts, e.g. "No administrator (1)"), `Load more`
  button via `createInfiniteQuery`, KPI cards and attention counts sourced from the function's
  `totals` (global, unaffected by search) rather than the loaded page.
- `src/routes/api/jafar/organizations/organizations.spec.ts`: 10 route-boundary tests (auth,
  validation, cursor encode/decode, RPC argument passthrough, error mapping).

## Non-obvious implementation notes

- **`setup_or_recovery_failed` has no data source yet.** It queries
  `platform_operation_attempts` for rows with `target_kind = 'organization'` and
  `status in ('pending', 'retrying')`. Nothing in the codebase writes such a row today —
  administrator recovery is Part 7, not yet built. Jafar explicitly approved wiring the reason now
  so it lights up automatically once Part 7 ships, rather than leaving a stub to revisit. If a
  future organization-targeted operation type turns out to need *exclusion* from this reason (a
  general provider failure that isn't setup/access/recovery), that will need an explicit allowlist
  added to the function — there wasn't one to design against yet.
- **Attention-reason array order is a display decision, not contract text.** The function orders
  each row's `attention_reasons` (and the urgency used to rank filter chips) as: `access_overdue`,
  `administrator_missing`, `administrator_ownership_unclear`, `setup_or_recovery_failed`,
  `expiring_soon`, `legacy_review`. Reasonable to revisit if Jafar wants different urgency.
- **The old client-side "Lifecycle" filter was dropped**, not carried forward. The approved 6F
  scope only specifies search + attention-reason filtering server-side; re-adding a lifecycle
  dropdown would need it added to the RPC's filter set (currently only `attention_reason`) since
  client-side filtering on an already-paginated page would show misleading partial counts.
  Lifecycle is still visible per row via the existing badge.
- **`totals.matching`** is the only totals field scoped to the current search+reason filter; every
  other totals field (`all`, `active`, `suspended`, `pending_setup`, `attention.*`) is global,
  matching the pre-6F header's always-platform-wide KPI cards.
- Pre-existing, unrelated to 6F: `SearchInput` renders both its own custom clear button and the
  browser's native `type="search"` clear-X, which visually double up. Not touched — it's shared by
  other pages and out of scope here.

## Verification

- `npx tsc --noEmit` clean on the new/changed files.
- `npx svelte-check` clean on the rebuilt page.
- pgTAP: 26/26 passed against remote (rolled back).
- Vitest: 10/10 passed (`organizations.spec.ts`).
- `mcp__supabase__get_advisors`: no new security or performance findings beyond the expected
  "index not yet used" info-level note for the brand-new `organizations_created_at_id_idx`.
- Browser-verified against the real 4-organization remote dataset at
  `app.upliftcontractor.com/jafar/organizations`: search by name (`raad` → 1 of 1), attention-reason
  filter (`No administrator (1)` → xdasd only), KPI cards and per-row badges match expected values
  (Riverside Legacy Demo: Needs Review/legacy_review; xdasd: No Administrator). No console errors,
  one clean `200` network call. Load-more was not exercised — only 4 real organizations exist, so
  there is no second page to fetch yet.
