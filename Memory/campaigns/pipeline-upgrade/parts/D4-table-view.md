# D4 — Table view

**Campaign:** pipeline-upgrade · **Plan:** `docs/sales-pipeline-behavior-contract.md` § board search and table
**Code:** `main`
**Done when:** Switching between Board and Table keeps the filters; a row opens the same Brief.

## Steps

- [x] Speed design: one list across every stage needs its own sort-ready indexes (50 ms → 3.7 ms at 5,000 cards)
- [ ] Apply migration `20261003120000_pipeline_table_view.sql` (adds scope `'all'` + six indexes)
- [ ] Route accepts `stage=all`; table component with sortable headers, Load more, row opens Brief
- [ ] Board/Table switch kept outside the saved-filter controls (`view` in URL, last choice remembered)
- [ ] Checks, browser check, merge, close

## Next

Apply the migration with `npx supabase db push --linked` (dry run first).

## Outside actions

- Migration `20261003120000` — check: `supabase_migrations.schema_migrations` has version `20261003120000` and index `opportunities_board_all_task_idx` exists — pending

## Notes

Table design (industry pattern, Pipedrive list view and HubSpot table view): one flat list, sortable by
clicking a header; only the board's five existing orders are sortable headers.
