-- Client onboarding E5: launch checks (plan §6).
--
-- Product truth: docs/client-onboarding-delivery-behavior-contract.md §6. Jafar's choices of 2026-10-05: each
-- released preview version has its own launch checklist, one line per check the client's package needs. Jafar ticks
-- each line by hand or marks it Doesn't apply with a reason. A line that depends on an outside wait still open shows
-- Waiting on that provider and cannot be ticked. Ask for launch approval stays locked until every line is ticked,
-- doesn't apply, or is waiting on a provider; open waits never block it. When Jafar asks, the list is kept with the
-- request, and that version's list no longer changes. The approver sees the kept list. Industry reference: milestone
-- gating in Rocketlane and GuideCX, and agencies' go-live QA checklists with a "doesn't apply" option.
--
-- 1. The lines a client's package needs, and the outside waits each depends on.
-- 2. organization_setup_launch_checks keeps Jafar's tick or Doesn't apply per version and line.
-- 3. The checklist as it stands, and Jafar's command to tick, mark or clear a line.
-- 4. public.owner_request_setup_launch_approval refuses until the list is done and keeps it on the request;
--    public.resolve_setup_launch_link returns it to the approver's link page.

-- 1. The lines ---------------------------------------------------------------------------------------------------

-- Mirrors LAUNCH_CHECKS in src/lib/setup/launch-checks.ts. A line with a service shows only when the client's
-- current package includes it; `wait_keys` are the outside waits (E2) the line cannot be tested before.
create function private.setup_launch_check_lines(target_organization_id uuid)
returns table (check_key text, wait_keys text[], line_order integer)
language sql
stable
security definer
set search_path = ''
as $$
  with current_package as (
    select array(
      select service ->> 'service_key'
      from jsonb_array_elements(edition.included_services) as service
      where service ->> 'service_key' is not null
    ) as service_keys
    from public.organization_package_agreements as agreement
    join public.package_editions as edition on edition.id = agreement.edition_id
    where agreement.organization_id = target_organization_id
      and agreement.cancelled_at is null
      and agreement.effective_from <= now()
    order by agreement.effective_from desc, agreement.created_at desc
    limit 1
  )
  select line.check_key, line.wait_keys, line.line_order
  from (values
    (1, 'web_address', 'website', array['website_address']),
    (2, 'phone_look', 'website', array[]::text[]),
    (3, 'form_leads', 'website', array[]::text[]),
    (4, 'email_delivery', null, array[]::text[]),
    (5, 'calls_texts', 'calls_texting', array['texting_approval', 'number_transfer']),
    (6, 'stop_help', 'calls_texting', array['texting_approval']),
    (7, 'imports', null, array[]::text[]),
    (8, 'account_ownership', null, array[]::text[]),
    (9, 'everything_else', null, array[]::text[])
  ) as line(line_order, check_key, service_key, wait_keys)
  left join current_package on true
  where line.service_key is null or line.service_key = any (coalesce(current_package.service_keys, '{}'::text[]))
  order by line.line_order;
$$;

revoke all on function private.setup_launch_check_lines(uuid) from public;

-- 2. Jafar's ticks ------------------------------------------------------------------------------------------------

create table public.organization_setup_launch_checks (
  organization_id uuid not null,
  version integer not null,
  -- Mirrors LAUNCH_CHECKS in src/lib/setup/launch-checks.ts.
  check_key text not null check (
    check_key in (
      'web_address', 'phone_look', 'form_leads', 'email_delivery', 'calls_texts', 'stop_help', 'imports',
      'account_ownership', 'everything_else'
    )
  ),
  outcome text not null check (outcome in ('checked', 'not_applicable')),
  -- Why the line doesn't apply; the approver reads it.
  reason text check (reason is null or char_length(reason) between 1 and 300),
  checked_at timestamptz not null default now(),
  checked_by_email text not null check (char_length(checked_by_email) between 3 and 320),
  primary key (organization_id, version, check_key),
  foreign key (organization_id, version)
    references public.organization_setup_previews (organization_id, version) on delete cascade,
  constraint organization_setup_launch_checks_not_applicable_check check ((outcome = 'not_applicable') = (reason is not null))
);

comment on table public.organization_setup_launch_checks is
  'Client onboarding E5: Jafar''s launch checks, per released preview version and line. Only the service role reads it; rows change only through public.owner_set_setup_launch_check, and every change is in platform_owner_audit_events. The approver sees the list kept on the launch approval request.';

alter table public.organization_setup_launch_checks enable row level security;
revoke all on table public.organization_setup_launch_checks from public, anon, authenticated;
grant all on table public.organization_setup_launch_checks to service_role;

-- What Uplift checked, kept with the request when Jafar asks.
alter table public.organization_setup_launch_approvals add column launch_checks jsonb;

grant select (launch_checks) on table public.organization_setup_launch_approvals to authenticated;

-- 3. The checklist and Jafar's command ------------------------------------------------------------------------------

-- Each line for this version: its state — checked, not_applicable, waiting (a wait it depends on is still open,
-- whatever was ticked) or unchecked — and the open waits it is on. `waits` lists every open wait.
create function private.setup_launch_checklist(target_organization_id uuid, target_version integer)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  with open_waits as (
    select wait.wait_key, wait.status
    from public.organization_setup_provider_waits as wait
    where wait.organization_id = target_organization_id
      and wait.status not in ('approved', 'unavailable')
  )
  select jsonb_build_object(
    'lines', coalesce((
      select jsonb_agg(jsonb_build_object(
        'key', line.check_key,
        'state', case
          when cardinality(waiting.wait_keys) > 0 then 'waiting'
          when tick.outcome is not null then tick.outcome
          else 'unchecked'
        end,
        'reason', tick.reason,
        'checked_at', tick.checked_at,
        'checked_by_email', tick.checked_by_email,
        'waiting_on', to_jsonb(waiting.wait_keys)
      ) order by line.line_order)
      from private.setup_launch_check_lines(target_organization_id) as line
      left join public.organization_setup_launch_checks as tick
        on tick.organization_id = target_organization_id
       and tick.version = target_version
       and tick.check_key = line.check_key
      cross join lateral (
        select array(
          select open_waits.wait_key from open_waits
          where open_waits.wait_key = any (line.wait_keys)
          order by array_position(line.wait_keys, open_waits.wait_key)
        ) as wait_keys
      ) as waiting
    ), '[]'::jsonb),
    'waits', coalesce((
      select jsonb_agg(jsonb_build_object('key', open_waits.wait_key, 'status', open_waits.status)
        order by array_position(
          array['google_profile', 'texting_approval', 'number_transfer', 'website_address'], open_waits.wait_key
        ))
      from open_waits
    ), '[]'::jsonb)
  );
$$;

revoke all on function private.setup_launch_checklist(uuid, integer) from public;

-- Jafar's view: the newest released version's checklist, and whether a request has been made on it (then the
-- list no longer changes). Null before any release.
create function public.owner_setup_launch_checklist(target_organization_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  newest integer;
begin
  select max(preview.version) into newest
  from public.organization_setup_previews as preview
  where preview.organization_id = target_organization_id and preview.released_at is not null;
  if newest is null then
    return null;
  end if;
  return private.setup_launch_checklist(target_organization_id, newest) || jsonb_build_object(
    'version', newest,
    'asked', exists (
      select 1 from public.organization_setup_launch_approvals as request
      where request.organization_id = target_organization_id and request.version = newest
    )
  );
end;
$$;

revoke all on function public.owner_setup_launch_checklist(uuid) from public, anon, authenticated;
grant execute on function public.owner_setup_launch_checklist(uuid) to service_role;

-- Ticks a line ('checked'), marks it Doesn't apply with a reason ('not_applicable'), or clears it (null). Only on
-- the newest version, before anyone asked for approval on it, and never ticked while a wait it depends on is open.
-- Saving what is already there returns 'unchanged'.
create function public.owner_set_setup_launch_check(
  target_organization_id uuid,
  target_version integer,
  target_check_key text,
  new_outcome text,
  new_reason text,
  actor_email text
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  clean_email text := nullif(btrim(coalesce(actor_email, '')), '');
  clean_reason text := nullif(btrim(coalesce(new_reason, '')), '');
  line record;
  before_row public.organization_setup_launch_checks;
  after_row public.organization_setup_launch_checks;
begin
  if target_organization_id is null or target_version is null or clean_email is null then
    raise exception 'Say which client and who is changing it.' using errcode = 'check_violation';
  end if;
  if new_outcome is not null and new_outcome not in ('checked', 'not_applicable') then
    raise exception 'That is not a launch check outcome.' using errcode = 'check_violation';
  end if;
  if new_outcome = 'not_applicable' and clean_reason is null then
    raise exception 'Say why this check doesn''t apply.' using errcode = 'check_violation';
  end if;
  if clean_reason is not null and char_length(clean_reason) > 300 then
    raise exception 'Keep the reason to 300 characters.' using errcode = 'check_violation';
  end if;
  if new_outcome is distinct from 'not_applicable' then
    clean_reason := null;
  end if;

  -- The same lock Ask takes, so a tick and an Ask never cross.
  perform 1 from public.organization_setup where organization_id = target_organization_id for update;

  if not exists (
    select 1 from public.organization_setup_previews
    where organization_id = target_organization_id and version = target_version and released_at is not null
  ) then
    raise exception 'That preview could not be found.' using errcode = 'check_violation';
  end if;
  if exists (
    select 1 from public.organization_setup_previews
    where organization_id = target_organization_id and version > target_version
  ) then
    raise exception 'Check the newest preview.' using errcode = 'check_violation';
  end if;
  if exists (
    select 1 from public.organization_setup_launch_approvals
    where organization_id = target_organization_id and version = target_version
  ) then
    raise exception 'Launch approval was already asked for on this version. Release a new version to check again.'
      using errcode = 'check_violation';
  end if;

  select * into line from private.setup_launch_check_lines(target_organization_id) as lines
  where lines.check_key = target_check_key;
  if not found then
    raise exception 'This client''s package does not need that check.' using errcode = 'check_violation';
  end if;
  if new_outcome = 'checked' and exists (
    select 1 from public.organization_setup_provider_waits as wait
    where wait.organization_id = target_organization_id
      and wait.wait_key = any (line.wait_keys)
      and wait.status not in ('approved', 'unavailable')
  ) then
    raise exception 'This check waits on an outside step that is still open.' using errcode = 'check_violation';
  end if;

  select * into before_row from public.organization_setup_launch_checks
  where organization_id = target_organization_id and version = target_version and check_key = target_check_key
  for update;

  if new_outcome is null then
    if before_row.organization_id is null then
      return jsonb_build_object('status', 'unchanged');
    end if;
    delete from public.organization_setup_launch_checks
    where organization_id = target_organization_id and version = target_version and check_key = target_check_key;
  else
    if before_row.outcome = new_outcome and before_row.reason is not distinct from clean_reason then
      return jsonb_build_object('status', 'unchanged');
    end if;
    insert into public.organization_setup_launch_checks (
      organization_id, version, check_key, outcome, reason, checked_by_email
    ) values (
      target_organization_id, target_version, target_check_key, new_outcome, clean_reason, clean_email
    )
    on conflict (organization_id, version, check_key) do update
      set outcome = excluded.outcome,
          reason = excluded.reason,
          checked_at = now(),
          checked_by_email = excluded.checked_by_email
    returning * into after_row;
  end if;

  insert into public.platform_owner_audit_events (
    actor_owner_email, event_type, target_type, target_key, before_state, after_state
  ) values (
    clean_email,
    'organization.setup_launch_check',
    'organization',
    target_organization_id::text,
    case when before_row.organization_id is not null then
      jsonb_build_object(
        'version', target_version, 'check', target_check_key, 'outcome', before_row.outcome,
        'reason', before_row.reason
      )
    end,
    jsonb_build_object(
      'version', target_version, 'check', target_check_key, 'outcome', after_row.outcome, 'reason', after_row.reason
    )
  );

  return jsonb_build_object('status', 'saved');
end;
$$;

revoke all on function public.owner_set_setup_launch_check(uuid, integer, text, text, text, text)
  from public, anon, authenticated;
grant execute on function public.owner_set_setup_launch_check(uuid, integer, text, text, text, text) to service_role;

-- 4. Ask waits for the checklist ---------------------------------------------------------------------------------
-- Unchanged from 20261102090000_setup_launch_approvals.sql except: an unchecked line refuses the request, and the
-- checklist without Jafar's email is kept on it.

create or replace function public.owner_request_setup_launch_approval(
  target_organization_id uuid,
  target_version integer,
  new_token_hash bytea,
  actor_email text
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  clean_email text := nullif(btrim(coalesce(actor_email, '')), '');
  preview public.organization_setup_previews;
  existing public.organization_setup_launch_approvals;
  approver record;
  checklist jsonb;
  created public.organization_setup_launch_approvals;
begin
  if target_organization_id is null or target_version is null or new_token_hash is null or clean_email is null then
    raise exception 'Say which client and who is asking.' using errcode = 'check_violation';
  end if;

  perform 1 from public.organization_setup where organization_id = target_organization_id for update;

  select * into existing from public.organization_setup_launch_approvals
  where organization_id = target_organization_id
    and (status = 'open' or (status = 'approved' and replaced_at is null));
  if existing.id is not null then
    if existing.version = target_version then
      return jsonb_build_object(
        'status', case when existing.status = 'approved' then 'already_approved' else 'already_requested' end,
        'request_id', existing.id
      );
    end if;
    raise exception 'A request for another version is still open.' using errcode = 'check_violation';
  end if;

  select * into preview from public.organization_setup_previews
  where organization_id = target_organization_id and version = target_version and released_at is not null;
  if preview.organization_id is null then
    raise exception 'That preview could not be found.' using errcode = 'check_violation';
  end if;
  if exists (
    select 1 from public.organization_setup_previews as newer
    where newer.organization_id = target_organization_id and newer.version > target_version
  ) then
    raise exception 'Ask on the newest preview.' using errcode = 'check_violation';
  end if;
  if preview.notes_sent_at is not null then
    raise exception 'The client sent corrections on this preview. Release a new version first.'
      using errcode = 'check_violation';
  end if;

  checklist := private.setup_launch_checklist(target_organization_id, target_version);
  if exists (
    select 1 from jsonb_array_elements(checklist -> 'lines') as line where line ->> 'state' = 'unchecked'
  ) then
    raise exception 'Finish the launch checks first.' using errcode = 'check_violation';
  end if;

  select * into approver from private.setup_launch_approver(target_organization_id);
  if approver.approver_email is null then
    raise exception 'The client''s setup names no final approver email.' using errcode = 'check_violation';
  end if;

  insert into public.organization_setup_launch_approvals (
    organization_id, version, requested_by_email, approver_name, approver_email, token_hash, link_expires_at,
    launch_checks
  ) values (
    target_organization_id, target_version, clean_email, approver.approver_name, approver.approver_email,
    new_token_hash, now() + interval '30 days',
    jsonb_build_object(
      'lines', (
        select coalesce(jsonb_agg(line - 'checked_by_email' order by position), '[]'::jsonb)
        from jsonb_array_elements(checklist -> 'lines') with ordinality as item(line, position)
      ),
      'waits', checklist -> 'waits'
    )
  )
  returning * into created;

  insert into public.platform_owner_audit_events (
    actor_owner_email, event_type, target_type, target_key, before_state, after_state
  ) values (
    clean_email,
    'organization.setup_launch_approval_requested',
    'organization',
    target_organization_id::text,
    null,
    jsonb_build_object('request_id', created.id, 'version', target_version, 'approver_email', created.approver_email)
  );

  return jsonb_build_object(
    'status', 'requested',
    'request_id', created.id,
    'approver_name', created.approver_name,
    'approver_email', created.approver_email,
    'link_expires_at', created.link_expires_at
  );
end;
$$;

-- Unchanged from 20261102090000_setup_launch_approvals.sql except: the kept checklist is returned.
create or replace function public.resolve_setup_launch_link(supplied_token_hash bytea)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  request public.organization_setup_launch_approvals;
  preview public.organization_setup_previews;
  business_name text;
begin
  request := private.setup_launch_link_request(supplied_token_hash, false);
  if request.id is null then
    return null;
  end if;
  select * into preview from public.organization_setup_previews
  where organization_id = request.organization_id and version = request.version;
  select name into business_name from public.organizations where id = request.organization_id;

  return jsonb_build_object(
    'business_name', business_name,
    'version', request.version,
    'approver_name', request.approver_name,
    'status', request.status,
    'wording', private.setup_launch_approval_wording(request.version),
    'approved_at', request.approved_at,
    'not_yet_at', request.not_yet_at,
    'requested_at', request.requested_at,
    'launch_checks', request.launch_checks,
    'cards', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', card ->> 'id',
        'title', card ->> 'title',
        'summary', card ->> 'summary',
        'link', card -> 'link'
      ) order by position)
      from jsonb_array_elements(preview.cards) with ordinality as item(card, position)
    ), '[]'::jsonb)
  );
end;
$$;
