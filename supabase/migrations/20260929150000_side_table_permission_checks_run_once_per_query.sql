-- The side tables a record page reads — its timeline, notes, attachments, tags, client contact details,
-- invoice history, and schedule events — still asked "may this member see this row?" once per returned row,
-- through helpers that re-read the caller's membership and permissions every time. Measured 2026-09-29 on
-- Raad LTD as the owner: one quote's 24 timeline rows took 31 ms / 1840 buffers, and the whole 683-row
-- timeline 552 ms — nearly all of it the per-row helper.
--
-- Same fix as the jobs, clients, requests, and files families: split each policy into a caller half with no
-- row argument, written as `(select …)` so Postgres runs it once per statement as an InitPlan, and a per-row
-- half that is at most one index probe. Visibility is unchanged — checked by fingerprinting every row each
-- Raad role (owner, admin, office, sales, finance, field) and a member of another organization can see,
-- before and after.
--
-- `organization_id = (select private.current_organization())` stands in for
-- `private.is_organization_member(organization_id)`: a user belongs to at most one organization
-- (organization_members_user_id_key), and current_organization() applies the same active-membership and
-- active-organization test.

-- ---------------------------------------------------------------------------------------------------------
-- 1. Linked-entity tables: activity_events, attachments, note_links, tag_assignments, notes
-- ---------------------------------------------------------------------------------------------------------

-- The record types the caller may see every row of, answered once per statement. A type is listed only when
-- can_view_linked_entity would say yes for every existing record of it, so the fast path below never shows
-- more than the per-row helper would. Anything narrower — an assigned-only field member, an expense the
-- member recorded themselves — is left to the per-row helper, exactly as before.
create or replace function private.current_full_view_entity_types()
returns text[]
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select array_remove(array[
    case when private.has_permission(caller.org, 'customers.view') then 'client' end,
    case when private.has_permission(caller.org, 'customers.view') then 'property' end,
    case
      when private.has_permission(caller.org, 'requests.view')
        and private.current_permission_scope('requests.view') <> 'assigned'
      then 'request'
    end,
    case when private.has_permission(caller.org, 'quotes.view') then 'quote' end,    case when caller.jobs_scope = 'all' then 'job' end,
    case when caller.jobs_scope = 'all' then 'visit' end,
    case
      when caller.jobs_scope = 'all' and private.has_permission(caller.org, 'expenses.manage_team')
      then 'job_expense'
    end
  ], null)
  from (
    select
      private.current_organization() as org,
      private.current_permission_scope('jobs.view') as jobs_scope
  ) as caller
  where caller.org is not null;
$$;

revoke all on function private.current_full_view_entity_types() from public, anon;
grant execute on function private.current_full_view_entity_types() to authenticated;

-- Per row, the fast path is an array test plus, for the types whose helper also checks that the record
-- exists, one index probe. Client, job, and request helpers never checked existence, so neither does this.
-- A row the fast path does not admit falls through to the original helper, unchanged.

drop policy "permitted members can view activity events" on public.activity_events;
create policy "permitted members can view activity events" on public.activity_events
  for select to authenticated
  using (
    (
      organization_id = (select private.current_organization())
      and entity_type = any ((select private.current_full_view_entity_types())::text[])
      and (
        entity_type in ('client', 'job', 'request')
        or private.linked_record_exists(organization_id, entity_type, entity_id)
      )
    )
    or private.can_view_linked_entity(organization_id, entity_type, entity_id)
  );

drop policy "permitted members can view attachments" on public.attachments;
create policy "permitted members can view attachments" on public.attachments
  for select to authenticated
  using (
    (
      organization_id = (select private.current_organization())
      and entity_type = any ((select private.current_full_view_entity_types())::text[])
      and (
        entity_type in ('client', 'job', 'request')
        or private.linked_record_exists(organization_id, entity_type, entity_id)
      )
    )
    or private.can_view_linked_entity(organization_id, entity_type, entity_id)
  );

drop policy "permitted members can view note links" on public.note_links;
create policy "permitted members can view note links" on public.note_links
  for select to authenticated
  using (
    (
      organization_id = (select private.current_organization())
      and entity_type = any ((select private.current_full_view_entity_types())::text[])
      and (
        entity_type in ('client', 'job', 'request')
        or private.linked_record_exists(organization_id, entity_type, entity_id)
      )
    )
    or private.can_view_linked_entity(organization_id, entity_type, entity_id)
  );

drop policy "permitted members can view tag assignments" on public.tag_assignments;
create policy "permitted members can view tag assignments" on public.tag_assignments
  for select to authenticated
  using (
    (
      organization_id = (select private.current_organization())
      and entity_type = any ((select private.current_full_view_entity_types())::text[])
      and (
        entity_type in ('client', 'job', 'request')
        or private.linked_record_exists(organization_id, entity_type, entity_id)
      )
    )
    or private.can_view_linked_entity(organization_id, entity_type, entity_id)
  );

-- A note is visible to its author, or through any link to a record the reader can see — the same link test
-- as note_links above.
drop policy "permitted members can view notes" on public.notes;
create policy "permitted members can view notes" on public.notes
  for select to authenticated
  using (
    (
      created_by = (select auth.uid())
      and organization_id = (select private.current_organization())
    )
    or exists (
      select 1
      from public.note_links link
      where link.note_id = notes.id
        and (
          (
            link.organization_id = (select private.current_organization())
            and link.entity_type = any ((select private.current_full_view_entity_types())::text[])
            and (
              link.entity_type in ('client', 'job', 'request')
              or private.linked_record_exists(link.organization_id, link.entity_type, link.entity_id)
            )
          )
          or private.can_view_linked_entity(link.organization_id, link.entity_type, link.entity_id)
        )
    )
  );

-- ---------------------------------------------------------------------------------------------------------
-- 2. Client detail tables: the clients policy's own shape, in place of can_view_client per row
-- ---------------------------------------------------------------------------------------------------------

drop policy "permitted members can view client contacts" on public.client_contacts;
create policy "permitted members can view client contacts" on public.client_contacts
  for select to authenticated
  using (
    organization_id = (select private.current_organization())
    and (
      (select private.has_permission((select private.current_organization()), 'customers.view'))
      or client_id in (select private.current_user_assigned_client_ids())
    )
  );

drop policy "permitted members can view client contact methods" on public.client_contact_methods;
create policy "permitted members can view client contact methods" on public.client_contact_methods
  for select to authenticated
  using (
    organization_id = (select private.current_organization())
    and (
      (select private.has_permission((select private.current_organization()), 'customers.view'))
      or client_id in (select private.current_user_assigned_client_ids())
    )
  );

drop policy "permitted members can view client communication preferences"
  on public.client_communication_preferences;
create policy "permitted members can view client communication preferences"
  on public.client_communication_preferences
  for select to authenticated
  using (
    organization_id = (select private.current_organization())
    and (
      (select private.has_permission((select private.current_organization()), 'customers.view'))
      or client_id in (select private.current_user_assigned_client_ids())
    )
  );

-- ---------------------------------------------------------------------------------------------------------
-- 3. Permission-only tables: every check is about the caller, none about the row
-- ---------------------------------------------------------------------------------------------------------

drop policy "permitted members can view opening balances" on public.client_opening_balances;
create policy "permitted members can view opening balances" on public.client_opening_balances
  for select to authenticated
  using (
    organization_id = (select private.current_organization())
    and (select private.has_permission((select private.current_organization()), 'invoices.view'))
  );

drop policy "permitted members can view invoice lines" on public.invoice_lines;
create policy "permitted members can view invoice lines" on public.invoice_lines
  for select to authenticated
  using (
    organization_id = (select private.current_organization())
    and (select private.has_permission((select private.current_organization()), 'invoices.view'))
  );

drop policy "permitted members can view invoice sources" on public.invoice_sources;
create policy "permitted members can view invoice sources" on public.invoice_sources
  for select to authenticated
  using (
    organization_id = (select private.current_organization())
    and (select private.has_permission((select private.current_organization()), 'invoices.view'))
  );

drop policy "permitted members can view client payments" on public.client_payment_events;
create policy "permitted members can view client payments" on public.client_payment_events
  for select to authenticated
  using (
    organization_id = (select private.current_organization())
    and (select private.has_permission((select private.current_organization()), 'invoices.view'))
    and (select private.has_permission((select private.current_organization()), 'invoices.view_price'))
  );

drop policy "permitted members can view invoice payment allocations"
  on public.invoice_payment_allocations;
create policy "permitted members can view invoice payment allocations"
  on public.invoice_payment_allocations
  for select to authenticated
  using (
    organization_id = (select private.current_organization())
    and (select private.has_permission((select private.current_organization()), 'invoices.view'))
    and (select private.has_permission((select private.current_organization()), 'invoices.view_price'))
  );

drop policy "permitted members can view invoice history" on public.invoice_events;
create policy "permitted members can view invoice history" on public.invoice_events
  for select to authenticated
  using (
    organization_id = (select private.current_organization())
    and (select private.has_permission((select private.current_organization()), 'invoices.view'))
    and (
      not price_sensitive
      or (select private.has_permission((select private.current_organization()), 'invoices.view_price'))
    )
  );

drop policy "permitted members can view quote deposit events" on public.quote_deposit_events;
create policy "permitted members can view quote deposit events" on public.quote_deposit_events
  for select to authenticated
  using (
    organization_id = (select private.current_organization())
    and (select private.has_permission((select private.current_organization()), 'quotes.view_price'))
  );

drop policy "permitted members can view quote schedule items" on public.quote_version_schedule_items;
create policy "permitted members can view quote schedule items" on public.quote_version_schedule_items
  for select to authenticated
  using (
    organization_id = (select private.current_organization())
    and (select private.has_permission((select private.current_organization()), 'quotes.view_price'))
  );

drop policy "members can view schedule events" on public.schedule_events;
create policy "members can view schedule events" on public.schedule_events
  for select to authenticated
  using (organization_id = (select private.current_organization()));
