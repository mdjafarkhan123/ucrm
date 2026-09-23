-- Marketing M5a: delivery truth.
--
-- M4 sends and projects delivery outcomes; this stage records the rest of what really happens to one
-- recipient's email so M5b (attribution) and M5c (results UI) have facts to read. Approved plan:
-- docs/marketing-first-release-plan.md §3 M5.
--
--   1. Recipient timestamps: delivered, first opened, first clicked, unsubscribed.
--   2. The provider_message_id index every SES event lookup and reply match needs (M4 left it out).
--   3. A recipient-bound call-to-action link, service-role only because every row is a credential -- the same
--      arrangement as client_marketing_unsubscribe_links.
--   4. Unsubscribe links remember the campaign recipient they were issued for, so the recipient shows
--      Unsubscribed on that campaign.
--   5. SES Open and Click events project onto the recipient.
--   6. An inbound reply to a Marketing message carries that campaign as its origin.

-- ---------------------------------------------------------------------------------------------------
-- 1-2. Recipient timestamps and the provider message lookup
-- ---------------------------------------------------------------------------------------------------

alter table "public"."marketing_campaign_recipients"
    add column if not exists "delivered_at" timestamptz,
    add column if not exists "first_opened_at" timestamptz,
    add column if not exists "first_clicked_at" timestamptz,
    add column if not exists "unsubscribed_at" timestamptz;

-- SES message ids are globally unique. Serves the event projector's per-event lookup and the reply trigger.
create unique index if not exists "marketing_campaign_recipients_provider_message_idx"
    on "public"."marketing_campaign_recipients" using btree ("provider_message_id")
    where ("provider_message_id" is not null);

-- ---------------------------------------------------------------------------------------------------
-- 3. Recipient-bound call-to-action links
-- ---------------------------------------------------------------------------------------------------

create table if not exists "public"."marketing_campaign_cta_links" (
    "id" uuid not null default gen_random_uuid(),
    "organization_id" uuid not null,
    "campaign_id" uuid not null,
    "marketing_campaign_recipient_id" uuid not null,
    "token_hash" bytea not null,
    "issued_at" timestamptz not null default now(),
    constraint "marketing_campaign_cta_links_pkey" primary key ("id"),
    constraint "marketing_campaign_cta_links_recipient_key" unique ("marketing_campaign_recipient_id"),
    constraint "marketing_campaign_cta_links_token_hash_key" unique ("token_hash"),
    constraint "marketing_campaign_cta_links_token_hash_check" check (octet_length("token_hash") = 32),
    constraint "marketing_campaign_cta_links_organization_id_fkey"
        foreign key ("organization_id") references "public"."organizations"("id") on delete cascade,
    constraint "marketing_campaign_cta_links_campaign_fkey"
        foreign key ("organization_id", "campaign_id")
        references "public"."marketing_campaigns"("organization_id", "id") on delete cascade,
    constraint "marketing_campaign_cta_links_recipient_fkey"
        foreign key ("marketing_campaign_recipient_id")
        references "public"."marketing_campaign_recipients"("id") on delete cascade
);

create index if not exists "marketing_campaign_cta_links_campaign_idx"
    on "public"."marketing_campaign_cta_links" using btree ("organization_id", "campaign_id");

comment on table "public"."marketing_campaign_cta_links" is
    'One recipient-bound call-to-action link per sent Marketing email. Stores only the token hash; the raw token exists solely in the form URL placed in the email. A form submitted through it is the campaign''s direct tracked result (M5b). Service role only -- every row is a credential.';

alter table "public"."marketing_campaign_cta_links" enable row level security;
revoke all on table "public"."marketing_campaign_cta_links" from anon, authenticated;

-- Written by the dispatcher while it holds the recipient's claim, before the email leaves. A retried send
-- replaces the hash: the earlier email never reached SES, so its token was never in anyone's inbox.
create or replace function "public"."issue_marketing_campaign_cta_link"(
    "target_recipient_id" uuid,
    "target_claim_token" uuid,
    "supplied_token_hash" bytea
) returns void
    language plpgsql security definer
    set search_path to 'pg_catalog', 'public'
    as $$
declare
    recipient public.marketing_campaign_recipients;
begin
    if supplied_token_hash is null or octet_length(supplied_token_hash) <> 32 then
        raise exception 'A call-to-action link needs a full-length token.' using errcode = 'check_violation';
    end if;

    select * into recipient
    from public.marketing_campaign_recipients
    where id = target_recipient_id and status = 'checking' and claim_token = target_claim_token;

    if recipient.id is null then
        raise exception 'That recipient is not claimed by this worker.'
            using errcode = 'object_not_in_prerequisite_state';
    end if;

    insert into public.marketing_campaign_cta_links (
        organization_id, campaign_id, marketing_campaign_recipient_id, token_hash
    ) values (
        recipient.organization_id, recipient.campaign_id, recipient.id, supplied_token_hash
    )
    on conflict ("marketing_campaign_recipient_id")
    do update set token_hash = excluded.token_hash, issued_at = now();
end;
$$;

revoke all on function "public"."issue_marketing_campaign_cta_link"(uuid, uuid, bytea)
    from public, anon, authenticated;
grant execute on function "public"."issue_marketing_campaign_cta_link"(uuid, uuid, bytea) to service_role;

-- ---------------------------------------------------------------------------------------------------
-- 4. Unsubscribe links remember their campaign recipient
-- ---------------------------------------------------------------------------------------------------

alter table "public"."client_marketing_unsubscribe_links"
    add column if not exists "marketing_campaign_recipient_id" uuid;

do $$
begin
    if not exists (
        select 1 from pg_constraint where conname = 'client_marketing_unsubscribe_links_campaign_recipient_fkey'
    ) then
        alter table "public"."client_marketing_unsubscribe_links"
            add constraint "client_marketing_unsubscribe_links_campaign_recipient_fkey"
            foreign key ("marketing_campaign_recipient_id")
            references "public"."marketing_campaign_recipients"("id") on delete set null;
    end if;
end
$$;

create index if not exists "client_marketing_unsubscribe_links_campaign_recipient_idx"
    on "public"."client_marketing_unsubscribe_links" using btree ("marketing_campaign_recipient_id")
    where ("marketing_campaign_recipient_id" is not null);

-- The three-argument form is replaced, not overloaded, so no caller can keep issuing campaign-less links.
drop function if exists "public"."issue_client_marketing_unsubscribe_link"(uuid, uuid, bytea);

create or replace function "public"."issue_client_marketing_unsubscribe_link"(
    "target_organization_id" uuid,
    "target_client_contact_method_id" uuid,
    "supplied_token_hash" bytea,
    "target_marketing_campaign_recipient_id" uuid default null
) returns jsonb
    language plpgsql security definer
    set search_path to 'pg_catalog', 'public'
    as $$
declare
  method_row public.client_contact_methods;
  link_row public.client_marketing_unsubscribe_links;
begin
  if supplied_token_hash is null or octet_length(supplied_token_hash) <> 32 then
    raise exception 'An unsubscribe link needs a full-length token.' using errcode = 'check_violation';
  end if;

  select * into method_row
  from public.client_contact_methods
  where organization_id = target_organization_id
    and id = target_client_contact_method_id
    and kind = 'email';

  if method_row.id is null then
    raise exception 'That email address is not on this organization.' using errcode = 'check_violation';
  end if;

  -- A campaign recipient must be the same organization's row for the same address, so a link can never
  -- mark someone else's result.
  if target_marketing_campaign_recipient_id is not null and not exists (
    select 1 from public.marketing_campaign_recipients
    where id = target_marketing_campaign_recipient_id
      and organization_id = method_row.organization_id
      and client_contact_method_id = method_row.id
  ) then
    raise exception 'That campaign recipient does not match this email address.' using errcode = 'check_violation';
  end if;

  insert into public.client_marketing_unsubscribe_links (
    organization_id, client_id, client_contact_method_id, token_hash, marketing_campaign_recipient_id
  ) values (
    method_row.organization_id, method_row.client_id, method_row.id, supplied_token_hash,
    target_marketing_campaign_recipient_id
  )
  returning * into link_row;

  return jsonb_build_object(
    'unsubscribe_link_id', link_row.id,
    'client_id', link_row.client_id,
    'client_contact_method_id', link_row.client_contact_method_id,
    'issued_at', link_row.issued_at
  );
end;
$$;

revoke all on function "public"."issue_client_marketing_unsubscribe_link"(uuid, uuid, bytea, uuid)
    from public, anon, authenticated;
grant execute on function "public"."issue_client_marketing_unsubscribe_link"(uuid, uuid, bytea, uuid)
    to service_role;

create or replace function "public"."record_client_marketing_unsubscribe"(
    "supplied_token_hash" bytea,
    "supplied_evidence" jsonb default '{}'::jsonb
) returns jsonb
    language plpgsql security definer
    set search_path to 'pg_catalog', 'public'
    as $$
declare
  link_row public.client_marketing_unsubscribe_links;
  method_value text;
  business_name text;
  current_state text;
begin
  if supplied_token_hash is null or octet_length(supplied_token_hash) <> 32 then
    return null;
  end if;

  if supplied_evidence is null or jsonb_typeof(supplied_evidence) <> 'object' then
    raise exception 'Unsubscribe evidence must be an object.' using errcode = 'check_violation';
  end if;

  select * into link_row
  from public.client_marketing_unsubscribe_links
  where token_hash = supplied_token_hash;

  if link_row.id is null then
    return null;
  end if;

  select method.value into method_value
  from public.client_contact_methods as method
  where method.organization_id = link_row.organization_id
    and method.id = link_row.client_contact_method_id;

  if method_value is null then
    return null;
  end if;

  select organization.name into business_name
  from public.organizations as organization
  where organization.id = link_row.organization_id;

  -- Locks the projected row for this address where one exists, so a repeat click cannot read a stale
  -- "still opted in" and write a second event. With no row yet there is nothing to lock, and two clicks
  -- arriving in the same instant can both insert; that costs one extra evidence row and reaches the same
  -- state, which is the right trade for an append-only ledger.
  select state into current_state
  from public.client_marketing_consent_state
  where organization_id = link_row.organization_id
    and client_contact_method_id = link_row.client_contact_method_id
  for update;

  if coalesce(current_state, 'unknown') <> 'opted_out' then
    insert into public.client_marketing_consent_events (
      organization_id, client_id, client_contact_method_id, event_kind, source, source_event_key,
      disclosure, evidence, occurred_at, created_by
    ) values (
      link_row.organization_id,
      link_row.client_id,
      link_row.client_contact_method_id,
      'opt_out',
      'unsubscribe',
      link_row.id::text || ':' || gen_random_uuid()::text,
      null,
      supplied_evidence || jsonb_build_object(
        'channel', 'unsubscribe_link',
        'unsubscribe_link_id', link_row.id,
        'marketing_campaign_recipient_id', link_row.marketing_campaign_recipient_id
      ),
      now(),
      null
    );
  end if;

  -- The campaign this link came from records the unsubscribe as that recipient's result. Only an email
  -- that actually left can be unsubscribed from; a bounce or complaint is the stronger fact and stays.
  if link_row.marketing_campaign_recipient_id is not null then
    update public.marketing_campaign_recipients
    set unsubscribed_at = coalesce(unsubscribed_at, now()),
        status = case
            when status in ('submitted', 'delivered', 'submission_unknown') then 'unsubscribed'
            else status
        end,
        updated_at = now()
    where id = link_row.marketing_campaign_recipient_id
      and organization_id = link_row.organization_id
      and unsubscribed_at is null;
  end if;

  return jsonb_build_object(
    'business_name', business_name,
    'email', method_value,
    'already_unsubscribed', coalesce(current_state, 'unknown') = 'opted_out'
  );
end;
$$;

-- ---------------------------------------------------------------------------------------------------
-- 5. SES Open and Click events
-- ---------------------------------------------------------------------------------------------------

-- The event key is ses:<messageId>:<eventType>, so only a message's first Open and first Click are stored:
-- exactly the "first opened" and "first clicked" facts results need, and a repeat open costs nothing.
alter table "public"."marketing_campaign_recipient_events"
    drop constraint if exists "marketing_campaign_recipient_events_normalized_kind_check";

alter table "public"."marketing_campaign_recipient_events"
    add constraint "marketing_campaign_recipient_events_normalized_kind_check"
    check ("normalized_kind" is null or "normalized_kind" = any (array[
        'delivered'::text, 'hard_bounce'::text, 'soft_bounce'::text, 'complaint'::text,
        'rejected'::text, 'delayed'::text, 'sent'::text, 'open'::text, 'click'::text, 'other'::text
    ]));

create or replace function "public"."project_marketing_campaign_recipient_events"(
    "batch_size" integer default 200
) returns integer
    language plpgsql security definer
    set search_path to 'pg_catalog', 'public'
    as $$
declare
    candidate record;
    norm text;
    bounce_kind text;
    processed_count integer := 0;
    max_processing_attempts constant integer := 5;
    recipient public.marketing_campaign_recipients;
    new_status text;
    event_time timestamptz;
    reputation_organizations uuid[] := '{}';
    reputation_organization uuid;
begin
    if batch_size < 1 or batch_size > 2000 then
        raise exception 'The marketing event batch size is outside its safe bounds.'
            using errcode = 'check_violation';
    end if;

    for candidate in
        select event.id, event.event_kind, event.payload, event.occurred_at, event.received_at,
            event.processing_attempts, event.provider_message_id
        from public.marketing_campaign_recipient_events event
        where event.processed_at is null
        order by event.received_at, event.id
        limit batch_size
        for update of event skip locked
    loop
        norm := case candidate.event_kind
            when 'Send' then 'sent'
            when 'Delivery' then 'delivered'
            when 'Complaint' then 'complaint'
            when 'Reject' then 'rejected'
            when 'DeliveryDelay' then 'delayed'
            when 'Open' then 'open'
            when 'Click' then 'click'
            when 'Bounce' then (
                case candidate.payload -> 'bounce' ->> 'bounceType'
                    when 'Permanent' then 'hard_bounce'
                    else 'soft_bounce'
                end
            )
            else 'other'
        end;
        event_time := coalesce(candidate.occurred_at, candidate.received_at);

        begin
            select * into recipient
            from public.marketing_campaign_recipients
            where provider_message_id = candidate.provider_message_id
            for update;

            if not found then
                -- The event arrived before the recipient's own finalize commit became visible, or names a
                -- message id this database never sent (a stray test send). Left unprocessed to retry on the
                -- next drain, capped like the operational processor so a permanently unknown id cannot spin
                -- forever.
                if candidate.processing_attempts + 1 >= max_processing_attempts then
                    update public.marketing_campaign_recipient_events
                    set processed_at = now(), normalized_kind = norm,
                        processing_attempts = candidate.processing_attempts + 1,
                        processing_error = 'No marketing_campaign_recipients row matches this provider_message_id.'
                    where id = candidate.id;
                else
                    update public.marketing_campaign_recipient_events
                    set processing_attempts = candidate.processing_attempts + 1
                    where id = candidate.id;
                end if;
                continue;
            end if;

            if norm = 'delivered' then
                update public.marketing_campaign_recipients
                set status = case
                        when status in ('bounced', 'complained', 'unsubscribed') then status
                        else 'delivered'
                    end,
                    delivered_at = coalesce(delivered_at, event_time),
                    updated_at = now()
                where id = recipient.id;
            elsif norm = 'open' then
                update public.marketing_campaign_recipients
                set first_opened_at = least(coalesce(first_opened_at, event_time), event_time),
                    updated_at = now()
                where id = recipient.id;
            elsif norm = 'click' then
                update public.marketing_campaign_recipients
                set first_clicked_at = least(coalesce(first_clicked_at, event_time), event_time),
                    updated_at = now()
                where id = recipient.id;
            elsif norm in ('hard_bounce', 'complaint') then
                new_status := case norm when 'hard_bounce' then 'bounced' else 'complained' end;
                update public.marketing_campaign_recipients
                set status = new_status, failure_code = 'ses_' || norm, updated_at = now()
                where id = recipient.id and status <> 'unsubscribed';

                bounce_kind := case norm when 'hard_bounce' then 'hard_bounce' else 'complaint' end;
                insert into public.communication_email_suppressions (
                    organization_id, recipient_email, reason, source, evidence
                ) values (
                    recipient.organization_id, recipient.recipient_email, bounce_kind, 'provider_callback',
                    jsonb_build_object(
                        'event_kind', candidate.event_kind,
                        'occurred_at', candidate.occurred_at,
                        'received_at', candidate.received_at,
                        'campaign_id', recipient.campaign_id,
                        'marketing_campaign_recipient_id', recipient.id
                    )
                )
                on conflict (organization_id, recipient_email, reason) where released_at is null
                do nothing;

                if not recipient.organization_id = any(reputation_organizations) then
                    reputation_organizations := reputation_organizations || recipient.organization_id;
                end if;
            elsif norm = 'rejected' then
                update public.marketing_campaign_recipients
                set status = 'failed', failure_code = 'ses_reject', updated_at = now()
                where id = recipient.id and status not in ('bounced', 'complained', 'unsubscribed');
            end if;
            -- soft_bounce, delayed, sent, other: logged only, SES retries a soft bounce on its own.

            update public.marketing_campaign_recipient_events
            set processed_at = now(), normalized_kind = norm, organization_id = recipient.organization_id
            where id = candidate.id;
            processed_count := processed_count + 1;
        exception
            when others then
                update public.marketing_campaign_recipient_events
                set processing_attempts = coalesce(processing_attempts, 0) + 1,
                    processing_error = left(coalesce(sqlerrm, 'unknown error'), 1000),
                    normalized_kind = coalesce(normalized_kind, norm),
                    processed_at = case
                        when coalesce(processing_attempts, 0) + 1 >= max_processing_attempts then now()
                        else processed_at
                    end
                where id = candidate.id;
        end;
    end loop;

    -- Each organization that took a complaint or hard bounce in this batch is re-measured once, after its
    -- events are projected. A failure here is logged rather than raised so it can never stall the event
    -- pipeline that also writes suppressions; the next complaint or bounce re-runs the evaluation.
    foreach reputation_organization in array reputation_organizations loop
        begin
            perform public.evaluate_marketing_email_reputation(reputation_organization, now());
        exception
            when others then
                raise warning 'Marketing reputation evaluation failed for organization %: %',
                    reputation_organization, sqlerrm;
        end;
    end loop;

    return processed_count;
end;
$$;

-- Recipients sent before this migration have no delivered_at; their Delivery event's time is already stored.
update public.marketing_campaign_recipients recipient
set delivered_at = event.occurred_at
from public.marketing_campaign_recipient_events event
where event.provider_message_id = recipient.provider_message_id
  and event.normalized_kind = 'delivered'
  and recipient.delivered_at is null;

-- ---------------------------------------------------------------------------------------------------
-- 6. Replies to a Marketing message carry the campaign as their origin
-- ---------------------------------------------------------------------------------------------------

alter table "public"."communication_inbound_messages"
    add column if not exists "marketing_campaign_id" uuid;

do $$
begin
    if not exists (
        select 1 from pg_constraint where conname = 'communication_inbound_messages_marketing_campaign_fkey'
    ) then
        alter table "public"."communication_inbound_messages"
            add constraint "communication_inbound_messages_marketing_campaign_fkey"
            foreign key ("organization_id", "marketing_campaign_id")
            references "public"."marketing_campaigns"("organization_id", "id")
            on delete set null ("marketing_campaign_id");
    end if;
end
$$;

create index if not exists "communication_inbound_messages_marketing_campaign_idx"
    on "public"."communication_inbound_messages" using btree ("organization_id", "marketing_campaign_id")
    where ("marketing_campaign_id" is not null);

-- A trigger rather than another edit to record_communication_inbound_message: the inbound recorder is shared
-- with operational email and is being moved to SES by its own campaign, so Marketing stays out of its body.
-- SES sets Message-ID to <messageId@region.amazonses.com>; a reply's In-Reply-To carries that whole form while
-- UCRM stores only the bare messageId, so the local part is matched.
create or replace function "private"."tag_inbound_message_marketing_campaign"()
returns trigger
    language plpgsql
    set search_path to 'pg_catalog', 'public'
    as $$
declare
    bare_message_id text;
begin
    if new.marketing_campaign_id is not null or new.in_reply_to_provider_message_id is null then
        return new;
    end if;

    bare_message_id := substring(trim(new.in_reply_to_provider_message_id) from '^<?([^@<>]+)');
    if bare_message_id is null then
        return new;
    end if;

    select recipient.campaign_id into new.marketing_campaign_id
    from public.marketing_campaign_recipients recipient
    where recipient.provider_message_id = bare_message_id
      and recipient.organization_id = new.organization_id;

    return new;
end;
$$;

revoke all on function "private"."tag_inbound_message_marketing_campaign"() from public, anon, authenticated;

drop trigger if exists "tag_inbound_message_marketing_campaign" on "public"."communication_inbound_messages";
create trigger "tag_inbound_message_marketing_campaign"
    before insert on "public"."communication_inbound_messages"
    for each row execute function "private"."tag_inbound_message_marketing_campaign"();
