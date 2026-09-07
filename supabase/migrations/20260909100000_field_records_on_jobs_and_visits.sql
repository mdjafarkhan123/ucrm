-- Jobs, Part 15a-1: field records on Jobs and Visits.
--
-- The contract said notes and attachments ride jobs.edit. Jobber says the opposite, and checking it settled
-- the question: the base Field crew preset "can see their own schedule, mark work complete, add notes and
-- photos on their jobs" while holding no Jobs create or edit right at all. Notes and Files are their own
-- switches beside the Jobs ladder, never inside it. Under our shipped keys a Field member holds jobs.view
-- and jobs.complete, so folding records into jobs.edit locked a crew member out of photographing the work
-- they were standing in front of.
--
-- Two things follow, and both are Jobber's, not ours:
--
--   Seeing a record is derived, never granted. Jobber's lowest Notes rung shows notes "only in the areas
--   they have permission to view", so a note inherits its parent's visibility. can_view_linked_entity
--   already works exactly that way; job and visit just become two more branches.
--
--   Only somebody else's record needs a permission. Jobber gates "view all", "edit all" and "delete all" --
--   the rungs are about everyone's records, never your own. That is the own/team split we already shipped
--   for expenses, so field_records.record / field_records.manage_team mirror expenses.record /
--   expenses.manage_team key for key.
--
-- No new tables. Widening the polymorphic seam is three edits, not one -- the entity_type lists, the
-- visibility pair, and the existence check -- the lesson paid for in 20260820110125 and repeated for expense
-- receipts in 20260908170000. This follows that same path.
--
-- Deliberately NOT here, and shipping next as 15a-2: narrowing the Field role's jobs.view to assigned work
-- only. That is also Jobber's behavior, but it turns on the dormant scope machinery from 20260822055549 and
-- has to sweep every shipped jobs.view policy and read model at once. Splitting it keeps this migration
-- reviewable and lets the assigned-scope change be verified on its own. Until it lands, can_view_job below
-- is the single function that change extends -- exactly like client_is_assigned_to_current_user.

-- 1. The two keys ------------------------------------------------------------------------------------------

insert into public.permissions (key, description)
values
  ('field_records.record', 'Add notes, photos and files to a job or visit, and change their own'),
  ('field_records.manage_team', 'Change or remove anyone''s job and visit records')
on conflict (key) do update set description = excluded.description;

-- Sales and office already write job notes today through jobs.edit; granting both here preserves exactly
-- what they can do rather than quietly taking it away with the contract fix. Field gets the record half --
-- logging what you did on your own job is the entire point of the own/team split.
insert into public.role_permissions (role, permission_key)
values
  ('owner', 'field_records.record'),
  ('owner', 'field_records.manage_team'),

  ('admin', 'field_records.record'),
  ('admin', 'field_records.manage_team'),

  ('office', 'field_records.record'),
  ('office', 'field_records.manage_team'),

  ('sales', 'field_records.record'),
  ('sales', 'field_records.manage_team'),

  ('finance', 'field_records.record'),
  ('finance', 'field_records.manage_team'),

  ('field', 'field_records.record')
on conflict (role, permission_key) do nothing;

-- 2. Widen the entity_type lists ---------------------------------------------------------------------------

-- Notes, tags, attachments and the activity feed all gain both. The feed is not optional: the note_link
-- trigger writes a 'note_added' row into activity_events, so leaving its list alone made attaching the very
-- first job note fail on a check constraint. That is the fourth edit this polymorphic seam always needs, and
-- it only showed up because the RLS test actually attached a note instead of reasoning about it.
alter table public.note_links drop constraint note_links_entity_type_check;
alter table public.note_links add constraint note_links_entity_type_check
  check (entity_type in ('client', 'property', 'request', 'quote', 'job', 'visit')) not valid;
alter table public.note_links validate constraint note_links_entity_type_check;

alter table public.tag_assignments drop constraint tag_assignments_entity_type_check;
alter table public.tag_assignments add constraint tag_assignments_entity_type_check
  check (entity_type in ('client', 'property', 'request', 'quote', 'job', 'visit')) not valid;
alter table public.tag_assignments validate constraint tag_assignments_entity_type_check;

alter table public.attachments drop constraint attachments_entity_type_check;
alter table public.attachments add constraint attachments_entity_type_check
  check (entity_type in ('client', 'property', 'request', 'quote', 'job_expense', 'job', 'visit')) not valid;
alter table public.attachments validate constraint attachments_entity_type_check;

alter table public.activity_events drop constraint activity_events_entity_type_check;
alter table public.activity_events add constraint activity_events_entity_type_check
  check (entity_type in ('client', 'property', 'request', 'quote', 'job', 'visit')) not valid;
alter table public.activity_events validate constraint activity_events_entity_type_check;

-- 3. Visibility, derived from the parent -------------------------------------------------------------------

-- The seam 15a-2 extends. Today jobs.view is unscoped, so seeing the Job is the whole test; when the Field
-- role narrows to assigned work, the assigned check is added HERE and every caller below inherits it.
create or replace function private.can_view_job(
  target_organization_id uuid,
  target_job_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select private.has_permission(target_organization_id, 'jobs.view')
    and exists (
      select 1
      from public.jobs
      where id = target_job_id
        and organization_id = target_organization_id
    );
$$;

revoke all on function private.can_view_job(uuid, uuid) from public;
grant execute on function private.can_view_job(uuid, uuid) to authenticated;

-- A Visit has no visibility of its own: it is a day of its Job's work, so it answers with its Job.
create or replace function private.can_view_visit(
  target_organization_id uuid,
  target_visit_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select exists (
    select 1
    from public.job_visits as visit
    where visit.id = target_visit_id
      and visit.organization_id = target_organization_id
      and private.can_view_job(visit.organization_id, visit.job_id)
  );
$$;

revoke all on function private.can_view_visit(uuid, uuid) from public;
grant execute on function private.can_view_visit(uuid, uuid) to authenticated;

create or replace function private.can_view_linked_entity(
  target_organization_id uuid,
  target_entity_type text,
  target_entity_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select coalesce(
    case target_entity_type
      when 'client' then private.can_view_client(target_organization_id, target_entity_id)
      when 'property' then private.can_view_property(target_organization_id, target_entity_id)
      when 'request' then private.can_view_request(target_organization_id, target_entity_id)
      when 'quote' then private.can_view_quote(target_organization_id, target_entity_id)
      when 'job_expense' then private.can_view_job_expense(target_organization_id, target_entity_id)
      when 'job' then private.can_view_job(target_organization_id, target_entity_id)
      when 'visit' then private.can_view_visit(target_organization_id, target_entity_id)
      else false
    end,
    false
  );
$$;

-- 4. Managing a record, and whose it is --------------------------------------------------------------------

-- The own/team rule itself, in one place so job and visit cannot drift apart.
create or replace function private.field_record_write_allowed(
  target_organization_id uuid,
  target_record_owner uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select private.has_permission(target_organization_id, 'field_records.manage_team')
    or (
      private.has_permission(target_organization_id, 'field_records.record')
      and (
        target_record_owner is null
        or target_record_owner = (select auth.uid())
      )
    );
$$;

revoke all on function private.field_record_write_allowed(uuid, uuid) from public;
grant execute on function private.field_record_write_allowed(uuid, uuid) to authenticated;

-- Until now "may I manage this record" was answered entirely by the parent: anyone with customers.edit can
-- delete anyone's client note. Job and visit records need the finer answer Jobber describes, so the question
-- grows a fourth argument -- who wrote the row. Every existing entity type ignores it and behaves exactly as
-- before; only job and visit read it.
--
-- A null owner means "this row has no author", not "anybody's". Callers that have an author column always
-- pass it.
create or replace function private.can_manage_linked_record(
  target_organization_id uuid,
  target_entity_type text,
  target_entity_id uuid,
  target_record_owner uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select private.can_view_linked_entity(target_organization_id, target_entity_type, target_entity_id)
    and case target_entity_type
      when 'client' then private.has_permission(target_organization_id, 'customers.edit')
      when 'property' then private.has_permission(target_organization_id, 'property.manage')
      when 'request' then true
      when 'quote' then private.has_permission(target_organization_id, 'quotes.edit')
      -- Reaching the expense at all already proved this is the submitter or a manager; attaching the
      -- receipt to it needs nothing further.
      when 'job_expense' then true
      when 'job' then private.field_record_write_allowed(target_organization_id, target_record_owner)
      when 'visit' then private.field_record_write_allowed(target_organization_id, target_record_owner)
      else false
    end;
$$;

revoke all on function private.can_manage_linked_record(uuid, text, uuid, uuid) from public;
grant execute on function private.can_manage_linked_record(uuid, text, uuid, uuid) to authenticated;

-- The three-argument question is now the four-argument one asked without an author. Policies on rows that
-- have no author column keep calling this and are unchanged.
create or replace function private.can_manage_linked_entity(
  target_organization_id uuid,
  target_entity_type text,
  target_entity_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select private.can_manage_linked_record(
    target_organization_id, target_entity_type, target_entity_id, null
  );
$$;

-- A note_link has no author of its own; the note it points at does. Reading notes from a policy on
-- note_links would re-enter the notes policy, which reads note_links -- so this definer lookup, which skips
-- RLS, is what keeps the two tables from chasing each other.
create or replace function private.note_author(target_note_id uuid)
returns uuid
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select created_by from public.notes where id = target_note_id;
$$;

revoke all on function private.note_author(uuid) from public;
grant execute on function private.note_author(uuid) to authenticated;

create or replace function private.linked_entity_exists(
  target_organization_id uuid,
  target_entity_type text,
  target_entity_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select case target_entity_type
    when 'client' then exists (
      select 1 from public.clients
      where id = target_entity_id and organization_id = target_organization_id
    )
    when 'property' then exists (
      select 1 from public.properties
      where id = target_entity_id and organization_id = target_organization_id
    )
    when 'request' then exists (
      select 1 from public.requests
      where id = target_entity_id and organization_id = target_organization_id
    )
    when 'quote' then exists (
      select 1 from public.quotes
      where id = target_entity_id and organization_id = target_organization_id
    )
    when 'job_expense' then exists (
      select 1 from public.job_expenses
      where id = target_entity_id and organization_id = target_organization_id
    )
    when 'job' then exists (
      select 1 from public.jobs
      where id = target_entity_id and organization_id = target_organization_id
    )
    when 'visit' then exists (
      select 1 from public.job_visits
      where id = target_entity_id and organization_id = target_organization_id
    )
    else false
  end;
$$;

-- 5. Teach the policies who wrote the row ------------------------------------------------------------------

-- Only the rows that carry an author change. Behaviour for client, property, request, quote and job_expense
-- is identical either way, because their branches ignore the argument.
drop policy "permitted members can update notes" on public.notes;
create policy "permitted members can update notes"
on public.notes for update to authenticated
using (
  exists (
    select 1 from public.note_links as link
    where link.note_id = notes.id
      and private.can_manage_linked_record(
        link.organization_id, link.entity_type, link.entity_id, notes.created_by
      )
  )
)
with check (
  exists (
    select 1 from public.note_links as link
    where link.note_id = notes.id
      and private.can_manage_linked_record(
        link.organization_id, link.entity_type, link.entity_id, notes.created_by
      )
  )
);

drop policy "permitted members can delete notes" on public.notes;
create policy "permitted members can delete notes"
on public.notes for delete to authenticated
using (
  exists (
    select 1 from public.note_links as link
    where link.note_id = notes.id
      and private.can_manage_linked_record(
        link.organization_id, link.entity_type, link.entity_id, notes.created_by
      )
  )
);

drop policy "permitted members can create note links" on public.note_links;
create policy "permitted members can create note links"
on public.note_links for insert to authenticated
with check (
  private.can_manage_linked_record(
    organization_id, entity_type, entity_id, private.note_author(note_id)
  )
);

drop policy "permitted members can delete note links" on public.note_links;
create policy "permitted members can delete note links"
on public.note_links for delete to authenticated
using (
  private.can_manage_linked_record(
    organization_id, entity_type, entity_id, private.note_author(note_id)
  )
);

drop policy "permitted members can create tag assignments" on public.tag_assignments;
create policy "permitted members can create tag assignments"
on public.tag_assignments for insert to authenticated
with check (
  private.can_manage_linked_record(organization_id, entity_type, entity_id, created_by)
);

drop policy "permitted members can delete tag assignments" on public.tag_assignments;
create policy "permitted members can delete tag assignments"
on public.tag_assignments for delete to authenticated
using (
  private.can_manage_linked_record(organization_id, entity_type, entity_id, created_by)
);

drop policy "permitted members can create attachments" on public.attachments;
create policy "permitted members can create attachments"
on public.attachments for insert to authenticated
with check (
  private.can_manage_linked_record(organization_id, entity_type, entity_id, uploaded_by)
);

drop policy "permitted members can delete attachments" on public.attachments;
create policy "permitted members can delete attachments"
on public.attachments for delete to authenticated
using (
  private.can_manage_linked_record(organization_id, entity_type, entity_id, uploaded_by)
);

-- 6. Indexes behind the new predicates ---------------------------------------------------------------------

-- can_view_visit resolves a visit to its job by primary key, and can_view_job checks one job by primary key,
-- so both are single index probes and need nothing new. The record lists themselves read
-- (organization_id, entity_type, entity_id), which note_links_entity_idx, tag_assignments_entity_idx and
-- attachments_entity_idx already cover -- widening the entity_type domain does not change the access path.

comment on function private.can_view_job(uuid, uuid) is
  'Whether the caller may see this job. The single seam the assigned-work scope extends in 15a-2: when the '
  'Field role narrows to assigned jobs only, the assignment check is added here and every field record, '
  'note, tag and attachment inherits it.';

comment on function private.field_record_write_allowed(uuid, uuid) is
  'Jobber''s note rule: your own record is yours, and touching somebody else''s is what needs a permission. '
  'field_records.manage_team allows any, field_records.record allows the caller''s own. A null owner means '
  'the row has no author rather than that it belongs to everyone.';
