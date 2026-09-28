# Part 8 — Speed

**Campaign:** deferred-launch-sweep · **Plan:** none — each task's deferred note is its spec
**Code:** worktree `.claude/worktrees/deferred-sweep-part8`, branch `worktree-deferred-sweep-part8`
**Done when:** each task below is fixed and measured (performance-review verification branch) or re-deferred with Jafar's OK; merged to `main`.

## Steps

- [ ] `get-started-page-weight` — city search through a server route
- [ ] `app-shell-idle-warmer-downloads-every-routine-route` — warm ~10 top routes, skip on data-saver/slow network
- [ ] `jafar-panel-organization-tabs-have-no-hover-prefetch` — copy client page `Tabs.onhover` pattern
- [ ] `list-table-rows-use-goto-instead-of-real-links` — `href` on shared row/menu components
- [ ] `every-entitlement-gated-route-re-reads-the-whole-access-model` — one combined read, no cache
- [ ] `six-unindexed-foreign-keys-from-the-collaboration-tables`
- [ ] `a-customer-file-re-resolves-the-whole-quote-document` — `resolve_quote_access_file` RPC
- [ ] `inbox-read-takes-over-a-second` — note file was never written (only its INDEX row); investigate from scratch
- [ ] `client-photos-are-one-request-each` — industry pattern (batched short-lived signed URLs); touches client pages, wait for Part 6
- [ ] `app-wide-rls-helpers-run-once-per-returned-row` — clients family; overlaps Part 6, wait for it
- [ ] `name-search-across-list-apis-falls-back-to-a-sequential-scan` — pg_trgm decision
- [ ] `quote-overview-counts-scan-the-whole-tenant`

## Next

Start `get-started-page-weight`.

## Notes

Jafar's decisions 2026-09-28: city box = server search; access checks = "industry best method that is faster"
(combine lookups; any cache must never serve one member's access to another); warmer = top pages, skip on
data saver; photos = "follow industry best pattern". Part 6 runs in parallel in the main folder
(customers-properties) — avoid client/property files until it merges. Memory edits: the worktree session
can't write the main folder — ExitWorktree (keep), commit Memory, re-enter by path.
