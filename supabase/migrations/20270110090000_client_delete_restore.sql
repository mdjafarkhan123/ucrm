-- Data privacy Part 6: delete a customer to Recently Deleted, restore them, and hand over to the permanent
-- delete on day 30. Plan: docs/data-privacy-deletion-behavior-contract.md § Deleting a customer. Design:
-- docs/data-privacy-client-delete-restore.md (Salesforce Recycle Bin: the parent and the children deleted with it
-- carry a mark, ordinary reads never return marked rows, restore clears the marks together).
--
--   1. client_deleted_at marks on the customer's work, contact values and conversations
--   2. public.client_deletions -- one row per delete: who, when, counts, day 30, restore or purge outcome
--   3. member reads hide marked rows (SELECT policies); writes to marked work are refused (guard trigger)
--   4. a deleted customer's phone or email can belong to a new contact (partial unique index)
--   5. outgoing email skips a deleted customer at claim time (SMS already does); marketing treats them as inactive
--   6. public.client_delete_preview / delete_clients / restore_client_deletions / recently_deleted_clients
--   7. after the permanent delete, kept shells lose the mark so money reports read them as before

-- 1. Marks ------------------------------------------------------------------------------------------------

alter table public.client_contact_methods add column client_deleted_at timestamptz;
alter table public.properties add column client_deleted_at timestamptz;
alter table public.requests add column client_deleted_at timestamptz;
alter table public.assessments add column client_deleted_at timestamptz;
alter table public.quotes add column client_deleted_at timestamptz;
alter table public.jobs add column client_deleted_at timestamptz;
alter table public.job_visits add column client_deleted_at timestamptz;
alter table public.invoices add column client_deleted_at timestamptz;
alter table public.opportunities add column client_deleted_at timestamptz;
alter table public.review_requests add column client_deleted_at timestamptz;
alter table public.communication_delivery_intents add column client_deleted_at timestamptz;
alter table public.communication_inbound_messages add column client_deleted_at timestamptz;
alter table public.website_chat_sessions add column client_deleted_at timestamptz;
alter table public.website_chat_messages add column client_deleted_at timestamptz;

comment on column public.jobs.client_deleted_at is
  'Set while the customer is in Recently Deleted (Part 6); every member read hides the row. Cleared on restore.';

-- 2. Delete records ---------------------------------------------------------------------------------------

create table public.client_deletions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  client_id uuid not null,
  deleted_at timestamptz not null default now(),
  deleted_by uuid references auth.users (id) on delete set null,
  purge_after timestamptz not null,
  counts jsonb not null default '{}'::jsonb,
  kept jsonb not null default '{}'::jsonb,
  restored_at timestamptz,
  restored_by uuid references auth.users (id) on delete set null,
  purged_at timestamptz,
  receipt_id uuid,
  purge_attempted_at timestamptz,
  purge_failure text,
  purge_failed_since timestamptz,
  constraint client_deletions_client_fkey
    foreign key (organization_id, client_id) references public.clients (organization_id, id) on delete cascade,
  constraint client_deletions_one_outcome check (restored_at is null or purged_at is null)
);

comment on table public.client_deletions is
  'One row per customer delete (Part 6). Open while restored_at and purged_at are null; the day-30 job purges '
  'rows whose purge_after has passed. Counts are taken at delete time so Recently Deleted never recounts.';

create unique index client_deletions_one_open_idx on public.client_deletions (client_id)
  where restored_at is null and purged_at is null;
create index client_deletions_open_org_idx on public.client_deletions (organization_id, purge_after)
  where restored_at is null and purged_at is null;
create index client_deletions_due_idx on public.client_deletions (purge_after)
  where restored_at is null and purged_at is null;

alter table public.client_deletions enable row level security;
revoke all on table public.client_deletions from anon, authenticated;
grant all on table public.client_deletions to service_role;

-- 3. Hiding and the write guard ---------------------------------------------------------------------------

create or replace function private.client_lifecycle_in_progress()
  returns boolean
  language sql stable
  set search_path to 'pg_catalog', 'public'
  as $$
  select coalesce(current_setting('app.client_lifecycle_in_progress', true), '') = 'true'
    or private.client_purge_in_progress();
$$;

-- New or changed work for a customer in Recently Deleted is refused, whoever asks (a direct API call, a
-- booking, an import, an automation). Delete, restore and the permanent delete step aside.
create or replace function private.refuse_work_for_deleted_client()
  returns trigger
  language plpgsql
  security definer
  set search_path to 'pg_catalog', 'public'
  as $$
declare
  deleted boolean := false;
begin
  if private.client_lifecycle_in_progress() then
    return new;
  end if;

  if tg_op = 'UPDATE' and old.client_deleted_at is not null then
    deleted := true;
  elsif tg_op = 'INSERT' or new.client_deleted_at is not null then
    if tg_table_name = 'assessments' then
      select request.client_deleted_at is not null into deleted
      from public.requests as request
      where request.organization_id = new.organization_id and request.id = new.request_id;
    elsif tg_table_name = 'job_visits' then
      select job.client_deleted_at is not null into deleted
      from public.jobs as job
      where job.organization_id = new.organization_id and job.id = new.job_id;
    else
      select client.deleted_at is not null into deleted
      from public.clients as client
      where client.organization_id = new.organization_id and client.id = new.client_id;
    end if;
  end if;

  if coalesce(deleted, false) then
    raise exception 'This client is in Recently Deleted. Restore them first.'
      using errcode = '55000';
  end if;
  return new;
end;
$$;

revoke all on function private.refuse_work_for_deleted_client() from public, anon, authenticated;

create trigger refuse_work_for_deleted_client before insert or update on public.client_contact_methods
  for each row execute function private.refuse_work_for_deleted_client();
create trigger refuse_work_for_deleted_client before insert or update on public.properties
  for each row execute function private.refuse_work_for_deleted_client();
create trigger refuse_work_for_deleted_client before insert or update on public.requests
  for each row execute function private.refuse_work_for_deleted_client();
create trigger refuse_work_for_deleted_client before insert or update on public.assessments
  for each row execute function private.refuse_work_for_deleted_client();
create trigger refuse_work_for_deleted_client before insert or update on public.quotes
  for each row execute function private.refuse_work_for_deleted_client();
create trigger refuse_work_for_deleted_client before insert or update on public.jobs
  for each row execute function private.refuse_work_for_deleted_client();
create trigger refuse_work_for_deleted_client before insert or update on public.job_visits
  for each row execute function private.refuse_work_for_deleted_client();
create trigger refuse_work_for_deleted_client before insert or update on public.opportunities
  for each row execute function private.refuse_work_for_deleted_client();
create trigger refuse_work_for_deleted_client before insert or update on public.review_requests
  for each row execute function private.refuse_work_for_deleted_client();
-- Invoices: only drafts are marked; an issued invoice stays a live money record (§ Money records), so a new
-- invoice for a deleted customer is refused but a kept one can still take a Stripe or refund update.
create trigger refuse_work_for_deleted_client before insert or update on public.invoices
  for each row execute function private.refuse_work_for_deleted_client();

-- 4. A deleted customer's phone or email can belong to a new contact ---------------------------------------

drop index public.client_contact_methods_org_value_unique_idx;
create unique index client_contact_methods_org_value_unique_idx
  on public.client_contact_methods (organization_id, kind, normalized_value)
  where client_deleted_at is null;

-- 5. Marketing: a deleted customer is inactive, like an archived one ----------------------------------------

create or replace function private.marketing_recipient_blocked_reason(p_organization_id uuid, p_client_id uuid, p_client_contact_method_id uuid, p_recipient_email text)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
    select
        case
            when client.archived_at is not null or client.deleted_at is not null then 'inactive_customer'
            when method.id is null
                or method.kind <> 'email'
                or method.client_id <> p_client_id
                or method.normalized_value <> p_recipient_email then 'missing_email'
            when consent.state = 'opted_out' and event.source = 'complaint' then 'complaint'
            when consent.state = 'opted_out' then 'unsubscribed'
            when suppression.reason = 'complaint' then 'complaint'
            when suppression.reason = 'hard_bounce' then 'hard_bounce'
            when preference.contact_policy = 'do_not_disturb' then 'do_not_disturb'
            when preference.contact_policy = 'no_marketing' then 'no_marketing'
            when consent.state is distinct from 'opted_in' then 'no_consent'
            else null
        end
    from public.clients client
    left join public.client_contact_methods method
        on method.organization_id = p_organization_id and method.id = p_client_contact_method_id
    left join public.client_marketing_consent_state consent
        on consent.organization_id = p_organization_id
        and consent.client_contact_method_id = p_client_contact_method_id
    left join public.client_marketing_consent_events event
        on event.organization_id = consent.organization_id and event.id = consent.source_event_id
    left join public.client_communication_preferences preference
        on preference.organization_id = p_organization_id and preference.client_id = p_client_id
    left join lateral (
        select active.reason
        from public.communication_email_suppressions active
        where active.organization_id = p_organization_id
            and active.recipient_email = p_recipient_email
            and active.released_at is null
        order by case active.reason when 'complaint' then 0 else 1 end
        limit 1
    ) suppression on true
    where client.organization_id = p_organization_id and client.id = p_client_id;
$function$;

-- 6. Commands ---------------------------------------------------------------------------------------------

-- Marks (or, with null, unmarks) everything that goes with one customer. Called inside delete and restore.
create or replace function private.set_client_deleted_mark(org uuid, c uuid, mark timestamptz)
  returns void
  language plpgsql
  security definer
  set search_path to 'pg_catalog', 'public'
  as $$
begin
  perform set_config('app.client_lifecycle_in_progress', 'true', true);

  -- On restore a phone or email a newer client now holds stays hidden on this one (one business never holds the
  -- same value twice); the row is kept because its messages and consent history point at it.
  update public.client_contact_methods as mine set client_deleted_at = mark
  where mine.organization_id = org and mine.client_id = c
    and (mark is not null or not exists (
      select 1 from public.client_contact_methods as theirs
      where theirs.organization_id = org and theirs.kind = mine.kind
        and theirs.normalized_value = mine.normalized_value and theirs.client_deleted_at is null));
  update public.properties set client_deleted_at = mark where organization_id = org and client_id = c;
  update public.assessments as assessment set client_deleted_at = mark
  from public.requests as request
  where request.organization_id = org and request.client_id = c
    and assessment.organization_id = org and assessment.request_id = request.id;
  update public.requests set client_deleted_at = mark where organization_id = org and client_id = c;
  update public.job_visits as visit set client_deleted_at = mark
  from public.jobs as job
  where job.organization_id = org and job.client_id = c
    and visit.organization_id = org and visit.job_id = job.id;
  update public.jobs set client_deleted_at = mark where organization_id = org and client_id = c;
  update public.quotes set client_deleted_at = mark where organization_id = org and client_id = c;
  -- Only drafts go with the customer; issued invoices stay in Invoices and reports.
  update public.invoices set client_deleted_at = mark
  where organization_id = org and client_id = c and issued_at is null and recognized_at is null;
  update public.opportunities set client_deleted_at = mark where organization_id = org and client_id = c;
  update public.review_requests set client_deleted_at = mark where organization_id = org and client_id = c;
  update public.communication_delivery_intents set client_deleted_at = mark
  where organization_id = org and client_id = c;
  update public.communication_inbound_messages set client_deleted_at = mark
  where organization_id = org and client_id = c;
  update public.website_chat_sessions set client_deleted_at = mark where organization_id = org and client_id = c;
  update public.website_chat_messages set client_deleted_at = mark where organization_id = org and client_id = c;
  update public.clients set deleted_at = mark where organization_id = org and id = c;

  perform set_config('app.client_lifecycle_in_progress', 'false', true);
end;
$$;

revoke all on function private.set_client_deleted_mark(uuid, uuid, timestamptz) from public, anon, authenticated;

-- Loads and locks the callers' clients, in id order so two bulk deletes cannot deadlock.
create or replace function private.lock_clients_for_delete(target_client_ids uuid[], permission text)
  returns setof public.clients
  language plpgsql
  security definer
  set search_path to 'pg_catalog', 'public'
  as $$
declare
  caller uuid := (select auth.uid());
  org uuid := (select private.current_organization());
begin
  if caller is null or org is null
     or not private.member_has_permission(org, caller, permission) then
    raise exception 'You do not have access to delete clients.' using errcode = 'insufficient_privilege';
  end if;
  if coalesce(cardinality(target_client_ids), 0) = 0 or cardinality(target_client_ids) > 100 then
    raise exception 'Choose between 1 and 100 clients.' using errcode = '22023';
  end if;

  return query
  select client.* from public.clients as client
  where client.organization_id = org and client.id = any(target_client_ids)
    and client.deleted_at is null and client.purged_at is null
    and private.can_view_client(org, client.id)
  order by client.id
  for update;
end;
$$;

revoke all on function private.lock_clients_for_delete(uuid[], text) from public, anon, authenticated;

-- What the Delete client pop-up shows: per client the counts, what stays and anything that stops the delete;
-- for many clients also the totals of those that can go.
create or replace function public.client_delete_preview(target_client_ids uuid[])
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'pg_catalog', 'public'
  as $$
declare
  caller uuid := (select auth.uid());
  org uuid := (select private.current_organization());
  client_row public.clients;
  plan jsonb;
  clients jsonb := '[]'::jsonb;
  totals jsonb := '{}'::jsonb;
  kept_totals jsonb := '{}'::jsonb;
  kv record;
begin
  if caller is null or org is null
     or not private.member_has_permission(org, caller, 'customers.delete') then
    raise exception 'You do not have access to delete clients.' using errcode = 'insufficient_privilege';
  end if;
  if coalesce(cardinality(target_client_ids), 0) = 0 or cardinality(target_client_ids) > 100 then
    raise exception 'Choose between 1 and 100 clients.' using errcode = '22023';
  end if;

  for client_row in
    select client.* from public.clients as client
    where client.organization_id = org and client.id = any(target_client_ids)
      and client.deleted_at is null and client.purged_at is null
      and private.can_view_client(org, client.id)
    order by client.display_name, client.id
  loop
    plan := private.client_deletion_plan(org, client_row.id);
    clients := clients || jsonb_build_array(jsonb_build_object(
      'client_id', client_row.id,
      'display_name', client_row.display_name,
      'created_at', client_row.created_at,
      'counts', plan -> 'counts',
      'kept', plan -> 'kept',
      'blockers', plan -> 'blockers'
    ));
    if jsonb_array_length(plan -> 'blockers') = 0 then
      for kv in select key, value::bigint as n from jsonb_each_text(plan -> 'counts') loop
        totals := totals || jsonb_build_object(kv.key, coalesce((totals ->> kv.key)::bigint, 0) + kv.n);
      end loop;
      for kv in select key, value::bigint as n from jsonb_each_text(plan -> 'kept') loop
        kept_totals := kept_totals || jsonb_build_object(kv.key, coalesce((kept_totals ->> kv.key)::bigint, 0) + kv.n);
      end loop;
    end if;
  end loop;

  return jsonb_build_object(
    'clients', clients,
    'totals', totals,
    'kept_totals', kept_totals,
    'restore_days', 30,
    'purge_after', now() + interval '30 days'
  );
end;
$$;

revoke all on function public.client_delete_preview(uuid[]) from public, anon;
grant execute on function public.client_delete_preview(uuid[]) to authenticated, service_role;

-- Moves clients to Recently Deleted. A client with open money is left out and named with its reasons; the
-- others go. Returns { deleted: [{client_id, deletion_id, display_name}], left_out: [{client_id, display_name,
-- blockers}] }.
create or replace function public.delete_clients(target_client_ids uuid[])
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'pg_catalog', 'public'
  as $$
declare
  caller uuid := (select auth.uid());
  client_row public.clients;
  plan jsonb;
  stamp timestamptz := now();
  deletion_id uuid;
  deleted jsonb := '[]'::jsonb;
  left_out jsonb := '[]'::jsonb;
begin
  for client_row in select * from private.lock_clients_for_delete(target_client_ids, 'customers.delete') loop
    plan := private.client_deletion_plan(client_row.organization_id, client_row.id);

    if jsonb_array_length(plan -> 'blockers') > 0 then
      left_out := left_out || jsonb_build_array(jsonb_build_object(
        'client_id', client_row.id, 'display_name', client_row.display_name, 'blockers', plan -> 'blockers'));
      continue;
    end if;

    perform private.set_client_deleted_mark(client_row.organization_id, client_row.id, stamp);

    insert into public.client_deletions (organization_id, client_id, deleted_at, deleted_by, purge_after, counts, kept)
    values (client_row.organization_id, client_row.id, stamp, caller, stamp + interval '30 days',
      plan -> 'counts', plan -> 'kept')
    returning id into deletion_id;

    insert into public.activity_events (organization_id, entity_type, entity_id, event_type, summary, actor_user_id,
      metadata)
    values (client_row.organization_id, 'client', client_row.id, 'client.deleted',
      'Moved this client to Recently Deleted.', caller,
      jsonb_build_object('deletion_id', deletion_id, 'counts', plan -> 'counts'));

    deleted := deleted || jsonb_build_array(jsonb_build_object(
      'client_id', client_row.id, 'deletion_id', deletion_id, 'display_name', client_row.display_name));
  end loop;

  if jsonb_array_length(deleted) = 0 and jsonb_array_length(left_out) = 0 then
    raise exception 'That client could not be found.' using errcode = 'P0002';
  end if;

  return jsonb_build_object('deleted', deleted, 'left_out', left_out, 'purge_after', stamp + interval '30 days');
end;
$$;

revoke all on function public.delete_clients(uuid[]) from public, anon;
grant execute on function public.delete_clients(uuid[]) to authenticated, service_role;

-- Restores deleted clients. When a newer client already holds one of their phone numbers or emails:
--   restore_mode 'check'    -> that client is not restored; the match is returned for the pop-up
--   restore_mode 'separate' -> restored; the clashing values stay hidden on it (the newer client keeps them)
--   restore_mode 'merge'    -> restored the same way, then merged into the newer client (one match only)
-- Returns { restored: [{deletion_id, client_id, display_name, merged_into}], matches: [{deletion_id,
-- client_id, display_name, other_client_id, other_display_name, kind, value}] }.
create or replace function public.restore_client_deletions(target_deletion_ids uuid[], restore_mode text default 'check')
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'pg_catalog', 'public'
  as $$
declare
  caller uuid := (select auth.uid());
  org uuid := (select private.current_organization());
  deletion public.client_deletions;
  client_row public.clients;
  found_matches jsonb;
  other_ids uuid[];
  dup record;
  restored jsonb := '[]'::jsonb;
  matches jsonb := '[]'::jsonb;
begin
  if caller is null or org is null
     or not private.member_has_permission(org, caller, 'customers.delete') then
    raise exception 'You do not have access to restore clients.' using errcode = 'insufficient_privilege';
  end if;
  if restore_mode not in ('check', 'separate', 'merge') then
    raise exception 'Unknown restore choice.' using errcode = '22023';
  end if;
  if coalesce(cardinality(target_deletion_ids), 0) = 0 or cardinality(target_deletion_ids) > 100 then
    raise exception 'Choose between 1 and 100 clients.' using errcode = '22023';
  end if;
  if restore_mode = 'merge' and cardinality(target_deletion_ids) > 1 then
    raise exception 'Restore and merge one client at a time.' using errcode = '22023';
  end if;

  for deletion in
    select * from public.client_deletions
    where organization_id = org and id = any(target_deletion_ids)
      and restored_at is null and purged_at is null
    order by client_id
    for update
  loop
    select * into client_row from public.clients
    where organization_id = org and id = deletion.client_id
    for update;

    select coalesce(jsonb_agg(jsonb_build_object(
        'deletion_id', deletion.id, 'client_id', client_row.id, 'display_name', client_row.display_name,
        'other_client_id', other.id, 'other_display_name', other.display_name,
        'kind', mine.kind, 'value', mine.value)
        order by mine.kind, mine.value), '[]'::jsonb),
      coalesce(array_agg(distinct other.id), '{}')
    into found_matches, other_ids
    from public.client_contact_methods as mine
    join public.client_contact_methods as theirs
      on theirs.organization_id = org and theirs.kind = mine.kind
      and theirs.normalized_value = mine.normalized_value and theirs.client_deleted_at is null
    join public.clients as other on other.organization_id = org and other.id = theirs.client_id
    where mine.organization_id = org and mine.client_id = client_row.id;

    if jsonb_array_length(found_matches) > 0 and restore_mode = 'check' then
      matches := matches || found_matches;
      continue;
    end if;
    if restore_mode = 'merge' and cardinality(other_ids) <> 1 then
      raise exception 'This client matches more than one client, so restore them separately.'
        using errcode = '22023';
    end if;

    perform private.set_client_deleted_mark(org, client_row.id, null);

    update public.client_deletions set restored_at = now(), restored_by = caller where id = deletion.id;

    insert into public.activity_events (organization_id, entity_type, entity_id, event_type, summary, actor_user_id,
      metadata)
    values (org, 'client', client_row.id, 'client.undeleted', 'Restored this client from Recently Deleted.', caller,
      jsonb_build_object('deletion_id', deletion.id, 'hidden_contact_values', jsonb_array_length(found_matches)));

    if restore_mode = 'merge' and cardinality(other_ids) = 1 then
      -- The values still hidden on this client are the newer client's own; their history moves onto the newer
      -- client's row first, so the merge never meets the same value twice on one client.
      perform set_config('app.client_lifecycle_in_progress', 'true', true);
      for dup in
        select mine.id as mine_id, theirs.id as theirs_id, theirs.client_id as theirs_client_id
        from public.client_contact_methods as mine
        join public.client_contact_methods as theirs
          on theirs.organization_id = org and theirs.kind = mine.kind
          and theirs.normalized_value = mine.normalized_value and theirs.client_deleted_at is null
        where mine.organization_id = org and mine.client_id = client_row.id and mine.client_deleted_at is not null
      loop
        update public.communication_reply_aliases set client_contact_method_id = dup.theirs_id
        where organization_id = org and client_contact_method_id = dup.mine_id;
        update public.communication_delivery_intents set client_contact_method_id = dup.theirs_id
        where organization_id = org and client_contact_method_id = dup.mine_id;
        update public.communication_inbound_messages set client_contact_method_id = dup.theirs_id
        where organization_id = org and client_contact_method_id = dup.mine_id;
        update public.communication_sms_consent_events
        set client_id = dup.theirs_client_id, client_contact_method_id = dup.theirs_id
        where organization_id = org and client_contact_method_id = dup.mine_id;
        update public.client_marketing_consent_events
        set client_id = dup.theirs_client_id, client_contact_method_id = dup.theirs_id
        where organization_id = org and client_contact_method_id = dup.mine_id;
        delete from public.client_contact_methods where organization_id = org and id = dup.mine_id;
      end loop;
      perform set_config('app.client_lifecycle_in_progress', 'false', true);
      perform public.merge_clients(other_ids[1], client_row.id);
    end if;

    restored := restored || jsonb_build_array(jsonb_build_object(
      'deletion_id', deletion.id, 'client_id', client_row.id, 'display_name', client_row.display_name,
      'merged_into', case when restore_mode = 'merge' then other_ids[1] end));
  end loop;

  if jsonb_array_length(restored) = 0 and jsonb_array_length(matches) = 0 then
    raise exception 'That client could not be found in Recently Deleted.' using errcode = 'P0002';
  end if;

  return jsonb_build_object('restored', restored, 'matches', matches);
end;
$$;

revoke all on function public.restore_client_deletions(uuid[], text) from public, anon;
grant execute on function public.restore_client_deletions(uuid[], text) to authenticated, service_role;

-- The Recently Deleted page: every open delete in the business, soonest permanent delete first.
create or replace function public.recently_deleted_clients()
  returns table (
    deletion_id uuid, client_id uuid, display_name text, deleted_at timestamptz, deleted_by uuid,
    deleted_by_name text, purge_after timestamptz, counts jsonb, kept jsonb
  )
  language plpgsql
  stable
  security definer
  set search_path to 'pg_catalog', 'public'
  as $$
declare
  caller uuid := (select auth.uid());
  org uuid := (select private.current_organization());
begin
  if caller is null or org is null
     or not private.member_has_permission(org, caller, 'customers.delete') then
    raise exception 'You do not have access to Recently Deleted.' using errcode = 'insufficient_privilege';
  end if;

  return query
  select deletion.id, deletion.client_id, client.display_name, deletion.deleted_at, deletion.deleted_by,
    coalesce(nullif(profile.full_name, ''), member.display_name_at_removal), deletion.purge_after,
    deletion.counts, deletion.kept
  from public.client_deletions as deletion
  join public.clients as client on client.organization_id = deletion.organization_id and client.id = deletion.client_id
  left join public.profiles as profile on profile.id = deletion.deleted_by
  left join public.organization_members as member
    on member.organization_id = deletion.organization_id and member.user_id = deletion.deleted_by
  where deletion.organization_id = org and deletion.restored_at is null and deletion.purged_at is null
  order by deletion.purge_after, deletion.id
  limit 1000;
end;
$$;

revoke all on function public.recently_deleted_clients() from public, anon;
grant execute on function public.recently_deleted_clients() to authenticated, service_role;

-- 7. After the permanent delete --------------------------------------------------------------------------

-- The engine keeps a few anonymous shells (a quote that took a deposit, its property) for the money records.
-- Before Part 6 they were visible; they stay visible, so the deposit report and payment lists still read them.
-- An open delete record is closed as purged.
create or replace function private.after_client_purged()
  returns trigger
  language plpgsql
  security definer
  set search_path to 'pg_catalog', 'public'
  as $$
begin
  perform set_config('app.client_lifecycle_in_progress', 'true', true);
  update public.quotes set client_deleted_at = null
  where organization_id = new.organization_id and client_id = new.id and client_deleted_at is not null;
  update public.properties set client_deleted_at = null
  where organization_id = new.organization_id and client_id = new.id and client_deleted_at is not null;
  update public.client_deletions set purged_at = new.purged_at, purge_failure = null, purge_failed_since = null
  where organization_id = new.organization_id and client_id = new.id
    and restored_at is null and purged_at is null;
  perform set_config('app.client_lifecycle_in_progress', 'false', true);
  return new;
end;
$$;

revoke all on function private.after_client_purged() from public, anon, authenticated;

create trigger after_client_purged after update of purged_at on public.clients
  for each row when (old.purged_at is null and new.purged_at is not null)
  execute function private.after_client_purged();

-- 3 (continued). Member reads hide marked rows.
alter policy "members can view assessments" on public.assessments using ((((organization_id = ( SELECT private.current_organization() AS current_organization)) AND ((( SELECT private.current_permission_scope('jobs.view'::text) AS current_permission_scope) <> 'assigned'::text) OR private.is_assigned_to_assessment(organization_id, id)))) and client_deleted_at is null);
alter policy "permitted members can view client contact methods" on public.client_contact_methods using ((((organization_id = ( SELECT private.current_organization() AS current_organization)) AND (( SELECT private.has_permission(( SELECT private.current_organization() AS current_organization), 'customers.view'::text) AS has_permission) OR (client_id IN ( SELECT private.current_user_assigned_client_ids() AS current_user_assigned_client_ids))))) and client_deleted_at is null);
alter policy "permitted members can view clients" on public.clients using ((((organization_id = ( SELECT private.current_organization() AS current_organization)) AND (( SELECT private.has_permission(( SELECT private.current_organization() AS current_organization), 'customers.view'::text) AS has_permission) OR (id IN ( SELECT private.current_user_assigned_client_ids() AS current_user_assigned_client_ids))))) and deleted_at is null);
alter policy "permitted members can view invoices" on public.invoices using ((((organization_id = ( SELECT private.current_organization() AS current_organization)) AND ( SELECT private.has_permission(( SELECT private.current_organization() AS current_organization), 'invoices.view'::text) AS has_permission))) and client_deleted_at is null);
alter policy "permitted members can view job visits" on public.job_visits using ((((organization_id = ( SELECT private.current_organization() AS current_organization)) AND ((( SELECT private.current_permission_scope('jobs.view'::text) AS current_permission_scope) = 'all'::text) OR ((( SELECT private.current_permission_scope('jobs.view'::text) AS current_permission_scope) = 'assigned'::text) AND private.is_assigned_to_job(organization_id, job_id))))) and client_deleted_at is null);
alter policy "permitted members can view jobs" on public.jobs using ((((organization_id = ( SELECT private.current_organization() AS current_organization)) AND ((( SELECT private.current_permission_scope('jobs.view'::text) AS current_permission_scope) = 'all'::text) OR ((( SELECT private.current_permission_scope('jobs.view'::text) AS current_permission_scope) = 'assigned'::text) AND private.is_assigned_to_job(organization_id, id))))) and client_deleted_at is null);
alter policy "permitted members can view opportunities" on public.opportunities using (((organization_id IN ( SELECT private.permitted_organizations('pipeline.view'::text) AS permitted_organizations))) and client_deleted_at is null);
alter policy "permitted members can view properties" on public.properties using ((((organization_id = ( SELECT private.current_organization() AS current_organization)) AND (( SELECT private.has_permission(( SELECT private.current_organization() AS current_organization), 'customers.view'::text) AS has_permission) OR (client_id IN ( SELECT private.current_user_assigned_client_ids() AS current_user_assigned_client_ids))))) and client_deleted_at is null);
alter policy "permitted members can view quotes" on public.quotes using (((organization_id IN ( SELECT private.permitted_organizations('quotes.view'::text) AS permitted_organizations))) and client_deleted_at is null);
alter policy "members can view requests" on public.requests using ((((organization_id = ( SELECT private.current_organization() AS current_organization)) AND ( SELECT private.has_permission(( SELECT private.current_organization() AS current_organization), 'requests.view'::text) AS has_permission) AND ((( SELECT private.current_permission_scope('requests.view'::text) AS current_permission_scope) <> 'assigned'::text) OR (id IN ( SELECT private.current_user_assigned_request_ids() AS current_user_assigned_request_ids))))) and client_deleted_at is null);

-- 5 (continued). Outgoing email skips a deleted customer at claim time; SMS already checks clients.deleted_at.

CREATE OR REPLACE FUNCTION public.claim_communication_outbox_event()
 RETURNS TABLE(outbox_event_id uuid, delivery_intent_id uuid, organization_id uuid, claim_token uuid, recipient_email text, subject text, html_content text, text_content text, logical_send_key text, sender_id uuid, sender_email text, sender_name text, sender_provider text, reply_to_email text, reply_to_name text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
declare
  candidate record;
  current_recipient public.client_contact_methods;
  selected_sender public.communication_email_senders;
  sender_domain public.communication_email_domains;
  assigned_member_status text;
  active_allowance record;
  allowance_limit_state text;
  allowance_limit_value integer;
  accepted_recipient_count integer;
  reserved_recipient_count integer;
  new_claim_token uuid;
  alias public.communication_reply_aliases;
  alias_domain public.communication_email_domains;
  holding_pause public.communication_email_sending_pauses%rowtype;
  hold_code text;
  hold_message text;
  today_start timestamptz := date_trunc('day', now() at time zone 'UTC') at time zone 'UTC';
  warmup_ceiling integer;
  warmup_used_today integer;
  short_term_max integer;
  short_term_window integer;
  short_term_used integer;
  short_term_oldest_at timestamptz;
  short_term_retry_at timestamptz;
  provider_capacity integer;
  provider_reserve_percent integer;
  provider_reserve integer;
  provider_effective_cap integer;
  current_period_start timestamptz := date_trunc('month', now() at time zone 'UTC') at time zone 'UTC';
  platform_accepted bigint;
  platform_reserved bigint;
  email_rate public.communication_email_retail_rates;
  credit_cost_minor bigint;
  credit_recipient_count integer;
  credit_promo_used bigint;
  credit_purchased_used bigint;
  credit_settled bigint;
  credit_reserved bigint;
  credit_promo_balance bigint;
  credit_promo_reserved bigint;
  credit_promo_available bigint;
  credit_purchased_available bigint;
begin
  if exists (
    select 1 from public.communication_email_sending_pauses
    where scope = 'platform' and released_at is null
  ) then
    return;
  end if;

  for candidate in
    select
      event.id as event_id,
      event.delivery_intent_id,
      intent.organization_id,
      intent.client_id,
      intent.client_contact_method_id,
      intent.recipient_email,
      intent.subject,
      intent.html_content,
      intent.text_content,
      intent.logical_send_key,
      intent.send_kind,
      intent.allowance_class,
      intent.retry_class,
      intent.expires_at,
      intent.sender_id,
      intent.reply_alias_id,
      intent.created_by
    from public.communication_outbox_events event
    join public.communication_delivery_intents intent on intent.id = event.delivery_intent_id
    where event.channel = 'email' and event.status in ('pending', 'failed') and event.available_at <= now()
    order by event.available_at, event.created_at, event.id
    limit 50
    for update of event skip locked
  loop
    if candidate.expires_at <= now() then
      hold_message := case candidate.retry_class
        when 'payment_receipt' then
          'This receipt could not be sent within 72 hours, so UCRM cancelled it. Send it again once sending is working.'
        when 'appointment_reminder' then
          'This reminder was not sent before its appointment window passed, so UCRM cancelled it.'
        when 'optional_followup' then
          'This follow-up passed its send window before it could go out, so UCRM cancelled it.'
        else
          'This message could not be sent within 24 hours, so UCRM cancelled it. Send it again once sending is working.'
      end;
      update public.communication_delivery_intents
      set status = 'cancelled', provider_message_id = null, accepted_at = null,
        failure_code = 'retry_deadline_passed', failure_message = hold_message
      where id = candidate.delivery_intent_id;
      update public.communication_outbox_events
      set status = 'cancelled', claimed_at = null, claim_token = null, last_error = hold_message
      where id = candidate.event_id;
      continue;
    end if;

    hold_code := null;
    hold_message := null;

    if exists (
      select 1 from public.organizations org
      where org.id = candidate.organization_id
        and org.lifecycle_status = 'suspended'
    ) then
      hold_code := 'organization_suspended';
      hold_message := 'Sending is suspended for this organization. UCRM will retry once it is reactivated.';
    elsif exists (
      select 1 from public.organization_closure_records closure
      where closure.organization_id = candidate.organization_id
        and closure.status in ('pending_closure', 'purge_in_progress')
    ) then
      hold_code := 'organization_closing';
      hold_message := 'This organization is closing. UCRM will retry if the closure is reversed.';
    end if;

    if hold_code is not null then
      update public.communication_delivery_intents
      set failure_code = hold_code, failure_message = hold_message
      where id = candidate.delivery_intent_id;
      update public.communication_outbox_events
      set available_at = least(now() + interval '1 hour', candidate.expires_at), last_error = hold_message
      where id = candidate.event_id;
      continue;
    end if;

    current_recipient := null;
    select method.* into current_recipient
    from public.client_contact_methods method
    where method.organization_id = candidate.organization_id
      and method.id = candidate.client_contact_method_id
    for share;

    if current_recipient.id is null
      or current_recipient.client_id <> candidate.client_id
      or current_recipient.kind <> 'email'
      -- A customer in Recently Deleted gets nothing; a send due while they were deleted is never sent late.
      or current_recipient.client_deleted_at is not null
      or current_recipient.normalized_value <> candidate.recipient_email then
      update public.communication_delivery_intents
      set status = 'cancelled', provider_message_id = null, accepted_at = null,
        failure_code = 'recipient_no_longer_eligible',
        failure_message = 'The queued recipient is no longer an active email method for this customer.'
      where id = candidate.delivery_intent_id;
      update public.communication_outbox_events
      set status = 'cancelled', claimed_at = null, claim_token = null,
        last_error = 'The queued recipient is no longer an active email method for this customer.'
      where id = candidate.event_id;
      continue;
    end if;

    if exists (
      select 1
      from public.communication_email_suppressions suppression
      where suppression.organization_id = candidate.organization_id
        and suppression.recipient_email = candidate.recipient_email
        and suppression.released_at is null
        and (
          suppression.reason in ('hard_bounce', 'complaint')
          or (suppression.reason = 'unsubscribe' and candidate.allowance_class = 'optional')
        )
    ) then
      update public.communication_delivery_intents
      set status = 'cancelled', provider_message_id = null, accepted_at = null,
        failure_code = 'recipient_suppressed',
        failure_message = 'This recipient address is on the organization suppression list.'
      where id = candidate.delivery_intent_id;
      update public.communication_outbox_events
      set status = 'cancelled', claimed_at = null, claim_token = null,
        last_error = 'This recipient address is on the organization suppression list.'
      where id = candidate.event_id;
      continue;
    end if;

    holding_pause := null;
    select pause.* into holding_pause
    from public.communication_email_sending_pauses pause
    where pause.scope = 'organization'
      and pause.organization_id = candidate.organization_id
      and pause.released_at is null
      and (pause.applies_to = 'all' or candidate.allowance_class = 'optional')
    order by case when pause.applies_to = 'all' then 0 else 1 end
    limit 1;

    if holding_pause.id is not null then
      if holding_pause.source = 'auto_reputation' then
        hold_code := 'sending_paused_reputation';
        hold_message := 'Optional email is paused while this organization''s delivery reputation is reviewed.';
      else
        hold_code := 'sending_paused_organization';
        hold_message := 'Sending for this organization is paused. UCRM will retry when it resumes.';
      end if;
      update public.communication_delivery_intents
      set failure_code = hold_code, failure_message = hold_message
      where id = candidate.delivery_intent_id;
      update public.communication_outbox_events
      set available_at = least(now() + interval '5 minutes', candidate.expires_at), last_error = hold_message
      where id = candidate.event_id;
      continue;
    end if;

    selected_sender := null;
    if candidate.sender_id is not null then
      select sender.* into selected_sender
      from public.communication_email_senders sender
      where sender.organization_id = candidate.organization_id and sender.id = candidate.sender_id
      for share;
    elsif candidate.send_kind = 'automated' then
      select sender.* into selected_sender
      from public.communication_email_senders sender
      where sender.organization_id = candidate.organization_id
        and sender.is_organization_default and sender.lifecycle_state <> 'removed'
      order by sender.created_at, sender.id limit 1 for share;
    end if;

    if selected_sender.id is null then
      if candidate.send_kind = 'manual' then
        update public.communication_delivery_intents set status = 'failed', provider_message_id = null,
          accepted_at = null, failure_code = 'manual_sender_review_required',
          failure_message = 'The original sender is no longer eligible. Review and reassign this message.'
        where id = candidate.delivery_intent_id;
        update public.communication_outbox_events set status = 'failed', available_at = 'infinity'::timestamptz,
          claimed_at = null, claim_token = null,
          last_error = 'The original sender is no longer eligible. Review and reassign this message.'
        where id = candidate.event_id;
      else
        update public.communication_delivery_intents set status = 'cancelled', provider_message_id = null,
          accepted_at = null, failure_code = 'automated_sender_invalid',
          failure_message = 'The configured automated sender is no longer valid.'
        where id = candidate.delivery_intent_id;
        update public.communication_outbox_events set status = 'cancelled', claimed_at = null, claim_token = null,
          last_error = 'The configured automated sender is no longer valid.'
        where id = candidate.event_id;
      end if;
      continue;
    end if;

    assigned_member_status := null;
    if selected_sender.assigned_user_id is not null then
      select member.status into assigned_member_status from public.organization_members member
      where member.organization_id = selected_sender.organization_id and member.user_id = selected_sender.assigned_user_id
      for share;
    end if;
    sender_domain := null;
    select domain.* into sender_domain from public.communication_email_domains domain
    where domain.organization_id = selected_sender.organization_id and domain.id = selected_sender.domain_id
    for share;

    if selected_sender.lifecycle_state = 'pending_verification'
      or (sender_domain.id is not null and sender_domain.lifecycle_state not in ('removal_pending', 'removed')
        and (sender_domain.lifecycle_state <> 'verified' or not sender_domain.provider_verified
          or not sender_domain.provider_authenticated or sender_domain.ownership_status <> 'passing'
          or sender_domain.dkim_status <> 'passing')) then
      update public.communication_delivery_intents set failure_code = 'sender_domain_temporarily_unavailable',
        failure_message = 'The sending domain is temporarily unavailable. UCRM will check again.'
      where id = candidate.delivery_intent_id;
      update public.communication_outbox_events
      set available_at = least(now() + interval '15 minutes', candidate.expires_at),
        last_error = 'The sending domain is temporarily unavailable. UCRM will check again.'
      where id = candidate.event_id;
      continue;
    end if;

    if selected_sender.lifecycle_state <> 'enabled'
      or (candidate.send_kind = 'manual' and not selected_sender.allows_manual)
      or (candidate.send_kind = 'automated' and not selected_sender.allows_automated)
      or (selected_sender.assigned_user_id is not null and assigned_member_status is distinct from 'active')
      or sender_domain.id is null or sender_domain.purpose <> 'sending'
      or sender_domain.lifecycle_state in ('removal_pending', 'removed') then
      if candidate.send_kind = 'manual' then
        update public.communication_delivery_intents set status = 'failed', provider_message_id = null,
          accepted_at = null, failure_code = 'manual_sender_review_required',
          failure_message = 'The original sender is no longer eligible. Review and reassign this message.'
        where id = candidate.delivery_intent_id;
        update public.communication_outbox_events set status = 'failed', available_at = 'infinity'::timestamptz,
          claimed_at = null, claim_token = null,
          last_error = 'The original sender is no longer eligible. Review and reassign this message.'
        where id = candidate.event_id;
      else
        update public.communication_delivery_intents set status = 'cancelled', provider_message_id = null,
          accepted_at = null, failure_code = 'automated_sender_invalid',
          failure_message = 'The configured automated sender is no longer valid.'
        where id = candidate.delivery_intent_id;
        update public.communication_outbox_events set status = 'cancelled', claimed_at = null, claim_token = null,
          last_error = 'The configured automated sender is no longer valid.'
        where id = candidate.event_id;
      end if;
      continue;
    end if;

    warmup_ceiling := private.resolve_communication_email_warmup_ceiling(
      candidate.organization_id, sender_domain.id, now());
    if warmup_ceiling is not null then
      select
        coalesce((
          select sum(usage.recipient_count)
          from public.communication_email_usage_events usage
          join public.communication_delivery_intents used_intent on used_intent.id = usage.delivery_intent_id
          join public.communication_email_senders used_sender on used_sender.id = used_intent.sender_id
          where usage.organization_id = candidate.organization_id
            and usage.occurred_at >= today_start
            and used_sender.domain_id = sender_domain.id
        ), 0)
      + coalesce((
          select sum(reservation.recipient_count)
          from public.communication_email_capacity_reservations reservation
          join public.communication_delivery_intents reserved_intent on reserved_intent.id = reservation.delivery_intent_id
          join public.communication_email_senders reserved_sender on reserved_sender.id = reserved_intent.sender_id
          where reservation.organization_id = candidate.organization_id
            and reservation.reservation_state in ('reserved', 'submission_unknown')
            and reservation.reserved_at >= today_start
            and reserved_sender.domain_id = sender_domain.id
        ), 0)
      into warmup_used_today;

      if warmup_used_today + 1 > warmup_ceiling then
        update public.communication_delivery_intents
        set failure_code = 'email_warmup_ceiling_reached',
          failure_message = 'This sending domain is still warming up and has reached today''s limit. UCRM will retry tomorrow.'
        where id = candidate.delivery_intent_id;
        update public.communication_outbox_events
        set available_at = least(today_start + interval '1 day', candidate.expires_at),
          last_error = 'This sending domain is still warming up and has reached today''s limit. UCRM will retry tomorrow.'
        where id = candidate.event_id;
        continue;
      end if;
    end if;

    select rate.max_recipients, rate.window_minutes
    into short_term_max, short_term_window
    from private.resolve_communication_email_short_term_rate(candidate.organization_id, now()) rate;

    if short_term_max is not null then
      select
        coalesce((
          select sum(usage.recipient_count)
          from public.communication_email_usage_events usage
          where usage.organization_id = candidate.organization_id
            and usage.occurred_at > now() - make_interval(mins => short_term_window)
        ), 0)
      + coalesce((
          select sum(reservation.recipient_count)
          from public.communication_email_capacity_reservations reservation
          where reservation.organization_id = candidate.organization_id
            and reservation.reservation_state in ('reserved', 'submission_unknown')
            and reservation.reserved_at > now() - make_interval(mins => short_term_window)
        ), 0)
      into short_term_used;

      select min(usage.occurred_at) into short_term_oldest_at
      from public.communication_email_usage_events usage
      where usage.organization_id = candidate.organization_id
        and usage.occurred_at > now() - make_interval(mins => short_term_window);

      if short_term_used + 1 > short_term_max then
        short_term_retry_at := coalesce(short_term_oldest_at, now())
          + make_interval(mins => short_term_window);
        if short_term_retry_at <= now() then
          short_term_retry_at := now() + interval '1 minute';
        end if;
        update public.communication_delivery_intents
        set failure_code = 'email_short_term_rate_limited',
          failure_message = format(
            'This organization has reached its short-term sending limit (%s recipients per %s minutes). UCRM will retry shortly.',
            short_term_max, short_term_window)
        where id = candidate.delivery_intent_id;
        update public.communication_outbox_events
        set available_at = least(short_term_retry_at, candidate.expires_at),
          last_error = 'Short-term sending limit reached. UCRM will retry shortly.'
        where id = candidate.event_id;
        continue;
      end if;
    end if;

    select cap.capacity, cap.reserve_percent
    into provider_capacity, provider_reserve_percent
    from private.resolve_communication_email_provider_capacity(now()) cap;

    if provider_capacity is not null then
      provider_reserve := ceil(provider_capacity::numeric * provider_reserve_percent / 100.0)::integer;
      if candidate.allowance_class = 'optional' then
        provider_effective_cap := provider_capacity - provider_reserve;
      else
        provider_effective_cap := provider_capacity;
      end if;

      select coalesce(usage.accepted_recipients, 0) into platform_accepted
      from public.communication_email_platform_period_usage usage
      where usage.period_start = current_period_start;
      platform_accepted := coalesce(platform_accepted, 0);

      select coalesce(sum(reservation.recipient_count), 0) into platform_reserved
      from public.communication_email_capacity_reservations reservation
      where reservation.reservation_state in ('reserved', 'submission_unknown')
        and reservation.reserved_at >= current_period_start;

      if platform_accepted + platform_reserved + 1 > provider_effective_cap then
        if candidate.allowance_class = 'optional' then
          hold_message := 'The platform has reached its reserved monthly sending capacity. Essential email still sends; other email will retry.';
          update public.communication_delivery_intents
          set failure_code = 'email_platform_capacity_reserved', failure_message = hold_message
          where id = candidate.delivery_intent_id;
        else
          hold_message := 'The platform has reached its monthly provider sending capacity. UCRM will retry shortly.';
          update public.communication_delivery_intents
          set failure_code = 'email_platform_capacity_reached', failure_message = hold_message
          where id = candidate.delivery_intent_id;
        end if;
        update public.communication_outbox_events
        set available_at = least(now() + interval '15 minutes', candidate.expires_at), last_error = hold_message
        where id = candidate.event_id;
        continue;
      end if;
    end if;

    select * into active_allowance
    from private.resolve_communication_email_allowance(candidate.organization_id, now());
    if not found then
      update public.communication_delivery_intents set failure_code = 'email_allowance_period_unavailable',
        failure_message = 'No active email allowance period is available. UCRM will check again.'
      where id = candidate.delivery_intent_id;
      update public.communication_outbox_events
      set available_at = least(now() + interval '15 minutes', candidate.expires_at),
        last_error = 'No active email allowance period is available. UCRM will check again.'
      where id = candidate.event_id;
      continue;
    end if;

    if candidate.allowance_class = 'optional' then
      allowance_limit_state := active_allowance.operational_limit_state;
      allowance_limit_value := active_allowance.operational_limit_value;
    else
      allowance_limit_state := active_allowance.essential_limit_state;
      allowance_limit_value := active_allowance.essential_limit_value;
    end if;
    -- A package with no email allowance set ('not_included', or no row at all) is an allowance of zero,
    -- never a stop: essential email still sends (the reserve-exhaustion alert fires once per period) and
    -- optional email is funded from the Communication Balance like any over-allowance email. It used to
    -- retry here every 15 minutes forever with nothing shown to anyone.
    if allowance_limit_state is distinct from 'unlimited'
      and (allowance_limit_state is distinct from 'numeric' or allowance_limit_value is null) then
      allowance_limit_state := 'numeric';
      allowance_limit_value := 0;
    end if;

    insert into public.communication_email_capacity_buckets (
      organization_id, allowance_period_id, allowance_class
    ) values (candidate.organization_id, active_allowance.period_id, candidate.allowance_class)
    on conflict do nothing;
    perform 1 from public.communication_email_capacity_buckets bucket
    where bucket.organization_id = candidate.organization_id
      and bucket.allowance_period_id = active_allowance.period_id
      and bucket.allowance_class = candidate.allowance_class
    for update;

    credit_cost_minor := null;
    credit_recipient_count := null;
    credit_promo_used := null;
    credit_purchased_used := null;

    if allowance_limit_state = 'numeric' then
      select coalesce(sum(usage.recipient_count), 0)::integer into accepted_recipient_count
      from public.communication_email_usage_events usage
      where usage.organization_id = candidate.organization_id
        and usage.allowance_period_id = active_allowance.period_id
        and usage.allowance_class = candidate.allowance_class;
      select coalesce(sum(reservation.recipient_count), 0)::integer into reserved_recipient_count
      from public.communication_email_capacity_reservations reservation
      where reservation.organization_id = candidate.organization_id
        and reservation.allowance_period_id = active_allowance.period_id
        and reservation.allowance_class = candidate.allowance_class
        and reservation.reservation_state in ('reserved', 'submission_unknown');
      if accepted_recipient_count + reserved_recipient_count >= allowance_limit_value then
        if candidate.allowance_class = 'essential' then
          -- Essential email never queues for an exhausted reserve -- alert once per period, then fall
          -- through below and let it send (still counted against the essential bucket as usual).
          perform private.record_communication_email_reserve_exhaustion(candidate.organization_id, active_allowance.period_id);
        else
          -- Optional email over its allowance: try to fund it from the organization's Communication
          -- Balance (the same account and ledger SMS spends from) at Jafar's published over-allowance
          -- price. No published price yet means UCRM cannot safely charge, so this behaves like the old
          -- exhausted-defer instead of guessing a price.
          select rr.* into email_rate
          from public.communication_email_effective_retail_rate('USD', now()) rr;
          if email_rate.id is null then
            update public.communication_delivery_intents set failure_code = 'email_allowance_exhausted',
              failure_message = 'Email allowance is currently exhausted. UCRM will check again.'
            where id = candidate.delivery_intent_id;
            update public.communication_outbox_events
            set available_at = least(now() + interval '15 minutes', candidate.expires_at),
              last_error = 'Email allowance is currently exhausted. UCRM will check again.'
            where id = candidate.event_id;
            continue;
          end if;

          credit_recipient_count := 1;
          credit_cost_minor := ceil(credit_recipient_count * email_rate.retail_rate_major / 1000.0 * 100)::bigint;

          insert into public.communication_sms_credit_accounts (organization_id, currency_code)
          values (candidate.organization_id, email_rate.currency_code)
          on conflict on constraint communication_sms_credit_accounts_pkey do nothing;

          select account.settled_balance_minor, account.reserved_balance_minor into credit_settled, credit_reserved
          from public.communication_sms_credit_accounts account
          where account.organization_id = candidate.organization_id
          for update;

          credit_promo_balance := public.communication_sms_promotional_balance(candidate.organization_id);
          select coalesce(sum(credit_res.reserved_promotional_minor), 0) into credit_promo_reserved
          from public.communication_sms_credit_reservations credit_res
          where credit_res.organization_id = candidate.organization_id
            and credit_res.state in ('reserved', 'submission_unknown', 'settled');
          credit_promo_available := greatest(credit_promo_balance - credit_promo_reserved, 0);
          credit_purchased_available := credit_settled - credit_reserved;

          if credit_promo_available + credit_purchased_available < credit_cost_minor then
            update public.communication_delivery_intents set failure_code = 'email_balance_insufficient',
              failure_message = 'This email is beyond your plan''s free allowance and your Communication Balance is too low to send it. Add credit to send it.'
            where id = candidate.delivery_intent_id;
            update public.communication_outbox_events
            set available_at = least(now() + interval '15 minutes', candidate.expires_at),
              last_error = 'Communication Balance is too low for over-allowance email. UCRM will retry after credit is added.'
            where id = candidate.event_id;
            continue;
          end if;

          credit_promo_used := least(credit_cost_minor, credit_promo_available);
          credit_purchased_used := credit_cost_minor - credit_promo_used;

          update public.communication_sms_credit_accounts
          set reserved_balance_minor = reserved_balance_minor + credit_purchased_used,
              updated_at = now()
          where communication_sms_credit_accounts.organization_id = candidate.organization_id;
        end if;
      end if;
    end if;

    insert into public.communication_email_capacity_reservations (
      organization_id, delivery_intent_id, allowance_period_id, allowance_class, reservation_state, reserved_at, settled_at
    ) values (
      candidate.organization_id, candidate.delivery_intent_id, active_allowance.period_id,
      candidate.allowance_class, 'reserved', now(), null
    ) on conflict on constraint communication_email_capacity_reservations_delivery_intent_key do update set
      organization_id = excluded.organization_id,
      allowance_period_id = excluded.allowance_period_id,
      allowance_class = excluded.allowance_class,
      reservation_state = 'reserved', reserved_at = now(), settled_at = null
    where public.communication_email_capacity_reservations.reservation_state = 'released';
    if not found then
      raise exception 'The email capacity reservation is not available for this delivery intent.'
        using errcode = 'object_not_in_prerequisite_state';
    end if;

    if credit_cost_minor is not null then
      insert into public.communication_sms_credit_reservations (
        organization_id, delivery_intent_id, channel, source_key, amount_minor, recipient_count,
        reserved_promotional_minor, reserved_purchased_minor, state
      ) values (
        candidate.organization_id, candidate.delivery_intent_id, 'email',
        'email-overage:' || candidate.delivery_intent_id::text, credit_cost_minor, credit_recipient_count,
        credit_promo_used, credit_purchased_used, 'reserved'
      )
      on conflict on constraint communication_sms_credit_reservations_one_intent do update set
        source_key = excluded.source_key, amount_minor = excluded.amount_minor,
        recipient_count = excluded.recipient_count, reserved_promotional_minor = excluded.reserved_promotional_minor,
        reserved_purchased_minor = excluded.reserved_purchased_minor,
        state = 'reserved', reserved_at = now(), settled_at = null
      where public.communication_sms_credit_reservations.state = 'released';
      if not found then
        raise exception 'The email over-allowance credit reservation is not available for this delivery intent.'
          using errcode = 'object_not_in_prerequisite_state';
      end if;
    end if;

    alias := null;
    alias_domain := null;
    if candidate.reply_alias_id is not null then
      select rep_alias.* into alias from public.communication_reply_aliases rep_alias
      where rep_alias.id = candidate.reply_alias_id and rep_alias.organization_id = candidate.organization_id
      for share;
      if alias.id is not null then
        select domain.* into alias_domain from public.communication_email_domains domain
        where domain.id = alias.receiving_domain_id and domain.organization_id = candidate.organization_id
        for share;
      end if;
    end if;

    new_claim_token := gen_random_uuid();
    update public.communication_outbox_events set status = 'processing', claimed_at = now(), claim_token = new_claim_token,
      attempt_count = attempt_count + 1, last_error = null where id = candidate.event_id;
    update public.communication_delivery_intents set status = 'claimed', sender_id = selected_sender.id,
      failure_code = null, failure_message = null where id = candidate.delivery_intent_id;
    return query select candidate.event_id, candidate.delivery_intent_id, candidate.organization_id, new_claim_token,
      candidate.recipient_email, candidate.subject, candidate.html_content, candidate.text_content,
      candidate.logical_send_key, selected_sender.id, selected_sender.email_address, selected_sender.display_name,
      sender_domain.provider,
      case when alias.id is not null and alias_domain.id is not null
        then alias.alias_local_part || '@' || alias_domain.domain_name else null end,
      case when alias.id is not null then selected_sender.display_name else null end;
    return;
  end loop;
end;
$function$;

-- 4 (continued). An inbound text from a deleted customer's number starts a new contact on the partial index.

CREATE OR REPLACE FUNCTION public.record_communication_sms_inbound_message(target_organization_id uuid, target_provider_message_id text, target_from_number text, target_body text, target_num_media integer)
 RETURNS communication_inbound_messages
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  normalized_from text := nullif(regexp_replace(coalesce(target_from_number, ''), '[^0-9]', '', 'g'), '');
  resolved_client_id uuid;
  resolved_method_id uuid;
  new_client_id uuid;
  inserted_row public.communication_inbound_messages;
begin
  if normalized_from is null then
    return null;
  end if;

  -- client_contact_methods_org_value_unique_idx (organization_id, kind, normalized_value) guarantees at
  -- most one client can hold this number in this org -- unlike Website Chat's phone+email cross-check,
  -- SMS has only one identifier, so there is no ambiguous-match case to branch on here.
  select method.id, method.client_id into resolved_method_id, resolved_client_id
  from public.client_contact_methods method
  join public.clients client
    on client.organization_id = method.organization_id and client.id = method.client_id
  where method.organization_id = target_organization_id
    and method.kind = 'phone'
    and method.normalized_value = normalized_from
    and client.deleted_at is null;

  if resolved_method_id is null then
    -- Nobody matched: a new Lead, exactly like an unmatched Website Chat visitor. Two inbound texts from
    -- the same brand-new number can race here; client_contact_methods_org_value_unique_idx (organization,
    -- kind, normalized_value) is the tiebreaker. The loser discards its own just-created Lead and attaches
    -- to whichever contact method actually won, rather than erroring the whole request.
    insert into public.clients (
      organization_id, display_name, lifecycle_status, lead_source, client_type
    ) values (
      target_organization_id, target_from_number, 'lead', 'SMS', 'person'
    ) returning id into new_client_id;

    insert into public.client_contact_methods (organization_id, client_id, kind, value, is_primary)
    values (target_organization_id, new_client_id, 'phone', target_from_number, true)
    on conflict (organization_id, kind, normalized_value) where client_deleted_at is null do nothing
    returning id into resolved_method_id;

    if resolved_method_id is null then
      select method.id, method.client_id into resolved_method_id, resolved_client_id
      from public.client_contact_methods method
      where method.organization_id = target_organization_id
        and method.kind = 'phone'
        and method.normalized_value = normalized_from
        and method.client_deleted_at is null;
      delete from public.clients where organization_id = target_organization_id and id = new_client_id;
    else
      resolved_client_id := new_client_id;
    end if;
  end if;

  insert into public.communication_inbound_messages (
    organization_id, channel, client_id, client_contact_method_id, provider, provider_message_id,
    sender_phone, subject, text_content, attachment_count, message_kind, review_status
  ) values (
    target_organization_id, 'sms', resolved_client_id, resolved_method_id, 'twilio', target_provider_message_id,
    target_from_number, '', coalesce(target_body, ''), coalesce(target_num_media, 0), 'reply', 'accepted'
  )
  on conflict (provider, provider_message_id) where provider_message_id is not null do nothing
  returning * into inserted_row;

  return inserted_row;
end;
$function$;
