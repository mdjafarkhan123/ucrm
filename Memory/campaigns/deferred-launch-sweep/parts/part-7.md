# Part 7 — Jobber parity

**Exact next action:** merged into `main` (`0a640513`), worktree removed, both notes deleted. Ask Jafar
for a decision on the 5 items below, one at a time, then build the approved ones.

**The 5 remaining items (each needs Jafar's decision before building; none are a quick fix):**

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
