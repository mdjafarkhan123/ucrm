# Part 8 — Speed

**Campaign:** deferred-launch-sweep · **Plan:** none — each task's deferred note is its spec
**Code:** worktree `.claude/worktrees/deferred-sweep-part8`, branch `worktree-deferred-sweep-part8`
**Done when:** each task below is fixed and measured (performance-review verification branch) or re-deferred with Jafar's OK; merged to `main`.

## Steps

- [x] `get-started-page-weight` — Browser check pending.
- [x] `app-shell-idle-warmer-...`
- [x] `jafar-panel-organization-tabs-...`
- [x] `list-table-rows-use-goto-...`
- [x] `every-entitlement-gated-route-re-reads-the-whole-access-model`
- [x] `six-unindexed-foreign-keys-from-the-collaboration-tables`
- [x] `a-customer-file-re-resolves-the-whole-quote-document`
- [x] `inbox-read-takes-over-a-second`
- [ ] `client-photos-are-one-request-each` — industry pattern (batched short-lived signed URLs); touches client pages, wait for Part 6
- [ ] `app-wide-rls-helpers-run-once-per-returned-row` — clients family; overlaps Part 6, wait for it
- [ ] `name-search-across-list-apis-falls-back-to-a-sequential-scan` — Jafar 2026-09-28: add pg_trgm now. WIP migration `20260929130000_trigram_name_search` committed on branch, **NOT pushed**. Rolled-back bench (50k-client tenant in 200k): no-match search 240 → 3.3 ms; common terms unchanged. Index 13 MB per 200k clients
- [x] `quote-overview-counts-scan-the-whole-tenant`
- [ ] Browser-verify the first four done items, merge to `main`, delete the done items' deferred notes + INDEX rows (`inbox-read-takes-over-a-second` has only a row, no file)

## Next

Finish the trigram migration, then push it: (1) remove the `files` index — `list_files` searches
`name OR caption OR exists(linked record)`, and the plan stays a Seq Scan, so it is dead weight; file search
would need `list_files` restructured (ask Jafar or defer). (2) Measure write cost: 2,000 client inserts took
1.8 s with the index but no no-index baseline was taken — rerun both in one rolled-back script (scratch scripts
were in the old session's scratchpad; rebuild them: fake org via `session_replication_role = replica`).
(3) `db push --linked`, regenerate types, commit. Then the browser-verify + merge step. Branch 12 commits
ahead of `main`. 72 unit tests fail on `main` too — deferred note `quote-api-tests-never-learned-the-rate-limit`.

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
