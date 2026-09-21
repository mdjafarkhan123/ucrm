-- CRM launch readiness Part 4, Stage 6: a website inquiry's follow-up history on the record it became.
--
-- Established pattern (HighLevel contact "Workflows" panel; docs/research/website-speed-to-lead-patterns-2026-09-17.md):
-- staff see, on the lead itself, whether the follow-up is waiting, paused and why, sent, or stopped and why, and
-- can Resume, Skip or Stop it. The controls are the existing 6D enrollment commands; this migration only adds
-- what the history needs to be truthful and fast.
--
--   1. paused_reason: a pause is either a staff Pause or the Stage 3 customer-reply pause. The reply-pause is the
--      only pause that moves customer_reply_after (the same signal the Stage 4 alert trigger uses), so a BEFORE
--      trigger records the reason without rewriting the commands and engine functions that pause.
--   2. An index to find the form submission behind a Request.
--   3. automation_inquiry_enrollments: the safe summary read for a Request or a chat session.
-- Approved by Jafar 2026-09-17 (the pause-reason column).

-- ---------------------------------------------------------------------------------------------------
-- 1. Why an enrollment is paused.
-- ---------------------------------------------------------------------------------------------------
alter table private.automation_enrollments
  add column paused_reason text check (paused_reason in ('staff', 'customer_reply'));

comment on column private.automation_enrollments.paused_reason is
  'Set while paused: customer_reply when a customer reply paused it (customer_reply_after moved), otherwise '
  'staff. Cleared when the enrollment leaves paused. Maintained by a trigger.';

create function private.automation_enrollments_set_paused_reason()
returns trigger
language plpgsql
set search_path = pg_catalog, private
as $$
begin
  if new.state = 'paused' and old.state is distinct from 'paused' then
    new.paused_reason := case
      when new.customer_reply_after is distinct from old.customer_reply_after then 'customer_reply'
      else 'staff'
    end;
  elsif new.state <> 'paused' then
    new.paused_reason := null;
  end if;
  return new;
end;
$$;

revoke all on function private.automation_enrollments_set_paused_reason() from public, anon, authenticated;

create trigger automation_enrollments_set_paused_reason
  before update of state on private.automation_enrollments
  for each row
  when (new.state is distinct from old.state)
  execute function private.automation_enrollments_set_paused_reason();

-- ---------------------------------------------------------------------------------------------------
-- 2. The submission behind a Request. The worker writes result.request_id once; most rows never have one.
-- ---------------------------------------------------------------------------------------------------
create index form_submissions_request_idx
  on private.form_submissions (organization_id, (result ->> 'request_id'))
  where result ->> 'request_id' is not null;

-- ---------------------------------------------------------------------------------------------------
-- 3. The record-level read.
-- ---------------------------------------------------------------------------------------------------
-- Exactly one of p_request_id / p_chat_session_id. The caller has already confirmed the record is visible to the
-- viewer in this organization. Same safe projection as automation_record_enrollments, plus the subject type, the
-- pause reason, and why the next step is held (a retry reason or a needs-attention reason). Never context,
-- payload, message copy, or worker lease state.
create function public.automation_inquiry_enrollments(
  p_organization_id uuid,
  p_request_id uuid,
  p_chat_session_id uuid,
  p_limit integer default 20
)
returns table (
  enrollment_id uuid,
  recipe_id uuid,
  recipe_name text,
  version_number integer,
  subject_type text,
  state text,
  source text,
  current_step_index integer,
  next_due_at timestamptz,
  customer_messages_sent integer,
  stop_reason text,
  paused_reason text,
  held_reason text,
  created_at timestamptz,
  updated_at timestamptz
)
language sql
stable
security definer
set search_path = pg_catalog, public, private
as $$
  with subjects as (
    select 'form_submission'::text as subject_type, s.id as subject_id
    from private.form_submissions as s
    where p_request_id is not null
      and s.organization_id = p_organization_id
      and s.result ->> 'request_id' is not null
      and s.result ->> 'request_id' = p_request_id::text
    union all
    select 'website_chat_session', w.id
    from public.website_chat_sessions as w
    where p_chat_session_id is not null
      and w.organization_id = p_organization_id
      and w.id = p_chat_session_id
  )
  select
    e.id,
    e.recipe_id,
    r.name,
    v.version_number,
    e.subject_type,
    e.state,
    e.source,
    e.current_step_index,
    coalesce(e.paused_work_due_at, work.due_at),
    e.customer_messages_sent,
    e.stop_reason,
    e.paused_reason,
    coalesce(attention.attention_reason, work.last_error_code),
    e.created_at,
    e.updated_at
  from subjects
  join private.automation_enrollments as e
    on e.organization_id = p_organization_id
    and e.subject_type = subjects.subject_type
    and e.subject_id = subjects.subject_id
  join public.automation_recipes as r on r.id = e.recipe_id and r.organization_id = e.organization_id
  join public.automation_recipe_versions as v on v.id = e.recipe_version_id
  left join lateral (
    select w.due_at, w.last_error_code
    from private.automation_work_items as w
    where w.enrollment_id = e.id and w.state = 'pending'
    order by w.step_index
    limit 1
  ) as work on true
  left join lateral (
    select w.attention_reason
    from private.automation_work_items as w
    where w.enrollment_id = e.id and w.state = 'needs_attention'
    order by w.step_index desc
    limit 1
  ) as attention on true
  order by e.updated_at desc, e.id desc
  limit least(greatest(coalesce(p_limit, 20), 1), 50);
$$;

revoke all on function public.automation_inquiry_enrollments(uuid, uuid, uuid, integer)
  from public, anon, authenticated;
grant execute on function public.automation_inquiry_enrollments(uuid, uuid, uuid, integer) to service_role;

comment on function public.automation_inquiry_enrollments(uuid, uuid, uuid, integer) is
  'Safe follow-up summaries for the website inquiry behind a Request (its form submission) or a chat session: '
  'recipe/version/state/next step/messages sent/stop, pause and hold reasons. Service role only.';
