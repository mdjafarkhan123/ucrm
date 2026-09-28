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
- [ ] `inbox-read-takes-over-a-second` — note file was never written (only its INDEX row); investigate from scratch
- [ ] `client-photos-are-one-request-each` — industry pattern (batched short-lived signed URLs); touches client pages, wait for Part 6
- [ ] `app-wide-rls-helpers-run-once-per-returned-row` — clients family; overlaps Part 6, wait for it
- [ ] `name-search-across-list-apis-falls-back-to-a-sequential-scan` — pg_trgm decision
- [ ] `quote-overview-counts-scan-the-whole-tenant`
- [ ] Browser-verify the four done items, merge to `main`, delete their deferred notes + INDEX rows

## Next

Next task: `inbox-read-takes-over-a-second` (no note exists; investigate from scratch). Branch rebased onto
`main` 2026-09-28, 8 commits ahead, nothing uncommitted.

## Outside actions

- Migration `20260929090000_organization_access_snapshot` pushed to the linked project — check:
  `select version from supabase_migrations.schema_migrations where version = '20260929090000'` — done.
- Also pushed and confirmed: `20260929100000_attachments_note_id_index`, `20260929110000_resolve_quote_access_file`.
  These three files are only on this branch until merge; if `main` gains newer migrations, rebase before pushing.

## Notes

Jafar's decisions 2026-09-28: city box = server search; access checks = "industry best method that is faster"
(combine lookups; any cache must never serve one member's access to another); warmer = top pages, skip on
data saver; photos = "follow industry best pattern". Part 6 runs in parallel in the main folder
(customers-properties) — avoid client/property files until it merges. Memory edits: the worktree session
can't write the main folder — ExitWorktree (keep), commit Memory, re-enter by path. Worktree needs
`node_modules` symlink + copied `.env`; `npm run check`/`build` need `NODE_OPTIONS=--max-old-space-size=8192`;
a build rewrites `static/widget/*.js` — restore them before committing. Pre-existing: 3 "union type too
complex" check errors.
