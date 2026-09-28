-- Deleting a property deletes the work at that address, the way Jobber does
-- (help.getjobber.com "Properties", read 2026-09-28; recorded in .claude/skills/jobber/jobber-01-clients-properties.md § 2.2a).
--
-- Jobber: "Deleting this property also deletes related quotes and jobs, including associated estimates and
-- prices. This data also won't be included in your reports." It is not blocked and cannot be undone. Jafar
-- chose that behavior on 2026-09-28.
--
-- Where we stop short of a literal copy: money and customer paperwork. A job that was invoiced, a quote that
-- took a deposit or has a card checkout, and a quote that was emailed or texted to the customer are all held by
-- RESTRICT keys that protect payment and delivery history, so any of those refuses the delete and says which
-- record is in the way. Work at this address that is tied to work at a different address (a quote here that
-- became a job there, or the other way round) also refuses rather than reaching across to another address.
--
-- Pieces:
--   private.property_deletion_plan  -- the one answer to "what would go, and what stops it?"
--   public.property_delete_impact   -- read it for the confirmation (counts and blockers)
--   public.delete_property          -- now a checked hard delete built on the same plan
--   five append-only / history triggers learn to step aside while a property delete is running, the way
--   job_signatures already steps aside for an organization purge.

-- ---------------------------------------------------------------------------------------------------------
-- 1. The plan
-- ---------------------------------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION "private"."property_deletion_plan"("target_organization_id" "uuid", "target_property_id" "uuid")
  RETURNS "jsonb"
  LANGUAGE "plpgsql" STABLE SECURITY DEFINER
  SET "search_path" TO 'pg_catalog', 'public'
  AS $$
declare
  request_ids uuid[];
  quote_ids uuid[];
  job_ids uuid[];
  visit_ids uuid[];
  blockers jsonb;
begin
  select coalesce(array_agg(request.id order by request.id), '{}') into request_ids
  from public.requests as request
  where request.organization_id = target_organization_id and request.property_id = target_property_id;

  select coalesce(array_agg(quote.id order by quote.id), '{}') into quote_ids
  from public.quotes as quote
  where quote.organization_id = target_organization_id and quote.property_id = target_property_id;

  select coalesce(array_agg(job.id order by job.id), '{}') into job_ids
  from public.jobs as job
  where job.organization_id = target_organization_id and job.property_id = target_property_id;

  select coalesce(array_agg(visit.id order by visit.id), '{}') into visit_ids
  from public.job_visits as visit
  where visit.organization_id = target_organization_id and visit.job_id = any(job_ids);

  -- Each blocker names the record so the office knows exactly what is in the way. Ordered so the message reads
  -- the same every time.
  select coalesce(jsonb_agg(blocker order by blocker ->> 'sort'), '[]'::jsonb) into blockers
  from (
    select jsonb_build_object('sort', 'a' || lpad(job.job_number::text, 12, '0'), 'kind', 'job_invoiced',
      'label', 'Job #' || job.job_number || ' has been invoiced') as blocker
    from public.jobs as job
    where job.organization_id = target_organization_id and job.id = any(job_ids)
      and (
        -- Any piece of the job a bill was made from: the job itself, one of its visits, one of its invoice
        -- reminders, or one of its payment-schedule installments.
        exists (
          select 1 from public.invoice_sources as source
          where source.organization_id = target_organization_id
            and (
              source.job_id = job.id
              or source.visit_id in (
                select visit.id from public.job_visits as visit
                where visit.organization_id = target_organization_id and visit.job_id = job.id
              )
              or source.reminder_id in (
                select reminder.id from public.job_invoice_reminders as reminder
                where reminder.organization_id = target_organization_id and reminder.job_id = job.id
              )
              or source.installment_id in (
                select item.id from public.job_payment_schedule_items as item
                where item.organization_id = target_organization_id and item.job_id = job.id
              )
            )
        )
        or exists (
          select 1 from public.invoice_lines as line
          where line.organization_id = target_organization_id and line.source_job_id = job.id
        )
      )

    union all
    select jsonb_build_object('sort', 'b' || lpad(quote.quote_number::text, 12, '0'), 'kind', 'quote_deposit',
      'label', 'Quote #' || quote.quote_number || ' has a deposit payment')
    from public.quotes as quote
    where quote.organization_id = target_organization_id and quote.id = any(quote_ids)
      and (
        exists (
          select 1 from public.quote_deposit_events as deposit
          where deposit.organization_id = target_organization_id and deposit.quote_id = quote.id
        )
        or exists (
          select 1 from public.payment_stripe_checkouts as checkout
          where checkout.organization_id = target_organization_id and checkout.quote_id = quote.id
        )
      )

    union all
    select jsonb_build_object('sort', 'c' || lpad(quote.quote_number::text, 12, '0'), 'kind', 'quote_sent',
      'label', 'Quote #' || quote.quote_number || ' was sent to the customer')
    from public.quotes as quote
    where quote.organization_id = target_organization_id and quote.id = any(quote_ids)
      and exists (
        select 1 from public.communication_delivery_intents as intent
        where intent.organization_id = target_organization_id and intent.quote_id = quote.id
      )

    union all
    select jsonb_build_object('sort', 'd' || lpad(quote.quote_number::text, 12, '0'), 'kind', 'linked_elsewhere',
      'label', 'Quote #' || quote.quote_number || ' at another address was made from a request here')
    from public.quotes as quote
    where quote.organization_id = target_organization_id
      and quote.request_id = any(request_ids)
      and not quote.id = any(quote_ids)

    union all
    select jsonb_build_object('sort', 'e' || lpad(job.job_number::text, 12, '0'), 'kind', 'linked_elsewhere',
      'label', 'Job #' || job.job_number || ' at another address was made from a quote here')
    from public.jobs as job
    where job.organization_id = target_organization_id
      and job.quote_id = any(quote_ids)
      and not job.id = any(job_ids)
  ) as found;

  return jsonb_build_object(
    'request_ids', to_jsonb(request_ids),
    'quote_ids', to_jsonb(quote_ids),
    'job_ids', to_jsonb(job_ids),
    'visit_ids', to_jsonb(visit_ids),
    'blockers', blockers
  );
end;
$$;

ALTER FUNCTION "private"."property_deletion_plan"("uuid", "uuid") OWNER TO "postgres";
REVOKE ALL ON FUNCTION "private"."property_deletion_plan"("uuid", "uuid") FROM PUBLIC, "anon", "authenticated";

COMMENT ON FUNCTION "private"."property_deletion_plan"("uuid", "uuid") IS
  'The requests, quotes, jobs and visits a property delete would remove, and the records that refuse it. The one rule behind both the confirmation and the delete, so they can never disagree.';


-- ---------------------------------------------------------------------------------------------------------
-- 2. Access: the same check for the preview and the delete
-- ---------------------------------------------------------------------------------------------------------

-- property.manage on a client the caller can see, plus the right to edit each kind of work the delete would
-- destroy, so nobody removes quotes or jobs they could not change directly.
CREATE OR REPLACE FUNCTION "private"."assert_can_delete_property"("property_row" "public"."properties", "plan" "jsonb")
  RETURNS "void"
  LANGUAGE "plpgsql" STABLE SECURITY DEFINER
  SET "search_path" TO 'pg_catalog', 'public'
  AS $$
declare
  caller uuid := (select auth.uid());
begin
  if caller is null
    or not private.can_view_client(property_row.organization_id, property_row.client_id)
    or not private.member_has_permission(property_row.organization_id, caller, 'property.manage') then
    raise exception 'That property could not be found.' using errcode = 'P0002';
  end if;

  if jsonb_array_length(plan -> 'quote_ids') > 0
    and not private.member_has_permission(property_row.organization_id, caller, 'quotes.edit') then
    raise exception 'This property has quotes, and you do not have access to delete quotes.'
      using errcode = 'insufficient_privilege';
  end if;

  if jsonb_array_length(plan -> 'job_ids') > 0
    and not private.member_has_permission(property_row.organization_id, caller, 'jobs.edit') then
    raise exception 'This property has jobs, and you do not have access to delete jobs.'
      using errcode = 'insufficient_privilege';
  end if;
end;
$$;

ALTER FUNCTION "private"."assert_can_delete_property"("public"."properties", "jsonb") OWNER TO "postgres";
REVOKE ALL ON FUNCTION "private"."assert_can_delete_property"("public"."properties", "jsonb") FROM PUBLIC, "anon", "authenticated";


-- ---------------------------------------------------------------------------------------------------------
-- 3. The preview the confirmation reads
-- ---------------------------------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION "public"."property_delete_impact"("p_property_id" "uuid") RETURNS "jsonb"
  LANGUAGE "plpgsql" STABLE SECURITY DEFINER
  SET "search_path" TO 'pg_catalog', 'public'
  AS $$
declare
  property_row public.properties;
  plan jsonb;
begin
  select * into property_row from public.properties where id = p_property_id and deleted_at is null;
  if property_row.id is null then
    raise exception 'That property could not be found.' using errcode = 'P0002';
  end if;

  plan := private.property_deletion_plan(property_row.organization_id, property_row.id);
  perform private.assert_can_delete_property(property_row, plan);

  return jsonb_build_object(
    'requests', jsonb_array_length(plan -> 'request_ids'),
    'quotes', jsonb_array_length(plan -> 'quote_ids'),
    'jobs', jsonb_array_length(plan -> 'job_ids'),
    'visits', jsonb_array_length(plan -> 'visit_ids'),
    'blockers', (select coalesce(jsonb_agg(blocker ->> 'label'), '[]'::jsonb) from jsonb_array_elements(plan -> 'blockers') as blocker)
  );
end;
$$;

ALTER FUNCTION "public"."property_delete_impact"("uuid") OWNER TO "postgres";
REVOKE ALL ON FUNCTION "public"."property_delete_impact"("uuid") FROM PUBLIC, "anon";
GRANT EXECUTE ON FUNCTION "public"."property_delete_impact"("uuid") TO "authenticated", "service_role";


-- ---------------------------------------------------------------------------------------------------------
-- 4. History triggers step aside while a property delete runs
-- ---------------------------------------------------------------------------------------------------------

-- A transaction-local setting only public.delete_property turns on, and turns off again before it returns.
-- PostgREST cannot set arbitrary settings, so a caller cannot reach it except through that checked function.
CREATE OR REPLACE FUNCTION "private"."property_delete_in_progress"() RETURNS boolean
  LANGUAGE "sql" STABLE
  SET "search_path" TO 'pg_catalog', 'public'
  AS $$
  select coalesce(current_setting('app.property_delete_in_progress', true), '') = 'true';
$$;

ALTER FUNCTION "private"."property_delete_in_progress"() OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "private"."reject_published_quote_version_change"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'pg_catalog', 'public'
    AS $$
begin
  if tg_op = 'DELETE' and private.property_delete_in_progress() then
    return old;
  end if;
  if old.status = 'published' then
    raise exception 'Published quote versions cannot be changed or deleted.' using errcode = 'P0409';
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

CREATE OR REPLACE FUNCTION "private"."reject_published_quote_child_change"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'pg_catalog', 'public'
    AS $$
declare
  target_version_id uuid;
begin
  if tg_op = 'DELETE' and private.property_delete_in_progress() then
    return old;
  end if;
  target_version_id := case when tg_op = 'DELETE' then old.quote_version_id else new.quote_version_id end;
  if exists (
    select 1 from public.quote_versions
    where id = target_version_id and status = 'published'
  ) then
    raise exception 'Published quote version content cannot be changed or deleted.' using errcode = 'P0409';
  end if;
  if tg_op = 'UPDATE' and old.quote_version_id is distinct from new.quote_version_id and exists (
    select 1 from public.quote_versions
    where id = old.quote_version_id and status = 'published'
  ) then
    raise exception 'Published quote version content cannot be moved.' using errcode = 'P0409';
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

CREATE OR REPLACE FUNCTION "private"."job_costing_events_are_append_only"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'public'
    AS $$
begin
  if tg_op = 'DELETE' and private.property_delete_in_progress() then
    return old;
  end if;
  raise exception 'Job costing history cannot be changed or removed.' using errcode = 'insufficient_privilege';
end;
$$;

CREATE OR REPLACE FUNCTION "private"."job_signatures_are_append_only"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'public'
    AS $$
begin
  if tg_op = 'DELETE' and (
    current_setting('app.organization_purge_in_progress', true) = 'true'
    or private.property_delete_in_progress()
  ) then
    return old;
  end if;
  raise exception 'A collected signature cannot be changed or removed.'
    using errcode = 'insufficient_privilege';
end;
$$;

CREATE OR REPLACE FUNCTION "private"."file_links_protect_history"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'public'
    AS $$
begin
  if old.protected and not private.property_delete_in_progress() then
    raise exception 'This file is part of a document the customer already received and cannot be removed from it.'
      using errcode = '23503';
  end if;
  return old;
end;
$$;


-- ---------------------------------------------------------------------------------------------------------
-- 5. The delete
-- ---------------------------------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION "public"."delete_property"("p_property_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'public'
    AS $$
declare
  property_row public.properties;
  plan jsonb;
  org uuid;
  request_ids uuid[];
  quote_ids uuid[];
  job_ids uuid[];
  visit_ids uuid[];
  expense_ids uuid[];
  review_feedback_ids uuid[];
  touched_file_ids uuid[];
  next_property_id uuid;
begin
  select * into property_row
  from public.properties
  where id = p_property_id and deleted_at is null
  for update;
  if property_row.id is null then
    raise exception 'That property could not be found.' using errcode = 'P0002';
  end if;
  org := property_row.organization_id;

  plan := private.property_deletion_plan(org, property_row.id);
  perform private.assert_can_delete_property(property_row, plan);

  if jsonb_array_length(plan -> 'blockers') > 0 then
    raise exception 'This property cannot be deleted: %.',
      (select string_agg(blocker ->> 'label', '; ') from jsonb_array_elements(plan -> 'blockers') as blocker)
      using errcode = 'check_violation';
  end if;

  select array(select jsonb_array_elements_text(plan -> 'request_ids')::uuid) into request_ids;
  select array(select jsonb_array_elements_text(plan -> 'quote_ids')::uuid) into quote_ids;
  select array(select jsonb_array_elements_text(plan -> 'job_ids')::uuid) into job_ids;
  select array(select jsonb_array_elements_text(plan -> 'visit_ids')::uuid) into visit_ids;

  -- Lock the work so nothing converts, invoices or sends it between the plan and the delete; then re-read the
  -- plan under those locks in case something did in the moment before.
  perform 1 from public.requests where organization_id = org and id = any(request_ids) for update;
  perform 1 from public.quotes where organization_id = org and id = any(quote_ids) for update;
  perform 1 from public.jobs where organization_id = org and id = any(job_ids) for update;
  plan := private.property_deletion_plan(org, property_row.id);
  if jsonb_array_length(plan -> 'blockers') > 0
    or (plan -> 'request_ids') <> to_jsonb(request_ids)
    or (plan -> 'quote_ids') <> to_jsonb(quote_ids)
    or (plan -> 'job_ids') <> to_jsonb(job_ids) then
    raise exception 'The work at this property just changed. Reload and try again.' using errcode = 'P0409';
  end if;

  select coalesce(array_agg(id), '{}') into expense_ids
  from public.job_expenses where organization_id = org and job_id = any(job_ids);
  select coalesce(array_agg(feedback.id), '{}') into review_feedback_ids
  from public.review_feedback as feedback
  join public.review_requests as review on review.id = feedback.request_id
  where review.organization_id = org and review.job_id = any(job_ids);

  perform set_config('app.property_delete_in_progress', 'true', true);

  -- Jobs first: they hold RESTRICT keys to their quotes. A report photo also holds a RESTRICT key to its report
  -- section, which cascades from the same job, so photos go before the cascade could reach sections first.
  delete from public.job_report_photos where organization_id = org and job_id = any(job_ids);
  delete from public.jobs where organization_id = org and id = any(job_ids);
  -- Quotes next (they hold RESTRICT keys to their requests); their versions, lines, decisions and pipeline
  -- cards cascade.
  delete from public.quotes where organization_id = org and id = any(quote_ids);
  delete from public.requests where organization_id = org and id = any(request_ids);
  -- A pipeline card can sit on the address without a request or quote behind it.
  delete from public.opportunities where organization_id = org and property_id = property_row.id;

  -- Notes, tags, files and history point at records by type and id with no foreign key, so they are cleared
  -- here rather than left pointing at nothing.
  with gone(entity_type, entity_id) as (
    select 'property', property_row.id
    union all select 'request', unnest(request_ids)
    union all select 'quote', unnest(quote_ids)
    union all select 'job', unnest(job_ids)
    union all select 'visit', unnest(visit_ids)
    union all select 'job_expense', unnest(expense_ids)
  ),
  removed_links as (
    delete from public.note_links as link using gone
    where link.organization_id = org and link.entity_type = gone.entity_type and link.entity_id = gone.entity_id
    returning link.id, link.note_id
  )
  -- A note shared with a record that stays (the client, say) keeps living there; only notes left with no link
  -- at all go. The main statement still sees the links the CTE removed, so those are excluded by id.
  delete from public.notes as note
  where note.organization_id = org
    and note.id in (select note_id from removed_links)
    and not exists (
      select 1 from public.note_links as other
      where other.organization_id = org and other.note_id = note.id
        and other.id not in (select id from removed_links)
    );

  with gone(entity_type, entity_id) as (
    select 'property', property_row.id
    union all select 'request', unnest(request_ids)
    union all select 'quote', unnest(quote_ids)
    union all select 'job', unnest(job_ids)
    union all select 'visit', unnest(visit_ids)
    union all select 'job_expense', unnest(expense_ids)
  ),
  removed_file_links as (
    delete from public.file_links as link using gone
    where link.organization_id = org and link.entity_type = gone.entity_type and link.entity_id = gone.entity_id
    returning link.file_id
  ),
  removed_attachments as (
    delete from public.attachments as attachment using gone
    where attachment.organization_id = org
      and attachment.entity_type = gone.entity_type and attachment.entity_id = gone.entity_id
    returning attachment.file_id
  ),
  removed_tags as (
    delete from public.tag_assignments as assignment using gone
    where assignment.organization_id = org
      and assignment.entity_type = gone.entity_type and assignment.entity_id = gone.entity_id
  ),
  removed_activity as (
    delete from public.activity_events as event using gone
    where event.organization_id = org and event.entity_type = gone.entity_type and event.entity_id = gone.entity_id
  )
  select coalesce(array_agg(distinct file_id) filter (where file_id is not null), '{}') into touched_file_ids
  from (select file_id from removed_file_links union all select file_id from removed_attachments) as touched;

  -- A file left with no use anywhere goes to Trash, where it can still be restored until the purge; a file the
  -- office filed into a folder stays in the File Manager.
  update public.files as file
  set trashed_at = now(), trashed_by = (select auth.uid())
  where file.organization_id = org
    and file.id = any(touched_file_ids)
    and file.trashed_at is null
    and file.folder_id is null
    and not exists (select 1 from public.file_links where organization_id = org and file_id = file.id)
    and not exists (select 1 from public.attachments where organization_id = org and file_id = file.id)
    and not exists (select 1 from public.request_pricing_lines where organization_id = org and image_file_id = file.id)
    and not exists (select 1 from public.quote_version_lines where organization_id = org and image_file_id = file.id)
    and not exists (select 1 from public.job_line_items where organization_id = org and image_file_id = file.id)
    and not exists (select 1 from public.job_visit_line_items where organization_id = org and image_file_id = file.id)
    and not exists (select 1 from public.quote_version_attachments where organization_id = org and file_id = file.id)
    and not exists (select 1 from public.job_report_photos where organization_id = org and file_id = file.id)
    and not exists (select 1 from public.file_share_items where organization_id = org and file_id = file.id);

  -- Bell notifications about records that no longer exist would open a missing page.
  delete from public.team_notifications
  where organization_id = org
    and (
      (subject_type = 'quote' and subject_id = any(quote_ids))
      or (subject_type = 'job' and subject_id = any(job_ids))
      or (subject_type = 'request' and subject_id = any(request_ids))
      or (subject_type = 'review_feedback' and subject_id = any(review_feedback_ids))
    );

  delete from public.properties where id = property_row.id;

  perform set_config('app.property_delete_in_progress', 'false', true);

  -- A client with properties must keep exactly one primary (a deferred check), so a replacement is promoted in
  -- the same transaction.
  if property_row.is_primary then
    select id into next_property_id
    from public.properties
    where client_id = property_row.client_id and deleted_at is null
    order by created_at, id
    limit 1;

    if next_property_id is not null then
      update public.properties set is_primary = true where id = next_property_id;
    end if;
  end if;
end;
$$;

ALTER FUNCTION "public"."delete_property"("uuid") OWNER TO "postgres";
REVOKE ALL ON FUNCTION "public"."delete_property"("uuid") FROM PUBLIC, "anon";
GRANT EXECUTE ON FUNCTION "public"."delete_property"("uuid") TO "authenticated", "service_role";

COMMENT ON FUNCTION "public"."delete_property"("uuid") IS
  'Permanently deletes a property with the requests, quotes and jobs at it, as Jobber does. Refuses while any of that work was invoiced, took a deposit, was sent to the customer, or is tied to work at another address.';
