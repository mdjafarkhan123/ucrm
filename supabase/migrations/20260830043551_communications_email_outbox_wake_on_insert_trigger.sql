-- Communications R2: make the immediate email-outbox wake automatic for EVERY send.
--
-- 20260912100000 added request_communication_email_outbox_wake() and the send routes called it by hand after
-- enqueuing. That works but is fragile: every future sender (invoice email, job reminders, quote follow-ups,
-- ...) would have to REMEMBER to call it, and a forgotten call silently drops that send back to the 1-minute
-- Cron latency. This replaces the per-route calls with a single statement-level trigger on the outbox, so the
-- instant nudge fires automatically the moment anything lands in the email outbox -- present and future senders
-- alike -- and can never be forgotten.
--
-- This is the same mechanism Supabase Database Webhooks use (a trigger that fires pg_net on write). The
-- once-a-minute Cron sweep remains the guaranteed backstop, and the SKIP LOCKED claim remains the exactly-once
-- boundary; the trigger only changes WHEN the drain wakes. LISTEN/NOTIFY would be lower latency but needs a
-- persistent worker we do not run yet -- it is the planned upgrade once the Docker worker lands.
--
-- Design choices:
--   * STATEMENT-level with a transition table, not row-level: one enqueue statement fires exactly one wake no
--     matter how many rows it inserted, so a multi-row send never multiplies wakes. Overlapping wakes still
--     collapse to already_running via the single-flight lease.
--   * Due-now guard: only wake when at least one newly-inserted row is actually due (available_at <= now()).
--     A future-dated / scheduled send must not trigger an immediate drain; the Cron sweep picks it up when due.
--   * The wake fn already never raises, so a wake problem can never fail the enqueue transaction.

create or replace function public.trigger_communication_email_outbox_wake()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  -- One wake per statement, and only if something is due right now. Scheduled/future rows wait for the Cron.
  if exists (select 1 from inserted where available_at <= now()) then
    perform public.request_communication_email_outbox_wake();
  end if;
  return null;
end;
$$;

comment on function public.trigger_communication_email_outbox_wake() is
  'Statement-level AFTER INSERT trigger on communication_outbox_events: fires one best-effort immediate '
  'outbox wake per enqueue when a newly-inserted row is due now. Automatic instant dispatch for every email '
  'sender; the minute Cron remains the guaranteed backstop.';

revoke all on function public.trigger_communication_email_outbox_wake() from public, anon, authenticated;

create trigger communication_email_outbox_wake_on_insert
  after insert on public.communication_outbox_events
  referencing new table as inserted
  for each statement
  execute function public.trigger_communication_email_outbox_wake();
