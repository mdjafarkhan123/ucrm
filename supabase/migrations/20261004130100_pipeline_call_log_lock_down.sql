-- Pipeline E4 follow-up: lock down the call history table.
--
-- Supabase gives every new public table full privileges to `anon` and `authenticated` by default. Row-level
-- security already refused every write and every anonymous read, but this table promises members may read
-- it and never write it (only public.pipeline_log_opportunity_call writes), so the privileges now say the
-- same thing, as they do on public.tasks.

revoke all on table public.opportunity_call_logs from anon, authenticated;
grant select on table public.opportunity_call_logs to authenticated;
