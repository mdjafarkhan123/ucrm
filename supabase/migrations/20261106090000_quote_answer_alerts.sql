
-- Client reminders Part 2: the team hears every online quote answer, and the customer is thanked for a yes.
--
-- Plan: docs/client-reminders-behavior-contract.md § Quote approved or changes requested online.
-- Before this, only a decline reached anyone. Now an approval or a request for changes puts one alert in the
-- same person's bell and sends them one email; a decline stays bell-only. The approving customer gets a
-- thank-you email from the business's own automated sender. Also fixes a long customer message (up to 1,000
-- characters) overflowing the alert's 500-character body and failing the customer's answer.

-- 1. Alert kinds --------------------------------------------------------------------------------------------

alter table public.team_notifications drop constraint team_notifications_kind_check;
alter table public.team_notifications add constraint team_notifications_kind_check check (kind = any (array[
  'website_inquiry.received', 'website_inquiry.customer_replied', 'invoice.paid_online',
  'invoice.online_payment_failed', 'invoice.online_overpayment', 'quote.deposit_paid_online',
  'quote.deposit_payment_failed', 'quote.deposit_overpaid', 'invoice.online_refund_failed',
  'invoice.payment_disputed', 'quote.deposit_refund_failed', 'quote.deposit_disputed',
  'review.private_feedback', 'quote.delivery_failed', 'quote.customer_declined', 'pipeline.task_assigned',
  'pipeline.note_mention', 'quote.customer_approved', 'quote.changes_requested'
]));

-- 2. Who is emailed a quote answer --------------------------------------------------------------------------
--
-- Still an active member of an active business who may see quotes. Without this the worker would apply the
-- website-inquiry rule and silently drop the email for anyone not picked for inquiries.

create function private.member_receives_quote_alerts(p_organization_id uuid, p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, private
as $$
  select exists (
      select 1
      from public.organization_members as membership
      join public.organizations as organization on organization.id = membership.organization_id
      where membership.organization_id = p_organization_id
        and membership.user_id = p_user_id
        and membership.status = 'active'
        and organization.lifecycle_status = 'active'
    )
    and private.member_has_permission(p_organization_id, p_user_id, 'quotes.view');
$$;

revoke all on function private.member_receives_quote_alerts(uuid, uuid) from public, anon, authenticated;

-- Unchanged from 20261004090000 except the quote-answer kinds. Same signature, so the grant stands.
create or replace function public.claim_team_notification_emails(
  p_batch_size integer default 25,
  p_lease_seconds integer default 120
)
returns table (
  notification_id uuid, claim_token uuid, organization_id uuid, organization_name text, recipient_email text,
  kind text, subject_type text, subject_id uuid, title text, body text, attempts integer
)
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  candidate record;
  token uuid;
  receives boolean;
begin
  if p_batch_size < 1 or p_batch_size > 100 or p_lease_seconds < 30 or p_lease_seconds > 900 then
    raise exception 'The alert email claim is outside its safe bounds.' using errcode = 'check_violation';
  end if;

  for candidate in
    select q.id, q.organization_id, q.user_id, q.kind, q.subject_type, q.subject_id, q.title, q.body,
      q.email_attempts, o.name as organization_name, nullif(btrim(u.email), '') as email
    from public.team_notifications as q
    join public.organizations as o on o.id = q.organization_id
    left join auth.users as u on u.id = q.user_id
    where q.email_state = 'pending' and q.email_available_at <= now()
      and (q.email_claimed_until is null or q.email_claimed_until < now())
    order by q.email_available_at, q.id
    limit p_batch_size
    for update of q skip locked
  loop
    -- Set first: PL/pgSQL ends an IF condition at its first THEN, so a CASE cannot sit inside one.
    receives := case
      when candidate.kind in ('pipeline.task_assigned', 'pipeline.note_mention')
        then private.member_receives_task_alerts(candidate.organization_id, candidate.user_id)
      when candidate.kind in ('quote.customer_approved', 'quote.changes_requested')
        then private.member_receives_quote_alerts(candidate.organization_id, candidate.user_id)
      else private.member_receives_inquiry_alerts(candidate.organization_id, candidate.user_id)
    end;

    if candidate.email is null or not receives then
      update public.team_notifications
      set email_state = 'not_needed', email_claim_token = null, email_claimed_until = null
      where id = candidate.id;
      continue;
    end if;

    token := gen_random_uuid();
    update public.team_notifications
    set email_claim_token = token, email_claimed_until = now() + make_interval(secs => p_lease_seconds)
    where id = candidate.id;

    notification_id := candidate.id;
    claim_token := token;
    organization_id := candidate.organization_id;
    organization_name := candidate.organization_name;
    recipient_email := candidate.email;
    kind := candidate.kind;
    subject_type := candidate.subject_type;
    subject_id := candidate.subject_id;
    title := candidate.title;
    body := candidate.body;
    attempts := candidate.email_attempts;
    return next;
  end loop;
end;
$$;

-- 3. The customer's thank-you -------------------------------------------------------------------------------
--
-- Sent to the approver's address when it is one of the client's saved emails, else the client's main email.
-- It answers the customer's own action, so follow-up switches do not hold it back; "Do not disturb" does.
-- It is not tied to the quote's send history, so it can never count as the quote being sent again or start
-- a quote follow-up. One per decision (the send key), and anything missing -- no email, no ready sender --
-- simply means no thank-you, never a failed approval.

create function private.send_quote_approval_thanks(
  quote_row public.quotes,
  link_row public.quote_access_links,
  decision_id uuid
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  approver public.quote_recipients;
  client_row public.clients;
  contact public.client_contact_methods;
  sender public.communication_email_senders;
  sender_domain public.communication_email_domains;
  business_name text;
  greeting_name text;
  intent_id uuid;
begin
  select * into client_row from public.clients
  where organization_id = quote_row.organization_id and id = quote_row.client_id and deleted_at is null;
  if client_row.id is null then
    return;
  end if;

  if exists (
    select 1 from public.client_communication_preferences as preference
    where preference.organization_id = client_row.organization_id
      and preference.client_id = client_row.id
      and preference.contact_policy = 'do_not_disturb'
  ) then
    return;
  end if;

  select * into approver from public.quote_recipients
  where organization_id = quote_row.organization_id and id = link_row.recipient_id;

  select * into contact from public.client_contact_methods
  where organization_id = client_row.organization_id and client_id = client_row.id and kind = 'email'
  order by
    (approver.email is not null and normalized_value = lower(btrim(approver.email))) desc,
    is_primary desc, created_at, id
  limit 1;
  if contact.id is null then
    return;
  end if;

  -- The organization's default automated sender, exactly as the receipt and quote emails choose it.
  select * into sender from public.communication_email_senders
  where organization_id = client_row.organization_id and lifecycle_state = 'enabled' and allows_automated
    and is_organization_default
  order by created_at, id limit 1;
  if sender.id is not null then
    select * into sender_domain from public.communication_email_domains
    where organization_id = sender.organization_id and id = sender.domain_id and purpose = 'sending'
      and lifecycle_state = 'verified' and provider_verified and provider_authenticated
      and ownership_status = 'passing' and dkim_status = 'passing';
  end if;
  if sender.id is null or sender_domain.id is null then
    return;
  end if;

  select coalesce(nullif(btrim(organization.name), ''), 'your contractor') into business_name
  from public.organizations as organization where organization.id = client_row.organization_id;

  greeting_name := coalesce(
    nullif(btrim(approver.display_name), ''), nullif(btrim(client_row.display_name), '')
  );

  insert into public.communication_delivery_intents (
    organization_id, client_id, client_contact_method_id, logical_send_key, recipient_email, subject,
    html_content, text_content, send_kind, allowance_class, sender_id, created_by
  ) values (
    client_row.organization_id, client_row.id, contact.id, 'quote-approval-thanks:' || decision_id,
    contact.normalized_value,
    'Thanks for approving your quote from ' || business_name,
    '<p>' || case when greeting_name is null then 'Hello,' else 'Hi ' || private.html_escape(greeting_name) || ',' end
      || '</p><p>Thank you for approving quote #' || quote_row.quote_number || ' from '
      || private.html_escape(business_name)
      || '. We have your approval and will be in touch soon about the next steps.</p>',
    case when greeting_name is null then 'Hello,' else 'Hi ' || greeting_name || ',' end
      || E'\n\nThank you for approving quote #' || quote_row.quote_number || ' from ' || business_name
      || '. We have your approval and will be in touch soon about the next steps.',
    'automated', 'essential', sender.id, null
  )
  on conflict do nothing
  returning id into intent_id;

  if intent_id is not null then
    insert into public.communication_outbox_events (organization_id, delivery_intent_id)
    values (client_row.organization_id, intent_id);
  end if;
end;
$$;

revoke all on function private.send_quote_approval_thanks(public.quotes, public.quote_access_links, uuid)
  from public, anon, authenticated;

-- 4. The link's decision command. Unchanged from 20261002160000 except the alert for every answer, the
--    500-character body, and the thank-you. Same signature, so it is replaced in place.

create or replace function public.submit_quote_customer_decision(
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

  -- Every online answer is news somebody has to hear. The card's owner is responsible for it; an unassigned
  -- card falls to whoever sent the quote, and failing that to the account owner -- the same order a failed
  -- delivery uses, so the alerts land with the same person. A yes or a request for changes is also emailed
  -- (Jobber emails the quote's reply person); a no stays in the bell, as before.
  begin
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
        quote_row.organization_id, recipient,
        case new_outcome
          when 'approved' then 'quote.customer_approved'
          when 'changes_requested' then 'quote.changes_requested'
          else 'quote.customer_declined'
        end,
        'quote', quote_row.id,
        left(
          coalesce(client_name, 'The customer')
          || case new_outcome
               when 'approved' then ' approved quote #'
               when 'changes_requested' then ' asked for changes to quote #'
               else ' declined quote #'
             end
          || quote_row.quote_number,
          200
        ),
        -- The table holds 500 characters and a customer may write 1,000; cutting here keeps a long message
        -- from failing the customer's whole answer.
        left(
          case new_outcome
            when 'approved' then
              case when clean_signer is null then 'Approved online.' else 'Signed by ' || clean_signer || '.' end
            when 'changes_requested' then
              case when clean_note is null then 'They did not leave a message.' else 'They wrote:' end
            else
              case clean_reason
                when 'too_expensive' then 'They said it was too expensive.'
                when 'went_with_someone_else' then 'They said they went with someone else.'
                when 'no_longer_needed' then 'They said they are no longer doing the work.'
                when 'other' then 'They picked "Other".'
                else 'They did not say why.'
              end
          end
          || case when clean_note is null then '' else ' "' || clean_note || '"' end,
          500
        ),
        'quote_customer_' || new_outcome || ':' || new_decision_id,
        case when new_outcome = 'declined' then 'not_needed' else 'pending' end
      )
      on conflict (organization_id, user_id, source_key) do nothing;
    end if;
  end;

  -- The customer who said yes hears back at once (Jobber's approval email). Never fails the approval.
  -- A fault in the email is logged and swallowed: the customer's yes is what matters.
  if new_outcome = 'approved' then
    begin
      perform private.send_quote_approval_thanks(quote_row, link_row, new_decision_id);
    exception when others then
      raise warning 'Quote approval thank-you was not queued: %', sqlstate;
    end;
  end if;

  return jsonb_build_object(
    'quote_id', quote_row.id, 'status', quote_row.status, 'outcome', new_outcome,
    'decided_at', now(), 'signed', clean_signer is not null, 'already_answered', false
  );
end;
$$;

comment on function public.submit_quote_customer_decision(bytea, text, text, jsonb, text, text, text, integer, text) is
  'The customer''s answer through their quote link: approved, changes_requested, or declined (Pipeline B8). Service role only; the token hash decides which quote. A decline may carry the customer''s own reason pick and message. Every answer alerts the card''s owner, else the sender, else the account owner; an approval or change request is also emailed to them, and an approval thanks the customer by email.';

revoke all on function public.submit_quote_customer_decision(bytea, text, text, jsonb, text, text, text, integer, text) from public, anon, authenticated;
grant execute on function public.submit_quote_customer_decision(bytea, text, text, jsonb, text, text, text, integer, text) to service_role;
