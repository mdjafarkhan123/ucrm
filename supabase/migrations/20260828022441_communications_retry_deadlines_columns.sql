alter table public.communication_delivery_intents
  add column retry_class text not null default 'standard'
    check (retry_class in ('standard', 'payment_receipt', 'appointment_reminder', 'optional_followup')),
  add column retry_window_ends_at timestamptz,
  add column expires_at timestamptz;

comment on column public.communication_delivery_intents.retry_class is
  'Which useful-life clock this message runs on. Set by the caller; the deadline itself is derived.';
comment on column public.communication_delivery_intents.retry_window_ends_at is
  'Required for appointment_reminder, optional for optional_followup: the caller''s own boundary.';
comment on column public.communication_delivery_intents.expires_at is
  'Derived deadline. Past it the claim cancels the message instead of releasing it.';

create or replace function private.resolve_communication_email_retry_deadline(
  p_retry_class text,
  p_queued_at timestamptz,
  p_window_ends_at timestamptz
)
returns timestamptz
language sql
immutable
set search_path to 'pg_catalog'
as $$
  select case p_retry_class
    when 'standard' then p_queued_at + interval '24 hours'
    when 'payment_receipt' then p_queued_at + interval '72 hours'
    when 'appointment_reminder' then p_window_ends_at
    when 'optional_followup' then least(
      coalesce(p_window_ends_at, 'infinity'::timestamptz), p_queued_at + interval '24 hours')
  end;
$$;

comment on function private.resolve_communication_email_retry_deadline(text, timestamptz, timestamptz) is
  'The retry deadline for one message class, per docs/contractor-email-contract.md.';

revoke all on function private.resolve_communication_email_retry_deadline(text, timestamptz, timestamptz)
  from public, anon, authenticated;

create or replace function private.communication_delivery_intent_set_retry_deadline()
returns trigger
language plpgsql
set search_path to 'pg_catalog', 'public', 'private'
as $$
begin
  if new.retry_class = 'appointment_reminder' and new.retry_window_ends_at is null then
    raise exception 'An appointment reminder needs the end of its reminder window.'
      using errcode = 'check_violation';
  end if;

  new.expires_at := private.resolve_communication_email_retry_deadline(
    new.retry_class, coalesce(new.created_at, now()), new.retry_window_ends_at);
  return new;
end;
$$;

create trigger communication_delivery_intents_set_retry_deadline
before insert or update of retry_class, retry_window_ends_at
on public.communication_delivery_intents
for each row execute function private.communication_delivery_intent_set_retry_deadline();

update public.communication_delivery_intents
set expires_at = created_at + interval '24 hours'
where expires_at is null;

alter table public.communication_delivery_intents
  alter column expires_at set not null;
