-- Permanent delete of the heavy customer inside a 1M-text business; rolled back so it can repeat.
begin;
create temp table xact_before on commit drop as
  select relid, schemaname, relname, seq_scan, seq_tup_read, coalesce(idx_scan, 0) as idx_scan, n_tup_del
  from pg_stat_xact_user_tables;
\timing on
select (private.client_deletion_plan('c0f20000-0000-0000-0000-000000000001', 'c0f30000-0000-0000-0000-000000000001') -> 'counts')::text as plan_counts;
select (public.run_client_purge('c0f20000-0000-0000-0000-000000000001', 'c0f30000-0000-0000-0000-000000000001',
  'scheduled') ->> 'status') as purge_status;
\timing off
select a.schemaname || '.' || a.relname as table_name, a.seq_scan - coalesce(b.seq_scan, 0) as seq_scans,
  a.seq_tup_read - coalesce(b.seq_tup_read, 0) as seq_rows_read,
  a.n_tup_del - coalesce(b.n_tup_del, 0) as rows_deleted
from pg_stat_xact_user_tables as a left join xact_before as b using (relid)
where a.seq_tup_read - coalesce(b.seq_tup_read, 0) > 5000
order by seq_rows_read desc limit 15;
rollback;
