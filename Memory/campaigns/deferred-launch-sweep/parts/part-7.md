# Part 7 — Jobber parity

**Exact next action:** merge worktree branch `worktree-deferred-sweep-part7` (commit `8006a42f`, in
`.claude/worktrees/deferred-sweep-part7`) into `main` — first check `main`'s working tree is clean of
another session's uncommitted work before merging. After merge: run svelte-check + prettier once more from
`main`, delete `Memory/deferred/request-list-search-doesn-t-match-client-name.md` and
`Memory/deferred/last-communication-rail-card-on-the-client-page.md` + their two rows in
`Memory/deferred/INDEX.md`, remove the worktree (`ExitWorktree` with `path` then `action: "remove"`, or
`git worktree remove`), and release reservation `34d9a57131a3` (`agent-work.py release 34d9a57131a3`).

Both merged changes were browser-verified live on Raad LTD (office-role login) before committing: request
search by "Riverbend" now finds that client's requests even though neither title contains the name; the
client detail page's new "Last communication" rail card shows date/subject and its "Read more..." link
correctly opens the Communication tab.

**Then, for the 5 remaining Part 7 items, get Jafar's decision before building each** (none are a quick fix):

1. `request-status-filter-matches-the-stored-status-not-the-displayed-one` — decide: filter by the same
   computed display-status the counts card already derives (extra per-row date math, needs a view/RPC like
   `request_status_counts`), or just relabel the existing stored-status filter so it stops promising something
   it doesn't do. Recommend the relabel — cheaper, no new view/RLS surface, still honest.
2. `quote-composer-has-no-financial-rail-or-proposal-sections` — decide whether `/quotes/new` starts writing
   the quote on first field entry (so Discount/Tax/Introduction/Client message can attach immediately) or
   keeps redirecting to the detail page to finish. This is a composer architecture change, not a UI add-on.
3. `client-detail-page-still-uses-the-superseded-staging-dialog-edit-shape` — a real rewrite to Jobber's
   3-edit-pattern convention (`.claude/skills/jobber/jobber-08-screen-patterns.md` § How WE compare); touches
   `clients/[id]/+page.svelte` and `ClientDetailsDialog.svelte`.
4. `job-visit-card-backend-fields` — needs a Jobs-owned decision on the off-series deviation flag (stored
   column vs. server-side comparison against the recurrence rule) before the completed-by/off-series work
   starts.
5. `no-image-on-a-price-list-item` — needs schema approval (new migration on `catalog_items` via the File
   Manager catalog, not the legacy `attachments` table) before the upload flow is built.

**Blockers:** none technical; each of the 5 above is blocked on a product decision, not code.

**Pointers:**
- Memory/campaigns/deferred-launch-sweep/ROADMAP.md Part 7
