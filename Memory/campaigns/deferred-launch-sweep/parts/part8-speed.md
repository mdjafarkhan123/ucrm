# Part 8 — Speed

**Campaign:** deferred-launch-sweep · **Plan:** none — each task's deferred note is its spec
**Code:** worktree `.claude/worktrees/deferred-sweep-part8`, branch `worktree-deferred-sweep-part8`
**Done when:** each task below is fixed and measured (performance-review verification branch) or re-deferred with Jafar's OK; merged to `main`.

## Steps

- [x] `get-started-page-weight` — server city search; page JS ~8 MB → ~110 KB gzip. Browser check pending (Chrome extension was disconnected)
- [x] `app-shell-idle-warmer-...` — 13 daily routes, skip on Save-Data/2G; ~890 → ~520 KB gzip. CLAUDE.md warm-list rule updated
- [x] `jafar-panel-organization-tabs-...` — Communications tab (the only tab with own reads) prefetches on hover via shared `src/lib/jafar/organization-communications-queries.ts`
- [x] `list-table-rows-use-goto-...` — rows already had real links; real gap was data. `DataTable` `onRowHover` (100 ms intent) prefetches detail on Jobs/Invoices/Quotes/Requests. Clients list waits for Part 6
- [ ] `every-entitlement-gated-route-re-reads-the-whole-access-model` — one combined read, no cache
- [ ] `six-unindexed-foreign-keys-from-the-collaboration-tables`
- [ ] `a-customer-file-re-resolves-the-whole-quote-document` — `resolve_quote_access_file` RPC
- [ ] `inbox-read-takes-over-a-second` — note file was never written (only its INDEX row); investigate from scratch
- [ ] `client-photos-are-one-request-each` — industry pattern (batched short-lived signed URLs); touches client pages, wait for Part 6
- [ ] `app-wide-rls-helpers-run-once-per-returned-row` — clients family; overlaps Part 6, wait for it
- [ ] `name-search-across-list-apis-falls-back-to-a-sequential-scan` — pg_trgm decision
- [ ] `quote-overview-counts-scan-the-whole-tenant`
- [ ] Browser-verify the four done items, merge to `main`, delete their deferred notes + INDEX rows

## Next

Start `every-entitlement-gated-route-re-reads-the-whole-access-model` (read `src/lib/server/access/effective.ts`,
`permission.ts`, report `docs/research/jobs-performance-verification-2026-09-10.md`).

## Notes

Jafar's decisions 2026-09-28: city box = server search; access checks = "industry best method that is faster"
(combine lookups; any cache must never serve one member's access to another); warmer = top pages, skip on
data saver; photos = "follow industry best pattern". Part 6 runs in parallel in the main folder
(customers-properties) — avoid client/property files until it merges. Memory edits: the worktree session
can't write the main folder — ExitWorktree (keep), commit Memory, re-enter by path. Worktree needs
`node_modules` symlink + copied `.env`; `npm run check`/`build` need `NODE_OPTIONS=--max-old-space-size=8192`;
a build rewrites `static/widget/*.js` — restore them before committing. Pre-existing: 3 "union type too
complex" check errors.
