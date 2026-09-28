# Part 8 — Speed

**Campaign:** deferred-launch-sweep · **Plan:** none — each task's deferred note is its spec
**Code:** worktree `.claude/worktrees/deferred-sweep-part8`, branch `worktree-deferred-sweep-part8`
**Done when:** each task below is fixed and measured (performance-review verification branch) or re-deferred with Jafar's OK; merged to `main`.

## Steps

- [x] `get-started-page-weight` — server city search; page JS ~8 MB → ~110 KB gzip. Browser check pending (Chrome extension was disconnected)
- [x] `app-shell-idle-warmer-...` — 13 daily routes, skip on Save-Data/2G; ~890 → ~520 KB gzip. CLAUDE.md warm-list rule updated
- [x] `jafar-panel-organization-tabs-...` — Communications tab (the only tab with own reads) prefetches on hover via shared `src/lib/jafar/organization-communications-queries.ts`
- [x] `list-table-rows-use-goto-...` — rows already had real links; real gap was data. `DataTable` `onRowHover` (100 ms intent) prefetches detail on Jobs/Invoices/Quotes/Requests. Clients list waits for Part 6
- [x] `every-entitlement-gated-route-re-reads-the-whole-access-model` — `public.organization_access_snapshot` (invoker, no cache); identical output all roles; 440 → 81 ms median
- [x] `six-unindexed-foreign-keys-from-the-collaboration-tables` — only `attachments.note_id` needed an index; the rest are covered or account-delete-only (migration comment says why)
- [x] `a-customer-file-re-resolves-the-whole-quote-document` — `resolve_quote_access_file`; same answers on all 546 live link/file pairs; expired link now 404 not 500
- [x] `inbox-read-takes-over-a-second` — each step is one ~70–130 ms trip to the remote DB, not DB work; access snapshot + concurrent rate limit took it from >1 s to ~580 ms here. Production (DB beside app) is the real cure. No note file exists — delete only its INDEX row at merge
- [ ] `client-photos-are-one-request-each` — industry pattern (batched short-lived signed URLs); touches client pages, wait for Part 6
- [ ] `app-wide-rls-helpers-run-once-per-returned-row` — clients family; overlaps Part 6, wait for it
- [ ] `name-search-across-list-apis-falls-back-to-a-sequential-scan` — Jafar 2026-09-28: add pg_trgm now (Clients, Requests, Jobs, catalog, files)
- [x] `quote-overview-counts-scan-the-whole-tenant` — `quote_status_tallies` counter cache (triggers, never stale); 12.9 → 0.07 ms. The note's `pipeline_stage_counts_read_model` never existed
- [ ] Browser-verify the four done items, merge to `main`, delete their deferred notes + INDEX rows

## Next

Next task: name search with pg_trgm (design verdict first). Branch 10 commits ahead of `main`, nothing
uncommitted. 72 unit tests fail on `main` too (quote specs; deferred note `quote-api-tests-never-learned-the-rate-limit`) — not ours.

## Outside actions

- Migration `20260929090000_organization_access_snapshot` pushed to the linked project — check:
  `select version from supabase_migrations.schema_migrations where version = '20260929090000'` — done.
- Also pushed and confirmed: `20260929100000_attachments_note_id_index`, `20260929110000_resolve_quote_access_file`,
  `20260929120000_quote_status_tally`. `db push` runs a file as one transaction but rejects `LOCK TABLE`.
  These three files are only on this branch until merge; if `main` gains newer migrations, rebase before pushing.

## Notes

Jafar 2026-09-28: photos = "follow industry best pattern". Part 6 runs in the main folder — avoid
client/property files until it merges. Worktree needs `node_modules` symlink + `.env`; `npm run check`/`build`
need `NODE_OPTIONS=--max-old-space-size=8192`; a build rewrites `static/widget/*.js` — restore before
committing. Pre-existing: 3 "union type too complex" check errors.
