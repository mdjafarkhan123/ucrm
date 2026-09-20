# M2 — Customer groups and exact recipient preview

Approved behavior: blueprint §8 step 2 (filters, recommended groups, preview split, exclusion reasons) and
§10 (consent, destination, frequency). Plan: `docs/marketing-first-release-plan.md` §3 M2.

## Slices

- **M2a (server):** `marketing_customer_groups` table, Zod rule schema, one `security definer` rule compiler +
  two read functions (counts, paged list), `/api/marketing/customer-groups*`, unit + SQL tests.
- **M2b (UI):** Marketing → Customer groups view: saved-group list with current counts, rule builder,
  live count, "View customers" preview split.

## Performance design verdict (design branch, 2026-09-20)

```
Performance Design - Marketing customer groups and recipient preview
Growth path       : One preview evaluates every non-deleted Client in one organization and, per Client,
                    EXISTS lookups into tag_assignments, properties, jobs, job_line_items, job_visits,
                    plus a left join to the Client's email method, consent state, contact policy, and
                    active suppressions. Dominant term: Clients per organization (N).
Workload contract : Data - assume up to 50k Clients, ~1 email method and ~1 property each, ~5 Jobs each per
                    large organization; most organizations are far smaller. Traffic - preview is a
                    permissioned, staff-only read, debounced to at most a few calls per rule edit, never
                    public. Delivery - count summary under ~300 ms on a 50k-Client organization; the
                    customer list returns one bounded keyset page (50 rows). Correctness - counts must be
                    exact at read time; the campaign snapshot (M4) re-derives from the same compiler inside
                    the launch transaction, so preview and launch can never diverge.
Chosen shape      : One plpgsql compiler that turns validated rule JSON into parameterized SQL from a fixed
                    whitelist of fragments (values only ever bound through USING; no user text becomes SQL).
                    Two callers: marketing_preview_counts (one pass, FILTER aggregates for matches,
                    eligible, each exclusion reason, duplicate destinations) and
                    marketing_preview_recipients (same match, keyset page ordered by display_name, id).
                    Live bounded queries only - no counter table, no materialized group membership, no
                    server cache. TanStack Query holds the browser copy keyed by organization + rule hash.
Complexity cost   : One new table (marketing_customer_groups). One new index
                    job_line_items (organization_id, source_catalog_item_id) for the "service used" filter;
                    every other filter is served by an index that already exists. No queue, cache, or
                    denormalized count.
Rejected options  : Materialized group membership or a stored count column - rejected: the count must be
                    exact at read time and would need invalidation on every Client, Job, tag, and consent
                    write. A single static kitchen-sink query with "(param is null or col = param)" -
                    rejected: it defeats index use. Compiling rules in TypeScript - rejected: M4's launch
                    snapshot must run the same logic inside a database transaction, and two compilers drift.
Failure behavior  : Compiler rejects any rule key or operator outside the whitelist. Functions are
                    security definer with a fixed search_path and take the organization id pinned by the
                    API route after the permission check, never from user input. Statement timeout bounds a
                    pathological rule set. A saved group holds rules only, so CRM edits change counts, never
                    launched history.
Verification plan : Seed one throwaway organization with 50k Clients / 50k contact methods / 250k Jobs /
                    250k line items, then collect EXPLAIN (ANALYZE, BUFFERS) for: the widest rule set, the
                    "service used" filter (with and without the new index), the city filter, and one keyset
                    page. Record wall time for the count query and page query, and the API payload size.
                    Drop the throwaway organization afterwards. Add
                    properties (organization_id, lower(city)) only if its plan shows the city filter needs it.
Open decisions    : None blocking. The 7-day frequency exclusion has no data source until M4 writes
                    recipient rows; M2 ships the reason in the enum and reports 0 for it, and M4 adds the
                    join. Noted so the reason list does not change shape later.
Overall           : Ready
```

## Acceptance checks

- Saved group stores rules, not members; counts follow CRM changes.
- Preview separates matches, eligible, excluded-by-reason, duplicate destinations, with the blueprint's
  plain reasons.
- One email destination appears once, with the chosen primary Customer identity shown.
- Rule JSON outside the whitelist is refused by both Zod and the compiler.
- Tenant isolation: a group and a preview never read another organization's rows.
