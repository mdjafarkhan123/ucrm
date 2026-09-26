-- Operational email Part 5B: a contractor asks Jafar to set up their business email.
--
-- One row per ask. A request only ever says open / cancelled / declined (Jafar closed it with a note) /
-- fulfilled. "Setting up" and "Ready" are NOT stored: they are read from the sending-domain rows that already
-- exist, so the two can never drift and the provisioning code stays untouched. A request counts as fulfilled
-- once any sending domain has been created for the organization after the request was made (a removed domain
-- still counts, so a later removal never resurrects an old ask).
--
-- Follows communication_sms_registrations: one status column, a lifecycle check tying status to its
-- timestamps and note, server-only access, and writes only through named commands.

create table public.communication_email_setup_requests (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  requested_by uuid,
  root_domain text not null,
  mailbox_provider text not null,
  note text,
  status text not null default 'open',
  closed_note text,
  closed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint communication_email_setup_requests_domain_check check (
    char_length(root_domain) between 4 and 253
    and root_domain ~ '^(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$'
  ),
  constraint communication_email_setup_requests_provider_check check (
    mailbox_provider in ('google_workspace', 'microsoft_365', 'godaddy', 'hostinger', 'other', 'none')
  ),
  constraint communication_email_setup_requests_note_check check (
    note is null or char_length(note) between 1 and 1000
  ),
  constraint communication_email_setup_requests_status_check check (
    status in ('open', 'cancelled', 'declined', 'fulfilled')
  ),
  constraint communication_email_setup_requests_closed_note_check check (
    closed_note is null or char_length(closed_note) between 1 and 1000
  ),
  constraint communication_email_setup_requests_lifecycle_check check (
    (status = 'open' and closed_at is null and closed_note is null)
    or (status in ('cancelled', 'fulfilled') and closed_at is not null and closed_note is null)
    or (status = 'declined' and closed_at is not null and closed_note is not null)
  )
);

comment on table public.communication_email_setup_requests is
  'A contractor''s ask for Jafar to set up their business email. Status is only open, cancelled, declined or fulfilled; Setting up and Ready are read from communication_email_domains. Server-owned; writes via the communication_email_setup_request_* commands only.';

-- At most one live ask per organization.
create unique index communication_email_setup_requests_one_open_idx
  on public.communication_email_setup_requests (organization_id)
  where status = 'open';

create index communication_email_setup_requests_org_idx
  on public.communication_email_setup_requests (organization_id, created_at desc);

create index communication_email_setup_requests_requested_by_idx
  on public.communication_email_setup_requests (requested_by)
  where requested_by is not null;

alter table public.communication_email_setup_requests enable row level security;
revoke all on table public.communication_email_setup_requests from public, anon, authenticated;
grant select, insert, update on table public.communication_email_setup_requests to service_role;

-- Open asks that Jafar has not started on yet: no sending domain has been created since the ask.
create view public.communication_email_setup_requests_waiting
with (security_invoker = true) as
select r.*
from public.communication_email_setup_requests r
where r.status = 'open'
  and not exists (
    select 1
    from public.communication_email_domains d
    where d.organization_id = r.organization_id
      and d.purpose = 'sending'
      and d.created_at >= r.created_at
  );

revoke all on table public.communication_email_setup_requests_waiting from public, anon, authenticated;
grant select on table public.communication_email_setup_requests_waiting to service_role;

-- The contractor sends an ask. Refuses when a live ask is still waiting or the business already has a sending
-- domain. An old ask that Jafar already acted on (a domain was created after it) is closed as fulfilled first,
-- so it never blocks a new one after a domain is removed.
create function public.communication_email_setup_request_create(
  p_organization_id uuid,
  p_actor_id uuid,
  p_root_domain text,
  p_mailbox_provider text,
  p_note text
) returns public.communication_email_setup_requests
language plpgsql
set search_path to 'pg_catalog', 'public'
as $function$
declare
  live public.communication_email_setup_requests;
  created public.communication_email_setup_requests;
begin
  perform 1 from public.organizations where id = p_organization_id for update;
  if not found then
    raise exception 'The organization was not found.' using errcode = 'no_data_found';
  end if;

  if exists (
    select 1 from public.communication_email_domains
    where organization_id = p_organization_id and purpose = 'sending' and lifecycle_state <> 'removed'
  ) then
    raise exception 'This business already has a sending domain.' using errcode = 'P0409';
  end if;

  select * into live from public.communication_email_setup_requests
  where organization_id = p_organization_id and status = 'open';
  if found then
    if exists (
      select 1 from public.communication_email_domains
      where organization_id = p_organization_id and purpose = 'sending' and created_at >= live.created_at
    ) then
      update public.communication_email_setup_requests
      set status = 'fulfilled', closed_at = now(), updated_at = now()
      where id = live.id;
    else
      raise exception 'An email setup request is already waiting.' using errcode = 'P0409';
    end if;
  end if;

  insert into public.communication_email_setup_requests (
    organization_id, requested_by, root_domain, mailbox_provider, note
  ) values (
    p_organization_id, p_actor_id, p_root_domain, p_mailbox_provider, nullif(btrim(coalesce(p_note, '')), '')
  ) returning * into created;

  return created;
end;
$function$;

-- The contractor withdraws an ask, only while it still waits on Jafar. Once a sending domain exists the setup
-- is underway and a half-written DNS and SES provisioning must not be abandoned.
create function public.communication_email_setup_request_cancel(
  p_organization_id uuid,
  p_request_id uuid
) returns public.communication_email_setup_requests
language plpgsql
set search_path to 'pg_catalog', 'public'
as $function$
declare
  target public.communication_email_setup_requests;
begin
  select * into target from public.communication_email_setup_requests
  where id = p_request_id and organization_id = p_organization_id
  for update;
  if not found then
    raise exception 'The request was not found.' using errcode = 'no_data_found';
  end if;
  if target.status <> 'open' then
    raise exception 'This request is already closed.' using errcode = 'P0409';
  end if;
  if exists (
    select 1 from public.communication_email_domains
    where organization_id = p_organization_id and purpose = 'sending' and created_at >= target.created_at
  ) then
    raise exception 'Setup is already underway.' using errcode = 'P0409';
  end if;

  update public.communication_email_setup_requests
  set status = 'cancelled', closed_at = now(), updated_at = now()
  where id = target.id
  returning * into target;
  return target;
end;
$function$;

-- Jafar closes an ask with a note the contractor sees.
create function public.communication_email_setup_request_close(
  p_request_id uuid,
  p_note text
) returns public.communication_email_setup_requests
language plpgsql
set search_path to 'pg_catalog', 'public'
as $function$
declare
  target public.communication_email_setup_requests;
  clean_note text := nullif(btrim(coalesce(p_note, '')), '');
begin
  if clean_note is null then
    raise exception 'A note for the contractor is required.' using errcode = 'check_violation';
  end if;
  select * into target from public.communication_email_setup_requests
  where id = p_request_id
  for update;
  if not found then
    raise exception 'The request was not found.' using errcode = 'no_data_found';
  end if;
  if target.status <> 'open' then
    raise exception 'This request is already closed.' using errcode = 'P0409';
  end if;

  update public.communication_email_setup_requests
  set status = 'declined', closed_note = clean_note, closed_at = now(), updated_at = now()
  where id = target.id
  returning * into target;
  return target;
end;
$function$;

revoke all on function public.communication_email_setup_request_create(uuid, uuid, text, text, text) from public, anon, authenticated;
revoke all on function public.communication_email_setup_request_cancel(uuid, uuid) from public, anon, authenticated;
revoke all on function public.communication_email_setup_request_close(uuid, text) from public, anon, authenticated;
grant execute on function public.communication_email_setup_request_create(uuid, uuid, text, text, text) to service_role;
grant execute on function public.communication_email_setup_request_cancel(uuid, uuid) to service_role;
grant execute on function public.communication_email_setup_request_close(uuid, text) to service_role;
