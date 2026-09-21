-- Communications Website Chat WC1 completion: Platform Owner suspension, token rotation,
-- health, and immutable authority history. Public widget resolution already treats suspended_at
-- as a hard stop; this migration supplies the missing owner-only writers and audit trail.

create table public.communication_website_chat_authority_events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  widget_id uuid,
  event_kind text not null check (event_kind in (
    'suspension_engaged', 'suspension_released', 'public_token_rotated'
  )),
  reason text not null check (char_length(btrim(reason)) between 3 and 500),
  actor_owner_email text not null check (char_length(btrim(actor_owner_email)) between 3 and 320),
  before_state jsonb not null default '{}'::jsonb,
  after_state jsonb not null default '{}'::jsonb,
  idempotency_key uuid not null,
  created_at timestamptz not null default now(),
  constraint communication_website_chat_authority_events_widget_fk
    foreign key (organization_id, widget_id)
    references public.website_chat_widgets(organization_id, id),
  constraint communication_website_chat_authority_events_idempotency_key
    unique (organization_id, idempotency_key)
);

create index communication_website_chat_authority_events_org_history_idx
  on public.communication_website_chat_authority_events (organization_id, created_at desc, id desc);

create index communication_website_chat_authority_events_widget_history_idx
  on public.communication_website_chat_authority_events (widget_id, created_at desc, id desc)
  where widget_id is not null;

alter table public.communication_website_chat_authority_events enable row level security;
revoke all on public.communication_website_chat_authority_events from anon, authenticated;
grant select, insert on public.communication_website_chat_authority_events to service_role;

-- New widgets inherit the current organization-level abuse/security suspension. This closes the
-- bypass where a contractor could create a fresh widget while the existing widgets were suspended.
create or replace function private.inherit_website_chat_authority_suspension()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  latest_kind text;
begin
  select event_kind into latest_kind
  from public.communication_website_chat_authority_events
  where organization_id = new.organization_id
    and event_kind in ('suspension_engaged', 'suspension_released')
  order by created_at desc, id desc
  limit 1;

  if latest_kind = 'suspension_engaged' then
    new.suspended_at := coalesce(new.suspended_at, now());
  end if;
  return new;
end;
$$;

revoke all on function private.inherit_website_chat_authority_suspension() from public, anon, authenticated;

create trigger website_chat_widgets_inherit_authority_suspension
before insert on public.website_chat_widgets
for each row execute function private.inherit_website_chat_authority_suspension();

create or replace function public.set_organization_website_chat_suspension(
  p_organization_id uuid,
  p_engage boolean,
  p_reason text,
  p_actor_email text,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  clean_reason text := btrim(coalesce(p_reason, ''));
  actor text := lower(btrim(coalesce(p_actor_email, '')));
  existing_event public.communication_website_chat_authority_events%rowtype;
  latest_event public.communication_website_chat_authority_events%rowtype;
  inserted_event public.communication_website_chat_authority_events%rowtype;
  affected_widgets integer;
  active boolean;
begin
  if char_length(clean_reason) not between 3 and 500 then
    raise exception 'A reason of 3 to 500 characters is required.' using errcode = 'check_violation';
  end if;
  if char_length(actor) not between 3 and 320 then
    raise exception 'An owner email is required.' using errcode = 'check_violation';
  end if;
  if p_idempotency_key is null then
    raise exception 'An idempotency key is required.' using errcode = 'check_violation';
  end if;
  if not exists (select 1 from public.organizations where id = p_organization_id) then
    raise exception 'That organization does not exist.' using errcode = 'foreign_key_violation';
  end if;

  perform pg_advisory_xact_lock(hashtext('website-chat-authority:' || p_organization_id::text));

  select * into existing_event
  from public.communication_website_chat_authority_events
  where organization_id = p_organization_id and idempotency_key = p_idempotency_key;
  if found then
    return jsonb_build_object('applied', false, 'event_id', existing_event.id,
      'suspended', existing_event.event_kind = 'suspension_engaged');
  end if;

  select * into latest_event
  from public.communication_website_chat_authority_events
  where organization_id = p_organization_id
    and event_kind in ('suspension_engaged', 'suspension_released')
  order by created_at desc, id desc
  limit 1;
  active := found and latest_event.event_kind = 'suspension_engaged';

  if active = p_engage then
    return jsonb_build_object('applied', false, 'event_id', latest_event.id, 'suspended', active);
  end if;

  update public.website_chat_widgets
  set suspended_at = case when p_engage then coalesce(suspended_at, now()) else null end,
      revision = revision + 1,
      updated_at = now()
  where organization_id = p_organization_id
    and (suspended_at is null) = p_engage;
  get diagnostics affected_widgets = row_count;

  insert into public.communication_website_chat_authority_events (
    organization_id, event_kind, reason, actor_owner_email, before_state, after_state,
    idempotency_key
  ) values (
    p_organization_id,
    case when p_engage then 'suspension_engaged' else 'suspension_released' end,
    clean_reason, actor,
    jsonb_build_object('suspended', active),
    jsonb_build_object('suspended', p_engage, 'affected_widgets', affected_widgets),
    p_idempotency_key
  ) returning * into inserted_event;

  insert into public.platform_owner_audit_events (
    actor_owner_email, event_type, target_type, target_key, before_state, after_state
  ) values (
    actor,
    case when p_engage then 'communications.website_chat_suspension_engaged'
      else 'communications.website_chat_suspension_released' end,
    'organization', p_organization_id::text,
    jsonb_build_object('suspended', active),
    jsonb_build_object('suspended', p_engage, 'reason', clean_reason,
      'authority_event_id', inserted_event.id, 'affected_widgets', affected_widgets)
  );

  return jsonb_build_object('applied', true, 'event_id', inserted_event.id,
    'suspended', p_engage, 'affected_widgets', affected_widgets);
end;
$$;

revoke all on function public.set_organization_website_chat_suspension(uuid, boolean, text, text, uuid)
  from public, anon, authenticated;
grant execute on function public.set_organization_website_chat_suspension(uuid, boolean, text, text, uuid)
  to service_role;

create or replace function public.rotate_website_chat_widget_public_token(
  p_organization_id uuid,
  p_widget_id uuid,
  p_expected_revision integer,
  p_reason text,
  p_actor_email text,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  clean_reason text := btrim(coalesce(p_reason, ''));
  actor text := lower(btrim(coalesce(p_actor_email, '')));
  widget public.website_chat_widgets%rowtype;
  existing_event public.communication_website_chat_authority_events%rowtype;
  inserted_event public.communication_website_chat_authority_events%rowtype;
  next_token uuid := gen_random_uuid();
begin
  if char_length(clean_reason) not between 3 and 500 then
    raise exception 'A reason of 3 to 500 characters is required.' using errcode = 'check_violation';
  end if;
  if char_length(actor) not between 3 and 320 then
    raise exception 'An owner email is required.' using errcode = 'check_violation';
  end if;
  if p_idempotency_key is null then
    raise exception 'An idempotency key is required.' using errcode = 'check_violation';
  end if;

  perform pg_advisory_xact_lock(hashtext('website-chat-widget-authority:' || p_widget_id::text));
  select * into existing_event
  from public.communication_website_chat_authority_events
  where organization_id = p_organization_id and idempotency_key = p_idempotency_key;
  if found then
    return existing_event.after_state || jsonb_build_object('applied', false, 'event_id', existing_event.id);
  end if;

  select * into widget
  from public.website_chat_widgets
  where organization_id = p_organization_id and id = p_widget_id
  for update;
  if not found then
    raise exception 'That widget was not found.' using errcode = 'foreign_key_violation';
  end if;
  if p_expected_revision is distinct from widget.revision then
    raise exception 'The widget changed while you were reviewing it. Reload and try again.'
      using errcode = 'serialization_failure';
  end if;

  update public.website_chat_widgets
  set public_token = next_token, revision = revision + 1, updated_at = now()
  where id = widget.id
  returning * into widget;

  insert into public.communication_website_chat_authority_events (
    organization_id, widget_id, event_kind, reason, actor_owner_email,
    before_state, after_state, idempotency_key
  ) values (
    p_organization_id, p_widget_id, 'public_token_rotated', clean_reason, actor,
    jsonb_build_object('revision', p_expected_revision),
    jsonb_build_object('widget_id', p_widget_id, 'revision', widget.revision,
      'public_token', widget.public_token),
    p_idempotency_key
  ) returning * into inserted_event;

  insert into public.platform_owner_audit_events (
    actor_owner_email, event_type, target_type, target_key, before_state, after_state
  ) values (
    actor, 'communications.website_chat_public_token_rotated', 'website_chat_widget', p_widget_id::text,
    jsonb_build_object('revision', p_expected_revision),
    jsonb_build_object('revision', widget.revision, 'reason', clean_reason,
      'authority_event_id', inserted_event.id)
  );

  return inserted_event.after_state || jsonb_build_object('applied', true, 'event_id', inserted_event.id);
end;
$$;

revoke all on function public.rotate_website_chat_widget_public_token(uuid, uuid, integer, text, text, uuid)
  from public, anon, authenticated;
grant execute on function public.rotate_website_chat_widget_public_token(uuid, uuid, integer, text, text, uuid)
  to service_role;

create or replace function public.get_organization_website_chat_authority(
  p_organization_id uuid
)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  with latest_suspension as (
    select e.*
    from public.communication_website_chat_authority_events e
    where e.organization_id = p_organization_id
      and e.event_kind in ('suspension_engaged', 'suspension_released')
    order by e.created_at desc, e.id desc
    limit 1
  ), widget_total as (
    select count(*)::integer as value
    from public.website_chat_widgets
    where organization_id = p_organization_id
  ), selected_widgets as (
    select w.*
    from public.website_chat_widgets w
    where w.organization_id = p_organization_id
    order by w.updated_at desc, w.id desc
    limit 100
  ), origin_counts as (
    select origin.widget_id, count(*)::integer as value
    from public.website_chat_widget_origins origin
    join selected_widgets selected on selected.id = origin.widget_id
    group by origin.widget_id
  )
  select jsonb_build_object(
    'suspension', (
      select case when event_kind = 'suspension_engaged' then jsonb_build_object(
        'event_id', id, 'reason', reason, 'engaged_by', actor_owner_email, 'engaged_at', created_at
      ) else null end
      from latest_suspension
    ),
    'widget_total_count', (select value from widget_total),
    'widgets_truncated', (select value > 100 from widget_total),
    'widgets', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', w.id, 'name', w.name, 'published', w.published,
        'disabled_at', w.disabled_at, 'suspended_at', w.suspended_at,
        'revision', w.revision, 'public_token', w.public_token,
        'allowed_origin_count', coalesce(origins.value, 0),
        'updated_at', w.updated_at
      ) order by w.updated_at desc, w.id desc)
      from selected_widgets w
      left join origin_counts origins on origins.widget_id = w.id
    ), '[]'::jsonb),
    'recent_events', coalesce((
      select jsonb_agg(to_jsonb(history) order by history.created_at desc, history.id desc)
      from (
        select id, widget_id, event_kind, reason, actor_owner_email, created_at
        from public.communication_website_chat_authority_events
        where organization_id = p_organization_id
        order by created_at desc, id desc
        limit 20
      ) history
    ), '[]'::jsonb)
  );
$$;

revoke all on function public.get_organization_website_chat_authority(uuid)
  from public, anon, authenticated;
grant execute on function public.get_organization_website_chat_authority(uuid) to service_role;
