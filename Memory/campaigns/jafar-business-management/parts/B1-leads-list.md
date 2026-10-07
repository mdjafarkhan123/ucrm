# B1 — Leads list and adding a Lead

**Campaign:** jafar-business-management · **Plan:** `docs/jafar-business-management-behavior-contract.md` § 1. Find and prepare a lead
**Code:** worktree `../Ucrm-b1-leads`, branch `jafar-b1-leads` (another session writes in the main folder)
**Done when:** Jafar adds "Smith Plumbing, UK"; adding the same website again shows the possible duplicate; filters by status and country work on a large test list

## Steps

- [x] Migration: business relationship + contact methods, list, duplicate check, create (`supabase/migrations/20261007032401_uplift_leads.sql`)
- [x] API `/api/jafar/leads` (GET list, POST add) and `/api/jafar/leads/duplicates`; spec
- [x] Pages `/jafar/leads` and `/jafar/leads/new`; sidebar "Leads" under Business Management
- [x] Database timing on 20,000 practice Leads (`scripts/perf/leads-volume-seed.sql`): list 0.05 s, filtered 0.02 s, search 0.1 s, duplicate check 0.003 s
- [x] Apply migration to the live project
- [x] Merge `main` into the branch
- [ ] Browser check desktop + phone width; browser speed check
- [ ] Merge branch into `main`; remove the worktree

## Next

Browser-check `/jafar/leads` from the worktree dev server (port 5180) on desktop and phone width.

## Outside actions

- Apply `uplift_leads` to remote — check: `select to_regclass('public.platform_business_relationships') is not null` returns true and the migration history lists `uplift_leads` — done (version 20261007032401; file renamed to match)

- Temporary test data in the live project: 20,000 fake Leads (`created_by_email = 'perf-seed@uplift.test'`) and one "Claude Test Plumbing" Lead — delete both after the browser check; check: `select count(*) from platform_business_relationships where created_by_email = 'perf-seed@uplift.test' or business_name = 'Claude Test Plumbing'` returns 0 — pending

## Notes

Owner is not stored yet: everything shows Jafar until stage D adds teammates. "Approved" status arrives with B3.
Duplicate check covers Leads (website, email, phone, name+country), Applications (email, phone, name) and Organizations (name).
