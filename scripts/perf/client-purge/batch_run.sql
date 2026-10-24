-- Day-30 batch throughput: purge 20 ordinary customers of the 1M-text business (500 texts, 100 replies,
-- 5 jobs, 10 visits each) back to back in one rolled-back transaction; per-customer time = total / 20.
begin;
\timing on
select count(*) filter (where public.run_client_purge('c0f20000-0000-0000-0000-000000000001', md5('1-c-' || g)::uuid,
  'scheduled') ->> 'status' is not null) as purged
from generate_series(1, 20) g;
\timing off
rollback;
