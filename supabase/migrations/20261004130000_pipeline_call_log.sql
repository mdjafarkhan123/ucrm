-- Pipeline E4: logging a phone call from a card's Brief.
--
-- Tapping Call opens the phone's dialler and records nothing. Afterwards a person may log what happened, by
-- choosing one of five outcomes (Jafar, 2026-10-02, after the HubSpot / Pipedrive / GoHighLevel / Jobber /
-- Housecall Pro comparison in docs/research/pipeline-call-logging-industry-patterns-2026-10-02.md).
--
-- Only a call that reached the customer is progress: "Connected" and "Left voicemail" restart the card's
-- inactivity clock (`progress_at`). "No answer", "Busy" and "Wrong number" are kept in the history but do not,
-- so a customer who never picks up cannot make a stuck card look healthy. Nothing here ever records an
-- outcome on its own -- a row exists only because a person chose one.

-- 1. The history -------------------------------------------------------------------------------------------

create table public.opportunity_call_logs (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  opportunity_id uuid not null,
  outcome text not null,
  note text,
  logged_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  constraint opportunity_call_logs_opportunity_organization_fk
    foreign key (organization_id, opportunity_id)
    references public.opportunities (organization_id, id) on delete cascade,
  constraint opportunity_call_logs_outcome_check
    check (outcome in ('connected', 'left_voicemail', 'no_answer', 'busy', 'wrong_number')),
  constraint opportunity_call_logs_note_check
    check (note is null or (char_length(note) between 1 and 2000))
);

comment on table public.opportunity_call_logs is
  'Calls a person chose to log from a Pipeline card. Members may read this table, never write it: the only write is public.pipeline_log_opportunity_call, which checks pipeline.edit. A row is never created automatically when a dialler opens.';

-- The Brief lists one card''s calls newest first; the organization column leads, as on tasks.
create index opportunity_call_logs_opportunity_idx
  on public.opportunity_call_logs (organization_id, opportunity_id, created_at desc);

alter table public.opportunity_call_logs enable row level security;

create policy "permitted members can view call logs"
  on public.opportunity_call_logs
  for select
  to authenticated
  using (organization_id in (select private.permitted_organizations('pipeline.view')));

grant select on table public.opportunity_call_logs to authenticated;
grant all on table public.opportunity_call_logs to service_role;

-- 2. Logging a call ----------------------------------------------------------------------------------------

create function public.pipeline_log_opportunity_call(
  target_opportunity_id uuid,
  new_outcome text,
  new_note text default null
)
returns table (
  id uuid,
  opportunity_id uuid,
  outcome text,
  note text,
  logged_by uuid,
  created_at timestamptz,
  restarted_progress boolean
)
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  target_organization_id uuid := private.pipeline_lock_task_parent(target_opportunity_id);
  created public.opportunity_call_logs;
  restarts boolean := new_outcome in ('connected', 'left_voicemail');
begin
  if new_outcome is null or new_outcome not in
     ('connected', 'left_voicemail', 'no_answer', 'busy', 'wrong_number') then
    raise exception 'Choose what happened on the call.' using errcode = '23514';
  end if;

  insert into public.opportunity_call_logs as call_log (
    organization_id, opportunity_id, outcome, note, logged_by
  )
  values (
    target_organization_id,
    target_opportunity_id,
    new_outcome,
    nullif(trim(coalesce(new_note, '')), ''),
    (select auth.uid())
  )
  returning call_log.* into created;

  -- Only an open card has a warning to clear; a won or lost card keeps its clock as it was.
  if restarts then
    update public.opportunities as opportunity
    set progress_at = now()
    where opportunity.id = target_opportunity_id
      and opportunity.organization_id = target_organization_id
      and opportunity.outcome = 'open';
  end if;

  return query select
    created.id, created.opportunity_id, created.outcome, created.note, created.logged_by,
    created.created_at, restarts;
end;
$$;

revoke all on function public.pipeline_log_opportunity_call(uuid, text, text) from public, anon;
grant execute on function public.pipeline_log_opportunity_call(uuid, text, text) to authenticated;
