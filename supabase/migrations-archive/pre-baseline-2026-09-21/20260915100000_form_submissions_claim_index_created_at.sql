-- Part 4E finding #1: make the worker's submission claim index-ordered.
--
-- public.process_next_form_submission() claims the oldest pending row with:
--   select ... from private.form_submissions
--   where status = 'pending' order by created_at for update skip locked limit 1
--
-- The original partial index led with organization_id:
--   form_submissions_pending_idx (organization_id, created_at) where status = 'pending'
-- The claim never filters by organization_id (it is a single global drain across all
-- tenants, oldest-first), so Postgres could satisfy the WHERE from that partial index but
-- still had to read every matching row and Sort by created_at on every claim -- O(N) per
-- claim, O(N^2) to drain a large backlog. EXPLAIN under a 200-row backlog showed a full
-- index scan (rows=200) feeding a quicksort before the Limit.
--
-- Nothing else consumes a status='pending' filter (idempotency lookups use the
-- (form_id, idempotency_key) unique constraint), so we replace -- not duplicate -- the
-- index with one that leads on created_at. The claim then walks the index in created_at
-- order and skip-locked stops at the first unlocked row: no sort, O(1) per claim. This is
-- the standard competing-consumer queue pattern for a "pending, oldest first" claim.
drop index if exists private.form_submissions_pending_idx;

create index form_submissions_pending_idx
  on private.form_submissions (created_at)
  where status = 'pending';
