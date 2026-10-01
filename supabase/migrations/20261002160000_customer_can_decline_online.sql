-- Pipeline B8: the customer can decline a quote from its link.
--
-- Until now the customer's copy offered Approve and Request changes, and a "no" had to reach the office by
-- phone before anybody could record it. Housecall Pro puts a quiet Decline beside the other two, and it is
-- a long-standing Jobber request. This part adds it:
--
--   * The link's decision command accepts 'declined', with an optional pick from four plain reasons and an
--     optional message. Both are the customer's own words and are kept apart from the staff Lost reason,
--     which staff can still set afterwards.
--   * The quote's own status trigger already turns a declined quote's card Lost at its last sent value.
--   * The card's owner -- otherwise whoever sent the quote, otherwise the account owner -- gets one alert.
--     ("The office" in the plan: an account has no shared office inbox, so the owner stands for it.)
--   * A repeated tap answers "already answered" and changes nothing.
--
-- Growth: one quote and one link by key, the same as approving; the alert is one indexed membership read.
-- Sales Outcomes gains one primary-key join per row on a page of at most 51 rows.

-- ---------------------------------------------------------------------------------------------------------
-- 1. Where the customer's pick is kept: on their answer, beside their message.
-- ---------------------------------------------------------------------------------------------------------

alter table public.quote_decisions
  add column customer_reason text,
  add constraint quote_decisions_customer_reason_check check (
    customer_reason is null
    or (
      customer_reason in ('too_expensive', 'went_with_someone_else', 'no_longer_needed', 'other')
      and outcome = 'declined'
      and actor_kind = 'customer'
    )
  );

comment on column public.quote_decisions.customer_reason is
  'Pipeline B8. Why the customer said they declined, picked by them on the quote link: too_expensive, went_with_someone_else, no_longer_needed, or other. Optional, customer declines only, and never the same thing as the staff Lost reason on the opportunity''s outcome event.';

-- ---------------------------------------------------------------------------------------------------------
-- 2. The alert kind.
-- ---------------------------------------------------------------------------------------------------------

alter table public.team_notifications drop constraint team_notifications_kind_check;
alter table public.team_notifications add constraint team_notifications_kind_check check (kind = any (array[
  'website_inquiry.received', 'website_inquiry.customer_replied', 'invoice.paid_online',
  'invoice.online_payment_failed', 'invoice.online_overpayment', 'quote.deposit_paid_online',
  'quote.deposit_payment_failed', 'quote.deposit_overpaid', 'invoice.online_refund_failed',
  'invoice.payment_disputed', 'quote.deposit_refund_failed', 'quote.deposit_disputed',
  'review.private_feedback', 'quote.delivery_failed', 'quote.customer_declined'
]));

-- ---------------------------------------------------------------------------------------------------------
-- 3. The link's decision command, now with Decline. A new parameter changes the signature, so the old one
--    is dropped rather than left beside it as a second way in.
-- ---------------------------------------------------------------------------------------------------------

drop function public.submit_quote_customer_decision(bytea, text, text, jsonb, text, text, text, integer);

create function public.submit_quote_customer_decision(
  supplied_token_hash bytea,
  new_outcome text,
  customer_note text default null,
  supplied_evidence jsonb default '{}'::jsonb,
  signature_name text default null,
  signature_method text default null,
  signature_object_key text default null,
  signature_byte_size integer default null,
  customer_reason text default null
) returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $$
declare
  link_row public.quote_access_links;
  quote_row public.quotes;
  version_row public.quote_versions;
  current_decision public.quote_decisions;
  new_decision_id uuid;
  clean_note text;
  clean_signer text;
  clean_reason text := nullif(trim(coalesce(customer_reason, '')), '');
  card_owner uuid;
  sender uuid;
  recipient uuid;
  client_name text;
begin
  if new_outcome is null or new_outcome not in ('approved', 'changes_requested', 'declined') then
    raise exception 'That is not an answer this link can give.' using errcode = 'check_violation';
  end if;

  clean_note := nullif(trim(coalesce(customer_note, '')), '');
  if clean_note is not null and char_length(clean_note) > 1000 then
    raise exception 'That message is too long.' using errcode = 'check_violation';
  end if;

  if clean_reason is not null then
    if new_outcome <> 'declined' then
      raise exception 'Only a decline gives a reason.' using errcode = 'check_violation';
    end if;
    if clean_reason not in ('too_expensive', 'went_with_someone_else', 'no_longer_needed', 'other') then
      raise exception 'That is not one of the reasons on offer.' using errcode = 'check_violation';
    end if;
  end if;

  clean_signer := nullif(trim(coalesce(signature_name, '')), '');

  -- Nobody signs a request to change something, or a refusal.
  if clean_signer is not null and new_outcome <> 'approved' then
    raise exception 'Only an approval is signed.' using errcode = 'check_violation';
  end if;

  if clean_signer is not null then
    if char_length(clean_signer) > 120 then
      raise exception 'That name is too long.' using errcode = 'check_violation';
    end if;
    if signature_method is null or signature_method not in ('typed', 'drawn') then
      raise exception 'That is not a way to sign.' using errcode = 'check_violation';
    end if;
    if (signature_method = 'drawn') <> (signature_object_key is not null) then
      raise exception 'That signature is incomplete.' using errcode = 'check_violation';
    end if;
  elsif signature_object_key is not null then
    -- A drawing with nobody's name on it is not a signature.
    raise exception 'That signature is incomplete.' using errcode = 'check_violation';
  end if;

  if supplied_token_hash is null or octet_length(supplied_token_hash) <> 32 then
    return null;
  end if;

  select * into link_row from public.quote_access_links where token_hash = supplied_token_hash;
  if link_row.id is null then
    return null;
  end if;

  select * into quote_row from public.quotes where id = link_row.quote_id for update;

  select * into link_row from public.quote_access_links where id = link_row.id;
  if link_row.revoked_at is not null
     or (link_row.expires_at is not null and link_row.expires_at <= now()) then
    return null;
  end if;

  if quote_row.id is null
     or quote_row.status = 'archived'
     or quote_row.current_published_version_id is distinct from link_row.quote_version_id then
    return null;
  end if;

  select * into version_row from public.quote_versions where id = link_row.quote_version_id;
  if version_row.id is null or version_row.status <> 'published' then
    return null;
  end if;

  select * into current_decision
  from public.quote_decisions
  where organization_id = quote_row.organization_id
    and quote_id = quote_row.id
    and is_current;

  -- The same answer twice -- a double tap, a retry after a dropped connection -- is the first answer.
  if current_decision.id is not null
     and current_decision.outcome = new_outcome
     and current_decision.quote_version_id = version_row.id
     and current_decision.actor_kind = 'customer' then
    return jsonb_build_object(
      'quote_id', quote_row.id, 'status', quote_row.status, 'outcome', current_decision.outcome,
      'decided_at', current_decision.decided_at, 'already_answered', true
    );
  end if;

  if quote_row.status not in ('awaiting_response', 'changes_requested') then
    raise exception 'This quote has already been answered.' using errcode = 'P0409';
  end if;

  if new_outcome = 'changes_requested' and quote_row.status = 'changes_requested' then
    raise exception 'You have already asked for changes on this quote.' using errcode = 'P0409';
  end if;

  update public.quote_decisions
  set is_current = false
  where organization_id = quote_row.organization_id
    and quote_id = quote_row.id
    and is_current;

  insert into public.quote_decisions (
    organization_id, quote_id, quote_version_id, outcome, actor_kind, quote_access_link_id,
    method, note, evidence, customer_reason
  ) values (
    quote_row.organization_id, quote_row.id, version_row.id, new_outcome, 'customer', link_row.id,
    'online', clean_note, coalesce(supplied_evidence, '{}'::jsonb), clean_reason
  )
  returning id into new_decision_id;

  -- Same transaction as the answer, on purpose. A signature that could arrive a moment later is a
  -- signature that could fail to arrive at all.
  if clean_signer is not null then
    insert into public.quote_signatures (
      organization_id, quote_id, quote_version_id, quote_decision_id, signer_name, method,
      document_hash, image_object_key, image_byte_size, evidence
    ) values (
      quote_row.organization_id, quote_row.id, version_row.id, new_decision_id, clean_signer,
      signature_method, version_row.document_hash, signature_object_key, signature_byte_size,
      coalesce(supplied_evidence, '{}'::jsonb)
    );
  end if;

  -- Approving and declining are decisions, and the quote carries them. Asking for changes only hands the
  -- quote back. The status trigger turns the card Won or Lost from here.
  if new_outcome in ('approved', 'declined') then
    update public.quotes
    set status = new_outcome,
        decision = new_outcome,
        decided_at = now(),
        decision_method = 'online',
        decision_note = clean_note,
        decided_by = null
    where id = quote_row.id
    returning * into quote_row;
  else
    update public.quotes
    set status = new_outcome
    where id = quote_row.id
    returning * into quote_row;
  end if;

  insert into public.activity_events (
    organization_id, entity_type, entity_id, event_type, summary, actor_user_id, metadata
  ) values (
    quote_row.organization_id, 'quote', quote_row.id,
    'quote.' || new_outcome,
    case new_outcome
      when 'approved' then 'The client approved this quote'
      when 'declined' then 'The client declined this quote'
      else 'The client asked for changes'
    end
      || case when clean_note is null then ''
              else ': ' || left(clean_note, 240) || case when char_length(clean_note) > 240 then '…' else '' end
         end,
    null,
    jsonb_build_object(
      'version_number', version_row.version_number,
      'method', 'online',
      'signed', clean_signer is not null,
      'quote_access_link_id', link_row.id
    ) || case when clean_reason is null then '{}'::jsonb
              else jsonb_build_object('customer_reason', clean_reason) end
  );

  -- A "no" is news somebody has to hear. The card's owner is responsible for it; an unassigned card falls
  -- to whoever sent the quote, and failing that to the account owner -- the same order a failed delivery
  -- uses, so the two alerts land with the same person.
  if new_outcome = 'declined' then
    select opportunity.owner_user_id into card_owner
    from public.opportunities as opportunity
    where opportunity.organization_id = quote_row.organization_id
      and opportunity.quote_id = quote_row.id;

    -- Whoever last emailed this quote, through the quote's own send-history index. A quote only ever
    -- marked sent outside UCRM has no email, so its author stands in.
    select coalesce(
      (
        select intent.created_by
        from public.communication_delivery_intents as intent
        where intent.organization_id = quote_row.organization_id
          and intent.quote_id = quote_row.id
        order by intent.created_at desc, intent.id desc
        limit 1
      ),
      quote_row.created_by
    ) into sender;

    select membership.user_id into recipient
    from public.organization_members as membership
    where membership.organization_id = quote_row.organization_id
      and membership.status = 'active'
      and (membership.user_id in (card_owner, sender) or membership.role = 'owner')
    order by
      (membership.user_id is not distinct from card_owner) desc,
      (membership.user_id is not distinct from sender) desc,
      membership.user_id
    limit 1;

    if recipient is not null then
      select nullif(btrim(client.display_name), '') into client_name
      from public.clients as client
      where client.organization_id = quote_row.organization_id and client.id = quote_row.client_id;

      insert into public.team_notifications (
        organization_id, user_id, kind, subject_type, subject_id, title, body, source_key, email_state
      ) values (
        quote_row.organization_id, recipient, 'quote.customer_declined', 'quote', quote_row.id,
        left(coalesce(client_name, 'The customer') || ' declined quote #' || quote_row.quote_number, 200),
        left(
          case clean_reason
            when 'too_expensive' then 'They said it was too expensive.'
            when 'went_with_someone_else' then 'They said they went with someone else.'
            when 'no_longer_needed' then 'They said they are no longer doing the work.'
            when 'other' then 'They picked "Other".'
            else 'They did not say why.'
          end
          || case when clean_note is null then '' else ' "' || clean_note || '"' end,
          1000
        ),
        'quote_customer_declined:' || new_decision_id,
        'not_needed'
      )
      on conflict (organization_id, user_id, source_key) do nothing;
    end if;
  end if;

  return jsonb_build_object(
    'quote_id', quote_row.id, 'status', quote_row.status, 'outcome', new_outcome,
    'decided_at', now(), 'signed', clean_signer is not null, 'already_answered', false
  );
end;
$$;

comment on function public.submit_quote_customer_decision(bytea, text, text, jsonb, text, text, text, integer, text) is
  'The customer''s answer through their quote link: approved, changes_requested, or declined (Pipeline B8). Service role only; the token hash decides which quote. A decline may carry the customer''s own reason pick and message, and alerts the card''s owner, else the sender, else the account owner.';

revoke all on function public.submit_quote_customer_decision(bytea, text, text, jsonb, text, text, text, integer, text) from public, anon, authenticated;
grant execute on function public.submit_quote_customer_decision(bytea, text, text, jsonb, text, text, text, integer, text) to service_role;

-- ---------------------------------------------------------------------------------------------------------
-- 4. Sales Outcomes shows the customer's pick beside their message. A new column means a new shape, so the
--    function is dropped and granted again; everything else is unchanged from 20261002130000.
-- ---------------------------------------------------------------------------------------------------------

drop function public.pipeline_outcome_page(uuid, text, integer, text, text, timestamptz, timestamptz, text, integer, timestamptz, numeric, text, uuid);

CREATE OR REPLACE FUNCTION "public"."pipeline_outcome_page"("target_organization_id" "uuid", "outcome_type" "text", "page_limit" integer DEFAULT 25, "sort_key" "text" DEFAULT 'outcome_at'::"text", "sort_direction" "text" DEFAULT 'desc'::"text", "outcome_from" timestamp with time zone DEFAULT NULL::timestamp with time zone, "outcome_to" timestamp with time zone DEFAULT NULL::timestamp with time zone, "cursor_sort_key" "text" DEFAULT NULL::"text", "cursor_phase" integer DEFAULT NULL::integer, "cursor_timestamp" timestamp with time zone DEFAULT NULL::timestamp with time zone, "cursor_numeric" numeric DEFAULT NULL::numeric, "cursor_text" "text" DEFAULT NULL::"text", "cursor_id" "uuid" DEFAULT NULL::"uuid") RETURNS TABLE("id" "uuid", "title" "text", "outcome" "text", "created_at" timestamp with time zone, "outcome_at" timestamp with time zone, "client_id" "uuid", "client_display_name" "text", "client_company_name" "text", "estimated_value" numeric, "source_kind" "text", "quote_id" "uuid", "quote_number" integer, "lost_reason" "text", "lost_note" "text", "customer_declined" boolean, "customer_message" "text", "customer_reason" "text")
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'public'
    AS $_$
declare
  caller_id uuid := (select auth.uid());
  caller_sees_money boolean;
  caller_sees_clients boolean;
  resolved_limit integer;
  select_body text;
  filters text := '';
  keyset text;
  ordering text;
  sort_expr text;
  phase integer;
  fetched integer;
begin
  if target_organization_id is null
     or target_organization_id not in (select private.permitted_organizations('pipeline.view')) then
    raise exception 'You do not have access to this sales pipeline.'
      using errcode = 'insufficient_privilege';
  end if;

  if outcome_type not in ('won', 'lost', 'direct_job') then
    raise exception 'That is not a Sales Outcomes type.' using errcode = 'invalid_parameter_value';
  end if;
  if sort_key not in ('title', 'client', 'created', 'outcome_at', 'total')
     or sort_direction not in ('asc', 'desc') then
    raise exception 'That is not a way to sort Sales Outcomes.' using errcode = 'invalid_parameter_value';
  end if;

  -- A cursor is only valid for the order it was cut from. Paging on with a cursor from a different sort
  -- would silently skip and repeat rows.
  if cursor_sort_key is not null and cursor_sort_key <> sort_key then
    raise exception 'That page marker belongs to a different order.'
      using errcode = 'invalid_parameter_value';
  end if;

  resolved_limit := least(greatest(coalesce(page_limit, 25), 1), 51);

  caller_sees_money :=
    private.member_has_permission(target_organization_id, caller_id, 'pipeline.view_value');
  caller_sees_clients :=
    private.member_has_permission(target_organization_id, caller_id, 'customers.view');

  if sort_key = 'total' and not caller_sees_money then
    raise exception 'You do not have access to values on this sales pipeline.'
      using errcode = 'insufficient_privilege';
  end if;
  if sort_key = 'client' and not caller_sees_clients then
    raise exception 'You do not have access to client names on this sales pipeline.'
      using errcode = 'insufficient_privilege';
  end if;

  select_body := format($body$
    select
      opportunity.id,
      opportunity.title,
      opportunity.outcome,
      opportunity.created_at,
      opportunity.outcome_at,
      opportunity.client_id,
      case when client_visible.allowed then client.display_name end,
      case when client_visible.allowed then client.company_name end,
      case when %L::boolean then opportunity.estimated_value end,
      case
        when opportunity.job_id is not null then 'job'
        when opportunity.quote_id is not null then 'quote'
        else 'request'
      end,
      opportunity.quote_id,
      quote.quote_number,
      outcome_event.reason,
      outcome_event.note,
      -- The customer said no, as opposed to the team giving up on it. Their words stay beside the reason.
      opportunity.outcome = 'lost' and quote.decision is not distinct from 'declined',
      case when opportunity.outcome = 'lost' and quote.decision = 'declined' then quote.decision_note end,
      -- What they picked when they declined online. A decline staff recorded by phone has none.
      case when opportunity.outcome = 'lost' and quote.decision = 'declined' then customer_answer.customer_reason end
    from public.opportunities as opportunity
    cross join lateral (
      select
        %L::boolean
        or private.can_view_client(opportunity.organization_id, opportunity.client_id) as allowed
    ) as client_visible
    left join public.clients as client
      on client.id = opportunity.client_id
     and client.organization_id = opportunity.organization_id
    left join public.quotes as quote
      on quote.id = opportunity.quote_id
     and quote.organization_id = opportunity.organization_id
    left join public.quote_decisions as customer_answer
      on customer_answer.organization_id = quote.organization_id
     and customer_answer.quote_id = quote.id
     and customer_answer.is_current
    left join public.opportunity_outcome_events as outcome_event
      on outcome_event.id = opportunity.current_outcome_event_id
     and outcome_event.organization_id = opportunity.organization_id
     and outcome_event.event_type = 'lost'
    where opportunity.organization_id = %L
      and opportunity.outcome_kind = %L
  $body$, caller_sees_money, caller_sees_clients, target_organization_id, outcome_type);

  if outcome_from is not null then
    filters := filters || format(' and opportunity.outcome_at >= %L', outcome_from);
  end if;
  if outcome_to is not null then
    filters := filters || format(' and opportunity.outcome_at < %L', outcome_to);
  end if;

  -- Total pages in two phases, the same way the board's value sort does: a null estimate cannot sit in a
  -- keyset row comparison, so the estimated rows and the unestimated ones are two separate ordered reads
  -- rather than one NULLS LAST that a cursor could not resume.
  if sort_key = 'total' then
    phase := coalesce(cursor_phase, 1);
    if phase not in (1, 2) then
      raise exception 'That page marker belongs to a different order.'
        using errcode = 'invalid_parameter_value';
    end if;

    if phase = 1 then
      if sort_direction = 'desc' then
        ordering := ' order by opportunity.estimated_value desc, opportunity.id desc';
        keyset := case
          when cursor_id is null then ''
          else format(
            ' and (opportunity.estimated_value, opportunity.id) < (%1$L::numeric, %2$L::uuid)',
            cursor_numeric, cursor_id)
        end;
      else
        ordering := ' order by opportunity.estimated_value asc, opportunity.id asc';
        keyset := case
          when cursor_id is null then ''
          else format(
            ' and (opportunity.estimated_value, opportunity.id) > (%1$L::numeric, %2$L::uuid)',
            cursor_numeric, cursor_id)
        end;
      end if;

      return query execute select_body || filters
        || ' and opportunity.estimated_value is not null' || keyset || ordering
        || format(' limit %s', resolved_limit);
      get diagnostics fetched = row_count;

      if fetched < resolved_limit then
        return query execute select_body || filters
          || ' and opportunity.estimated_value is null'
          || ' order by opportunity.id asc'
          || format(' limit %s', resolved_limit - fetched);
      end if;
      return;
    end if;

    return query execute select_body || filters
      || ' and opportunity.estimated_value is null'
      || case when cursor_id is null then ''
              else format(' and opportunity.id > %L::uuid', cursor_id) end
      || ' order by opportunity.id asc'
      || format(' limit %s', resolved_limit);
    return;
  end if;

  -- Every other sort is a single ordered read. Title, Created and Outcome date are never null; Client can
  -- be null only when the backing client row itself has been removed, which NULLS LAST is enough for --
  -- this is a report column, not money, and that edge is rare enough not to earn Total's two-phase split.
  sort_expr := case sort_key
    when 'title' then 'opportunity.title'
    when 'client' then 'client.display_name'
    when 'created' then 'opportunity.created_at'
    else 'opportunity.outcome_at'
  end;

  if sort_key in ('title', 'client') then
    if sort_direction = 'desc' then
      ordering := format(' order by %1$s desc nulls last, opportunity.id desc', sort_expr);
      keyset := case
        when cursor_id is null then ''
        else format(' and (%1$s, opportunity.id) < (%2$L::text, %3$L::uuid)', sort_expr, cursor_text, cursor_id)
      end;
    else
      ordering := format(' order by %1$s asc nulls last, opportunity.id asc', sort_expr);
      keyset := case
        when cursor_id is null then ''
        else format(' and (%1$s, opportunity.id) > (%2$L::text, %3$L::uuid)', sort_expr, cursor_text, cursor_id)
      end;
    end if;
  else
    if sort_direction = 'desc' then
      ordering := format(' order by %1$s desc, opportunity.id desc', sort_expr);
      keyset := case
        when cursor_id is null then ''
        else format(
          ' and (%1$s, opportunity.id) < (%2$L::timestamptz, %3$L::uuid)', sort_expr, cursor_timestamp, cursor_id)
      end;
    else
      ordering := format(' order by %1$s asc, opportunity.id asc', sort_expr);
      keyset := case
        when cursor_id is null then ''
        else format(
          ' and (%1$s, opportunity.id) > (%2$L::timestamptz, %3$L::uuid)', sort_expr, cursor_timestamp, cursor_id)
      end;
    end if;
  end if;

  return query execute select_body || filters || keyset || ordering
    || format(' limit %s', resolved_limit);
end;
$_$;

revoke all on function public.pipeline_outcome_page(uuid, text, integer, text, text, timestamptz, timestamptz, text, integer, timestamptz, numeric, text, uuid) from public, anon;
grant execute on function public.pipeline_outcome_page(uuid, text, integer, text, text, timestamptz, timestamptz, text, integer, timestamptz, numeric, text, uuid) to authenticated, service_role;

revoke all on function public.pipeline_outcome_page(uuid, text, integer, text, text, timestamptz, timestamptz, text, integer, timestamptz, numeric, text, uuid) from public, anon;
grant execute on function public.pipeline_outcome_page(uuid, text, integer, text, text, timestamptz, timestamptz, text, integer, timestamptz, numeric, text, uuid) to authenticated, service_role;
