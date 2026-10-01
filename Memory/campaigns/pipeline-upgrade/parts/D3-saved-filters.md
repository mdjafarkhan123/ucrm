# D3 Saved filters

**Where:** worktree `.claude/worktrees/pipeline-d3`, branch `worktree-pipeline-d3`. Waiting to merge.
**Done when:** see `stages/D-move-find-volume.md` row D3.

Decisions (Pipedrive/HubSpot pattern): a saved filter keeps sort, salesperson, lead source and created date —
never the search box. Personal = only that person; shared = everyone with the Pipeline, only owners and
admins change it. Sharing is chosen when saving; there is no "unshare" (delete and save again). 50 each.

## Steps

- [x] Table `pipeline_saved_filters` — migration `20261003100000` is applied to the remote database
      (check: `npx supabase migration list --linked`). Rules tested live as sales, office and owner.
- [x] API `/api/pipeline/saved-filters`, Saved button, Save and Manage windows, tests (293 Pipeline tests pass).
- [x] Browser check passed 2026-10-01 (headless): sales filter survives signing in again and office cannot
      see it; owner's shared filter shows for office, who gets 404/403 trying to change, delete or share;
      Update after changing a control works; phone width fits.
- [ ] Merge to `main`, then mark D3 done and delete this note.

## Next

Merge `worktree-pipeline-d3` into `main`. It was blocked only because the onboarding D3 session had
uncommitted edits to `src/lib/database.types.ts`, which this branch also changes (it adds the
`pipeline_saved_filters` block). Until merged, `main` lacks migration `20261003100000` that the remote
database already has, so a `supabase db push` from `main` may complain — merge first.
