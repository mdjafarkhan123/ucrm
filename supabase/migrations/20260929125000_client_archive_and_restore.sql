-- Archive and restore a client, following Jobber's documented rules
-- (help.getjobber.com "Client Archiving", read 2026-09-28).
--
-- Jobber archives a client rather than deleting them: the record and its whole history stay, the client just
-- leaves the working list. It refuses to archive while the client still has live work -- requests and quotes
-- must be archived or converted, jobs closed, invoices paid or written off as bad debt -- and it automatically
-- brings an archived client back the moment new work is created for them or they submit a request.
--
-- Three pieces here:
--   private.client_open_work  -- the one answer to "what is still live for this client?"
--   public.archive_client / public.restore_client -- the two checked commands
--   private.unarchive_client_for_new_work -- the trigger that reverses an archive when work arrives
--
-- Both commands are SECURITY DEFINER and check `customers.archive` themselves, the way public.archive_quote
-- checks quotes.edit: archiving is its own permission, not the one the clients RLS write policy rides on.

CREATE OR REPLACE FUNCTION "private"."client_open_work"("target_organization_id" "uuid", "target_client_id" "uuid")
  RETURNS "jsonb"
  LANGUAGE "sql" STABLE SECURITY DEFINER
  SET "search_path" TO 'pg_catalog', 'public'
  AS $$
  select jsonb_build_object(
    'requests', requests.total,
    'quotes', quotes.total,
    'jobs', jobs.total,
    'invoices', invoices.total
  )
  from
    -- Anything not yet converted into real work and not archived is still waiting on the office.
    (
      select count(*)::bigint as total
      from public.requests as request
      where request.organization_id = target_organization_id
        and request.client_id = target_client_id
        and request.status not in ('converted', 'archived')
    ) as requests,
    (
      select count(*)::bigint as total
      from public.quotes as quote
      where quote.organization_id = target_organization_id
        and quote.client_id = target_client_id
        and quote.status not in ('converted', 'archived')
    ) as quotes,
    -- Jobs carry only two stored statuses; anything not closed is still work in hand.
    (
      select count(*)::bigint as total
      from public.jobs as job
      where job.organization_id = target_organization_id
        and job.client_id = target_client_id
        and job.status <> 'closed'
    ) as jobs,
    -- A bill is settled once it reads Paid, Bad debt or Voided, or once a later bill replaced it. Everything
    -- else -- including a draft that was never issued -- is money still open on this client.
    (
      select count(*)::bigint as total
      from public.invoices as invoice
      where invoice.organization_id = target_organization_id
        and invoice.client_id = target_client_id
        and invoice.replaced_at is null
        and private.invoice_status_label(invoice) not in ('paid', 'bad_debt', 'voided')
    ) as invoices;
$$;

ALTER FUNCTION "private"."client_open_work"("uuid", "uuid") OWNER TO "postgres";
REVOKE ALL ON FUNCTION "private"."client_open_work"("uuid", "uuid") FROM PUBLIC, "anon", "authenticated";

COMMENT ON FUNCTION "private"."client_open_work"("uuid", "uuid") IS
  'Counts the live requests, quotes, jobs and unsettled invoices a client still has. The one rule behind the archive guard, so the refusal message and the check can never disagree.';


CREATE OR REPLACE FUNCTION "public"."archive_client"("target_client_id" "uuid") RETURNS "jsonb"
  LANGUAGE "plpgsql" SECURITY DEFINER
  SET "search_path" TO 'pg_catalog', 'public'
  AS $$
declare
  client_row public.clients;
  open_work jsonb;
begin
  select * into client_row
  from public.clients
  where id = target_client_id and deleted_at is null
  for update;

  if client_row.id is null
     or not private.member_has_permission(
       client_row.organization_id, (select auth.uid()), 'customers.archive'
     ) then
    raise exception 'You do not have access to archive this client.' using errcode = 'insufficient_privilege';
  end if;

  if client_row.archived_at is not null then
    return jsonb_build_object('applied', false, 'archived', true, 'open_work', null);
  end if;

  open_work := private.client_open_work(client_row.organization_id, client_row.id);

  -- A refusal, not an error: the caller gets the counts so the office is told exactly what to finish first.
  if (open_work->>'requests')::bigint > 0
     or (open_work->>'quotes')::bigint > 0
     or (open_work->>'jobs')::bigint > 0
     or (open_work->>'invoices')::bigint > 0 then
    return jsonb_build_object('applied', false, 'archived', false, 'open_work', open_work);
  end if;

  update public.clients set archived_at = now() where id = client_row.id;

  return jsonb_build_object('applied', true, 'archived', true, 'open_work', null);
end;
$$;

ALTER FUNCTION "public"."archive_client"("uuid") OWNER TO "postgres";
REVOKE ALL ON FUNCTION "public"."archive_client"("uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."archive_client"("uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."archive_client"("uuid") TO "service_role";

COMMENT ON FUNCTION "public"."archive_client"("uuid") IS
  'Moves a client out of the working list, keeping the record and its history. Refuses while live work remains (Jobber''s rule), returning the counts rather than raising, so the caller can say what to close first. SECURITY DEFINER; self-checks customers.archive.';


CREATE OR REPLACE FUNCTION "public"."restore_client"("target_client_id" "uuid") RETURNS "jsonb"
  LANGUAGE "plpgsql" SECURITY DEFINER
  SET "search_path" TO 'pg_catalog', 'public'
  AS $$
declare
  client_row public.clients;
begin
  select * into client_row
  from public.clients
  where id = target_client_id and deleted_at is null
  for update;

  if client_row.id is null
     or not private.member_has_permission(
       client_row.organization_id, (select auth.uid()), 'customers.archive'
     ) then
    raise exception 'You do not have access to restore this client.' using errcode = 'insufficient_privilege';
  end if;

  if client_row.archived_at is null then
    return jsonb_build_object('applied', false, 'archived', false);
  end if;

  update public.clients set archived_at = null where id = client_row.id;

  return jsonb_build_object('applied', true, 'archived', false);
end;
$$;

ALTER FUNCTION "public"."restore_client"("uuid") OWNER TO "postgres";
REVOKE ALL ON FUNCTION "public"."restore_client"("uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."restore_client"("uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."restore_client"("uuid") TO "service_role";

COMMENT ON FUNCTION "public"."restore_client"("uuid") IS
  'Brings an archived client back into the working list. SECURITY DEFINER; self-checks customers.archive.';


-- New work always wins over an archive. Jobber unarchives a client automatically when work is created for
-- them or they submit a request, so nobody has to notice the archive first. Definer because the member
-- creating the work holds quotes.create or jobs.create, not necessarily any client-write permission.
CREATE OR REPLACE FUNCTION "private"."unarchive_client_for_new_work"() RETURNS "trigger"
  LANGUAGE "plpgsql" SECURITY DEFINER
  SET "search_path" TO 'pg_catalog', 'public'
  AS $$
begin
  update public.clients
  set archived_at = null
  where id = new.client_id and archived_at is not null;
  return new;
end;
$$;

ALTER FUNCTION "private"."unarchive_client_for_new_work"() OWNER TO "postgres";
REVOKE ALL ON FUNCTION "private"."unarchive_client_for_new_work"() FROM PUBLIC, "anon", "authenticated";

COMMENT ON FUNCTION "private"."unarchive_client_for_new_work"() IS
  'Reverses an archive the moment new work is created for the client, matching Jobber. Fires on requests, quotes, jobs and invoices.';

DROP TRIGGER IF EXISTS "requests_unarchive_client" ON "public"."requests";
CREATE TRIGGER "requests_unarchive_client"
  AFTER INSERT ON "public"."requests"
  FOR EACH ROW EXECUTE FUNCTION "private"."unarchive_client_for_new_work"();

DROP TRIGGER IF EXISTS "quotes_unarchive_client" ON "public"."quotes";
CREATE TRIGGER "quotes_unarchive_client"
  AFTER INSERT ON "public"."quotes"
  FOR EACH ROW EXECUTE FUNCTION "private"."unarchive_client_for_new_work"();

DROP TRIGGER IF EXISTS "jobs_unarchive_client" ON "public"."jobs";
CREATE TRIGGER "jobs_unarchive_client"
  AFTER INSERT ON "public"."jobs"
  FOR EACH ROW EXECUTE FUNCTION "private"."unarchive_client_for_new_work"();

DROP TRIGGER IF EXISTS "invoices_unarchive_client" ON "public"."invoices";
CREATE TRIGGER "invoices_unarchive_client"
  AFTER INSERT ON "public"."invoices"
  FOR EACH ROW EXECUTE FUNCTION "private"."unarchive_client_for_new_work"();
