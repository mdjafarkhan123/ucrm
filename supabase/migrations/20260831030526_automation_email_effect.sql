-- Contractor Settings Part 6D-3a: the email effect.
--
-- Until now an `action` step had no adapter: advance_automation_work_item parked it as needs_attention with
-- reason `action_not_available`, and nothing sent. This migration gives Automation a real, safe send that
-- reuses the Communications outbox exactly as the quote send does -- Automation never talks to the provider,
-- it drops a delivery intent into the same queue the email worker already drains.
--
-- The send is authorized as the SYSTEM (an automation has no signed-in user), so it cannot lean on the
-- human-permission check the quote send uses. Instead it fails closed on every domain fact it does not own:
-- automations entitlement, platform authority (operational/security), the quote still being open, a customer
-- email on file, and a verified automated sender. The copy is contractor-authored but constrained to a fixed
-- set of safe variables, escaped here so nothing a contractor or customer typed can smuggle markup into the
-- email.
--
-- Flow for one action step:
--   1. advance_automation_work_item now returns 'action_due' for an action step (no park, no advance): it has
--      run the enrollment/expiry/recipe rechecks, but the effect needs the app worker (Node) to mint the
--      customer link, which needs the app origin the database does not hold.
--   2. The worker mints a fresh access link (origin + random token) -- no quote data required -- and calls
--      perform_automation_email_effect, which in ONE transaction re-checks pause/current truth, enqueues the
--      email idempotently, and settles the work item (advance / stop / defer).
-- The logical send key is deterministic per (enrollment, version, step), so a replay -- a lease that expired
-- mid-effect and got picked up by a second worker -- re-enqueues the same key and sends nothing extra.

-- ---------------------------------------------------------------------------------------------------
-- 1. Rendering: author copy + a fixed, escaped variable set.
-- ---------------------------------------------------------------------------------------------------
-- HTML-escape a string. `&` first so the entities it introduces are not re-escaped.
create or replace function private.html_escape(p_text text)
returns text
language sql
immutable
set search_path = pg_catalog
as $$
  select replace(replace(replace(replace(replace(
    coalesce(p_text, ''),
    '&', '&amp;'), '<', '&lt;'), '>', '&gt;'), '"', '&quot;'), '''', '&#39;');
$$;

comment on function private.html_escape(text) is
  'Escapes the five HTML-significant characters. Ampersand is escaped first so introduced entities are not '
  'double-escaped.';

-- Render one automation email from contractor-authored subject/body and the four allow-listed variables.
-- The body is treated as plain text: it is escaped whole (so any markup the author typed is inert), THEN the
-- `{{token}}` placeholders -- which survive escaping because they hold no HTML-significant characters -- are
-- replaced with individually escaped values. `{{quote_link}}` becomes a real anchor. The plain-text part
-- substitutes raw. Subjects carry no markup, so they substitute raw and are never escaped.
create or replace function private.render_automation_email(
  p_subject text,
  p_body text,
  p_customer_name text,
  p_business_name text,
  p_quote_number text,
  p_quote_url text
)
returns table (subject text, html_content text, text_content text)
language plpgsql
immutable
set search_path = pg_catalog, private
as $$
declare
  rendered_subject text;
  rendered_html text;
  rendered_text text;
  link_html text;
begin
  rendered_subject := replace(replace(replace(replace(coalesce(p_subject, ''),
    '{{customer_name}}', p_customer_name),
    '{{business_name}}', p_business_name),
    '{{quote_number}}', p_quote_number),
    '{{quote_link}}', p_quote_url);

  link_html := '<a href="' || private.html_escape(p_quote_url) || '">'
    || private.html_escape(p_quote_url) || '</a>';
  rendered_html := private.html_escape(p_body);
  rendered_html := replace(replace(replace(replace(rendered_html,
    '{{customer_name}}', private.html_escape(p_customer_name)),
    '{{business_name}}', private.html_escape(p_business_name)),
    '{{quote_number}}', private.html_escape(p_quote_number)),
    '{{quote_link}}', link_html);
  rendered_html := '<p>' || regexp_replace(rendered_html, E'\r?\n', '<br>', 'g') || '</p>';

  rendered_text := replace(replace(replace(replace(coalesce(p_body, ''),
    '{{customer_name}}', p_customer_name),
    '{{business_name}}', p_business_name),
    '{{quote_number}}', p_quote_number),
    '{{quote_link}}', p_quote_url);

  subject := rendered_subject;
  html_content := rendered_html;
  text_content := rendered_text;
  return next;
end;
$$;

comment on function private.render_automation_email(text, text, text, text, text, text) is
  'Renders an automation email from author subject/body and the four allow-listed variables. The HTML body is '
  'escaped before variable substitution so no authored or customer text can inject markup.';

-- ---------------------------------------------------------------------------------------------------
-- 2. The system send command.
-- ---------------------------------------------------------------------------------------------------
-- Automation's equivalent of enqueue_quote_communication_email, authorized as the system. It owns none of the
-- facts it checks, so it re-reads each from its owning table immediately before enqueuing and returns a plain
-- status rather than raising: 'sent' (queued now, or already queued under this key), 'skipped_permanent' (a
-- fact that will not change -- the caller should stop the enrollment), or 'skipped_temporary' (not ready yet
-- -- the caller should back off and retry).
create or replace function public.enqueue_automation_quote_email(
  p_organization_id uuid,
  p_quote_id uuid,
  p_logical_send_key text,
  p_subject text,
  p_body text,
  p_quote_url text,
  p_quote_token_hash bytea
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  authority public.organization_automation_authority;
  quote_row public.quotes;
  version_row public.quote_versions;
  client_row public.clients;
  recipient public.client_contact_methods;
  quote_recipient public.quote_recipients;
  sender public.communication_email_senders;
  sender_domain public.communication_email_domains;
  alias public.communication_reply_aliases;
  intent public.communication_delivery_intents;
  access_link_id uuid;
  rendered record;
  customer_name text;
begin
  -- The link the worker minted must be well-formed; a malformed one is a caller bug, not a customer fact.
  if p_quote_url !~ '^https?://[^[:space:]]+$'
    or p_quote_token_hash is null or octet_length(p_quote_token_hash) <> 32 then
    return jsonb_build_object('status', 'skipped_permanent', 'reason', 'invalid_link');
  end if;

  -- Author copy must be present. A recipe frozen before this slice (referencing a template id, not subject/
  -- body) lands here and is stopped rather than sending an empty email.
  if coalesce(btrim(p_subject), '') = '' or coalesce(btrim(p_body), '') = '' then
    return jsonb_build_object('status', 'skipped_permanent', 'reason', 'invalid_email_content');
  end if;

  -- Idempotency: one intent per (organization, logical send key). If it already exists this effect already
  -- happened -- report sent without inserting a second.
  select * into intent from public.communication_delivery_intents
    where organization_id = p_organization_id and logical_send_key = p_logical_send_key for share;
  if intent.id is not null then
    if intent.quote_id is distinct from p_quote_id then
      return jsonb_build_object('status', 'skipped_permanent', 'reason', 'idempotency_conflict');
    end if;
    return jsonb_build_object('status', 'sent', 'reason', 'already_enqueued', 'intent_id', intent.id);
  end if;

  -- Entitlement: a package downgrade fails customer effects closed. Permanent so the row surfaces for an
  -- administrator to restore access or reduce recipes, rather than retrying forever.
  if not private.organization_has_automations_feature(p_organization_id, now()) then
    return jsonb_build_object('status', 'skipped_permanent', 'reason', 'automations_not_entitled');
  end if;

  -- Platform authority: operationally disabled or security suspended fails closed. Permanent-park so it is
  -- visible in Needs attention; resume replays it once the platform re-enables the organization.
  select * into authority from public.organization_automation_authority
    where organization_id = p_organization_id;
  if coalesce(authority.operational_state, 'enabled') <> 'enabled'
    or coalesce(authority.security_state, 'active') <> 'active' then
    return jsonb_build_object('status', 'skipped_permanent', 'reason', 'automation_suspended');
  end if;

  -- The quote must still be awaiting the customer. Approved, declined, archived, or gone means the follow-up
  -- is moot: permanent, so the caller stops the whole enrollment.
  select * into quote_row from public.quotes
    where organization_id = p_organization_id and id = p_quote_id
      and status in ('awaiting_response', 'changes_requested', 'approved') and archived_at is null for share;
  if quote_row.id is null then
    return jsonb_build_object('status', 'skipped_permanent', 'reason', 'quote_not_sendable');
  end if;

  select * into version_row from public.quote_versions
    where organization_id = quote_row.organization_id and id = quote_row.current_published_version_id
      and quote_id = quote_row.id and status = 'published' for share;
  select * into client_row from public.clients
    where organization_id = quote_row.organization_id and id = quote_row.client_id and deleted_at is null for share;
  select * into recipient from public.client_contact_methods
    where organization_id = quote_row.organization_id and client_id = quote_row.client_id and kind = 'email'
    order by is_primary desc, created_at, id limit 1 for share;
  if version_row.id is null or client_row.id is null or recipient.id is null then
    return jsonb_build_object('status', 'skipped_permanent', 'reason', 'recipient_unavailable');
  end if;

  -- A ready automated sender on a verified sending domain. This can become ready later (a domain still
  -- verifying), so its absence is temporary: back off and retry.
  select * into sender from public.communication_email_senders
    where organization_id = quote_row.organization_id and lifecycle_state = 'enabled' and allows_automated
      and is_organization_default
    order by created_at, id limit 1 for share;
  if sender.id is not null then
    select * into sender_domain from public.communication_email_domains
      where organization_id = sender.organization_id and id = sender.domain_id and purpose = 'sending'
        and lifecycle_state = 'verified' and provider_verified and provider_authenticated
        and ownership_status = 'passing' and dkim_status = 'passing' for share;
  end if;
  if sender.id is null or sender_domain.id is null then
    return jsonb_build_object('status', 'skipped_temporary', 'reason', 'sender_not_ready');
  end if;

  customer_name := coalesce(nullif(btrim(client_row.display_name), ''), recipient.normalized_value);
  select * into rendered from private.render_automation_email(
    p_subject, p_body, customer_name, version_row.organization_name,
    quote_row.quote_number::text, p_quote_url);

  alias := public.ensure_communication_reply_alias(
    quote_row.organization_id, sender.id, quote_row.client_id, recipient.id);

  insert into public.quote_recipients (organization_id, quote_id, display_name, email, created_by)
    values (quote_row.organization_id, quote_row.id, customer_name, recipient.normalized_value, null)
    on conflict (organization_id, quote_id, email) do update set display_name = excluded.display_name
    returning * into quote_recipient;
  update public.quote_access_links set revoked_at = now(), revoked_reason = 'rotated'
    where organization_id = quote_row.organization_id and quote_id = quote_row.id
      and recipient_id = quote_recipient.id and revoked_at is null;
  insert into public.quote_access_links
    (organization_id, quote_id, quote_version_id, recipient_id, token_hash, issued_by)
    values (quote_row.organization_id, quote_row.id, version_row.id, quote_recipient.id, p_quote_token_hash, null)
    returning id into access_link_id;

  -- The unique (organization, logical send key) constraint is the real exactly-once guard: two workers racing
  -- the same expired lease both reach here, and the loser catches the violation and returns the winner's row.
  begin
    insert into public.communication_delivery_intents
      (organization_id, client_id, client_contact_method_id, quote_id, quote_version_id, quote_recipient_id,
       quote_access_link_id, logical_send_key, recipient_email, subject, html_content, text_content,
       send_kind, allowance_class, sender_id, reply_alias_id, created_by)
      values (quote_row.organization_id, quote_row.client_id, recipient.id, quote_row.id, version_row.id,
       quote_recipient.id, access_link_id, p_logical_send_key, recipient.normalized_value,
       rendered.subject, rendered.html_content, rendered.text_content,
       'automated', 'essential', sender.id, alias.id, null)
      returning * into intent;
  exception when unique_violation then
    select * into intent from public.communication_delivery_intents
      where organization_id = p_organization_id and logical_send_key = p_logical_send_key;
    return jsonb_build_object('status', 'sent', 'reason', 'already_enqueued', 'intent_id', intent.id);
  end;

  insert into public.communication_outbox_events (organization_id, delivery_intent_id)
    values (intent.organization_id, intent.id);

  return jsonb_build_object('status', 'sent', 'reason', 'enqueued', 'intent_id', intent.id);
end;
$$;

comment on function public.enqueue_automation_quote_email(uuid, uuid, text, text, text, text, bytea) is
  'System-authorized automation email send: re-checks entitlement, authority, quote status, recipient, and '
  'sender readiness, renders safe copy, and enqueues one delivery intent idempotently on the logical send '
  'key. Returns sent / skipped_permanent / skipped_temporary. Service role only.';

revoke all on function public.enqueue_automation_quote_email(uuid, uuid, text, text, text, text, bytea)
  from public, anon, authenticated;
grant execute on function public.enqueue_automation_quote_email(uuid, uuid, text, text, text, text, bytea)
  to service_role;

-- ---------------------------------------------------------------------------------------------------
-- 3. The claimed action effect: recheck pause, enqueue, and settle in one transaction.
-- ---------------------------------------------------------------------------------------------------
-- Called by the worker after advance returned 'action_due' and it minted the customer link. Everything here
-- is guarded by the claim token, so a worker whose lease expired cannot settle over the worker that took the
-- row. The enqueue is idempotent, so even the split second where both own the row sends at most one email.
create or replace function public.perform_automation_email_effect(
  p_work_item_id uuid,
  p_claim_token uuid,
  p_quote_url text,
  p_quote_token_hash bytea
)
returns text
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  item private.automation_work_items%rowtype;
  enrollment private.automation_enrollments%rowtype;
  recipe_status text;
  definition jsonb;
  step jsonb;
  logical_send_key text;
  result jsonb;
  status text;
begin
  if p_work_item_id is null or p_claim_token is null then
    raise exception 'A work item and its claim are required.' using errcode = 'check_violation';
  end if;

  select * into item from private.automation_work_items
    where id = p_work_item_id and claim_token = p_claim_token and state = 'pending' for update;
  if not found then
    return 'claim_lost';
  end if;

  select * into enrollment from private.automation_enrollments where id = item.enrollment_id for update;
  if not found or enrollment.state <> 'active' then
    update private.automation_work_items
      set state = 'cancelled', claim_token = null, claimed_at = null where id = item.id;
    return 'action_cancelled';
  end if;
  if enrollment.expires_at is not null and enrollment.expires_at <= now() then
    update private.automation_enrollments
      set state = 'stopped', stop_reason = 'enrollment_expired', stopped_at = now() where id = enrollment.id;
    update private.automation_work_items
      set state = 'cancelled', claim_token = null, claimed_at = null where id = item.id;
    return 'action_cancelled';
  end if;

  -- Recheck pause immediately before the customer effect: a recipe paused since the claim holds this step.
  select recipe.status, version.definition into recipe_status, definition
    from private.automation_enrollments e
    join public.automation_recipes recipe on recipe.id = e.recipe_id
    join public.automation_recipe_versions version on version.id = e.recipe_version_id
    where e.id = enrollment.id;
  if recipe_status = 'paused' then
    update private.automation_work_items
      set available_at = now() + private.automation_retry_delay(item.attempts),
        claim_token = null, claimed_at = null
      where id = item.id;
    return 'action_deferred';
  end if;
  if recipe_status is distinct from 'active' then
    update private.automation_enrollments
      set state = 'stopped', stop_reason = 'recipe_not_active', stopped_at = now() where id = enrollment.id;
    update private.automation_work_items
      set state = 'cancelled', claim_token = null, claimed_at = null where id = item.id;
    return 'action_cancelled';
  end if;

  step := (definition -> 'steps') -> item.step_index;
  if step is null or (step ->> 'type') <> 'action' or (step ->> 'key') <> 'action.send_email' then
    -- Not an emailable action (or past the last step): nothing this adapter can do. Park for attention rather
    -- than guessing.
    update private.automation_work_items
      set state = 'needs_attention', attention_reason = 'action_not_available', attention_at = now(),
        claim_token = null, claimed_at = null
      where id = item.id;
    return 'action_cancelled';
  end if;

  logical_send_key := 'automation-quote-follow-up:' || enrollment.id || ':'
    || enrollment.recipe_version_id || ':' || item.step_index;

  result := public.enqueue_automation_quote_email(
    enrollment.organization_id,
    enrollment.subject_id,
    logical_send_key,
    step -> 'config' ->> 'subject',
    step -> 'config' ->> 'body',
    p_quote_url,
    p_quote_token_hash);
  status := result ->> 'status';

  if status = 'sent' then
    -- Advance the enrollment and schedule the single next step, due now: the next wake picks it up and advance
    -- applies any wait delay there. One customer message recorded.
    update private.automation_enrollments
      set current_step_index = item.step_index + 1,
        customer_messages_sent = customer_messages_sent + 1
      where id = enrollment.id;
    update private.automation_work_items
      set state = 'done', claim_token = null, claimed_at = null where id = item.id;
    insert into private.automation_work_items
      (organization_id, enrollment_id, step_index, due_at, available_at)
      values (enrollment.organization_id, enrollment.id, item.step_index + 1, now(), now())
      on conflict (enrollment_id, step_index) do nothing;
    return 'action_sent';
  elsif status = 'skipped_temporary' then
    update private.automation_work_items
      set available_at = now() + private.automation_retry_delay(item.attempts),
        last_error_code = left(result ->> 'reason', 100),
        claim_token = null, claimed_at = null
      where id = item.id;
    return 'action_deferred';
  else
    -- Permanent: stop the whole enrollment with the plain reason and cancel the step. Later steps do not run.
    update private.automation_enrollments
      set state = 'stopped', stop_reason = left(result ->> 'reason', 100), stopped_at = now()
      where id = enrollment.id;
    update private.automation_work_items
      set state = 'cancelled', last_error_code = left(result ->> 'reason', 100),
        claim_token = null, claimed_at = null
      where id = item.id;
    return 'action_cancelled';
  end if;
end;
$$;

comment on function public.perform_automation_email_effect(uuid, uuid, text, bytea) is
  'Runs one claimed email action in a single transaction: rechecks enrollment/expiry/pause, enqueues the '
  'email idempotently, and settles the work item (advance on sent, back off on temporary, stop the enrollment '
  'on permanent). Claim-token guarded. Service role only.';

revoke all on function public.perform_automation_email_effect(uuid, uuid, text, bytea)
  from public, anon, authenticated;
grant execute on function public.perform_automation_email_effect(uuid, uuid, text, bytea) to service_role;

-- ---------------------------------------------------------------------------------------------------
-- 4. advance now hands an action step to the worker instead of parking it.
-- ---------------------------------------------------------------------------------------------------
-- Only the action branch changes: it returns 'action_due' after the shared rechecks, leaving the row claimed
-- under its lease so the worker can mint the link and call perform_automation_email_effect. Everything else
-- (wait, completed, inactive, expired, recipe-not-active) is unchanged from 20260918090000.
create or replace function public.advance_automation_work_item(
  p_work_item_id uuid,
  p_claim_token uuid
)
returns text
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  item private.automation_work_items%rowtype;
  enrollment private.automation_enrollments%rowtype;
  recipe_status text;
  definition jsonb;
  step jsonb;
  step_type text;
  wait_amount integer;
  wait_unit text;
  next_due timestamptz;
begin
  if p_work_item_id is null or p_claim_token is null then
    raise exception 'A work item and its claim are required.' using errcode = 'check_violation';
  end if;

  select * into item
  from private.automation_work_items
  where id = p_work_item_id and claim_token = p_claim_token and state = 'pending'
  for update;

  if not found then
    return 'claim_lost';
  end if;

  select * into enrollment
  from private.automation_enrollments
  where id = item.enrollment_id
  for update;

  if not found or enrollment.state <> 'active' then
    update private.automation_work_items
    set state = 'cancelled', claim_token = null, claimed_at = null
    where id = item.id;
    return 'enrollment_inactive';
  end if;

  if enrollment.expires_at is not null and enrollment.expires_at <= now() then
    update private.automation_enrollments
    set state = 'stopped', stop_reason = 'enrollment_expired', stopped_at = now()
    where id = enrollment.id;
    update private.automation_work_items
    set state = 'cancelled', claim_token = null, claimed_at = null
    where id = item.id;
    return 'enrollment_expired';
  end if;

  select recipe.status, version.definition
  into recipe_status, definition
  from private.automation_enrollments as e
  join public.automation_recipes as recipe on recipe.id = e.recipe_id
  join public.automation_recipe_versions as version on version.id = e.recipe_version_id
  where e.id = enrollment.id;

  if recipe_status is distinct from 'active' then
    update private.automation_enrollments
    set state = 'stopped', stop_reason = 'recipe_not_active', stopped_at = now()
    where id = enrollment.id;
    update private.automation_work_items
    set state = 'cancelled', claim_token = null, claimed_at = null
    where id = item.id;
    return 'recipe_not_active';
  end if;

  step := (definition -> 'steps') -> item.step_index;

  if step is null then
    update private.automation_enrollments
    set state = 'completed', completed_at = now(), current_step_index = item.step_index
    where id = enrollment.id;
    update private.automation_work_items
    set state = 'done', claim_token = null, claimed_at = null
    where id = item.id;
    return 'completed';
  end if;

  step_type := step ->> 'type';

  if step_type = 'wait' then
    wait_unit := step -> 'config' ->> 'unit';
    wait_amount := nullif(step -> 'config' ->> 'amount', '')::integer;
    if wait_unit not in ('hours', 'days') or wait_amount is null or wait_amount < 1 then
      raise exception 'This automation step has an unusable delay.' using errcode = 'check_violation';
    end if;

    next_due := now() + case wait_unit
      when 'days' then make_interval(days => wait_amount)
      else make_interval(hours => wait_amount)
    end;

    update private.automation_enrollments
    set current_step_index = item.step_index + 1
    where id = enrollment.id;

    update private.automation_work_items
    set state = 'done', claim_token = null, claimed_at = null
    where id = item.id;

    insert into private.automation_work_items (
      organization_id, enrollment_id, step_index, due_at, available_at
    ) values (
      enrollment.organization_id, enrollment.id, item.step_index + 1, next_due, next_due
    )
    on conflict (enrollment_id, step_index) do nothing;

    return 'waiting';
  end if;

  if step_type = 'action' then
    -- The effect runs in the worker (it needs the app origin to mint the customer link) and settles through
    -- perform_automation_email_effect. The row stays claimed under its lease meanwhile; a lease that expires
    -- before the effect settles returns the row to the queue and the idempotent send key prevents a double.
    return 'action_due';
  end if;

  raise exception 'This automation step has an unknown type.' using errcode = 'check_violation';
end;
$$;

comment on function public.advance_automation_work_item(uuid, uuid) is
  'Runs one claimed transition: rechecks enrollment, expiry, and recipe state, then completes, waits and '
  'schedules the single next step, or returns action_due for the worker to run and settle the effect. '
  'Claim-token guarded. Service role only.';

revoke all on function public.advance_automation_work_item(uuid, uuid) from public, anon, authenticated;
grant execute on function public.advance_automation_work_item(uuid, uuid) to service_role;
