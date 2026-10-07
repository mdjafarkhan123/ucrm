# B1 — Leads list and adding a Lead

**Campaign:** jafar-business-management · **Plan:** `docs/jafar-business-management-behavior-contract.md` § 1. Find and prepare a lead
**Code:** worktree `../Ucrm-b1-leads`, branch `jafar-b1-leads` — all committed; `main` (with A2) already merged into it
**Done when:** Jafar adds "Smith Plumbing, UK"; adding the same website again shows the possible duplicate; filters by status and country work on a large test list

## Steps

- [x] Migration applied to the live project (`supabase/migrations/20261007032401_uplift_leads.sql`)
- [x] API `/api/jafar/leads` (GET list, POST add) and `/api/jafar/leads/duplicates`; spec (14 tests); `npm run check` clean
- [x] Pages `/jafar/leads` and `/jafar/leads/new`; sidebar "Leads" under Business Management
- [x] Speed: practice database, 20,000 Leads — list 0.05 s, filtered 0.02 s, search 0.1 s, duplicate check 0.003 s. Live project from this computer, 20,000 Leads — list 0.4 s, filtered 0.3 s, search 0.47 s per request
- [x] Browser check on phone width and desktop (1366 px): add, duplicate warning by website, status + country filters together (334 of 20,001), overdue shown in red
- [x] Temporary test data removed from the live project (check returned 0)
- [ ] Merge `jafar-b1-leads` into `main`, rerun `npm run check` and the Leads + `src/hooks.server.spec.ts` tests on `main`, remove the worktree and branch; then mark B1 done in the stage file, delete this note, point `NOW.md` at B2

## Next

Merge the branch into `main`. The D1 session (`opus-d1-team`) writes in the main folder: ask it before merging, or merge after it commits. D1 said it will commit to `main` first, and its regenerated `database.types.ts` already includes the Leads tables and functions (on a conflict there, keep `main`'s copy). Expected overlap: `AppShell.svelte`, `Sidebar.svelte`, `database.types.ts`, `query-keys.ts`, `src/routes/jafar/(protected)/+layout.svelte`.

## Notes

Owner is not stored yet: everything shows Jafar until stage D adds teammates. "Approved" status arrives with B3.
Duplicate check covers Leads (website, email, phone, name+country), Applications (email, phone, name) and Organizations (name). Applications have no page of their own, so a matching Application shows as plain text.
