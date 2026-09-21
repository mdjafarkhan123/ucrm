-- Message template editor: lets Jafar edit the wording of the 4 owner-managed
-- messages (received page, application-receipt email, password-setup email,
-- account-created-contact email) with a draft/publish workflow, an immutable
-- version history, and a restore-to-default action. Required/approved
-- placeholder rules and default copy live in TypeScript
-- (src/lib/server/jafar/message-templates.ts) since they are product rules
-- that change more often than the schema should -- this migration only
-- stores content and enforces "you cannot publish empty content".

create table public.platform_message_templates (
  template_key text primary key check (
    template_key in ('received_page', 'application_receipt', 'password_setup', 'account_created_contact')
  ),
  subject_draft text,
  body_draft text not null default '',
  subject_published text,
  body_published text,
  published_version integer not null default 0 check (published_version >= 0),
  published_at timestamptz,
  published_by_owner_email text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint platform_message_templates_published_check check (
    (published_version = 0) = (published_at is null)
  )
);

create trigger platform_message_templates_set_updated_at
before update on public.platform_message_templates
for each row execute function public.set_updated_at();

alter table public.platform_message_templates enable row level security;

revoke all on public.platform_message_templates from anon, authenticated;
grant select, insert, update on public.platform_message_templates to service_role;

-- Immutable snapshot of every publish, forever -- restore-to-version and the
-- version history list both read from here, never from the mutable row above.
create table public.platform_message_template_versions (
  id uuid primary key default gen_random_uuid(),
  template_key text not null references public.platform_message_templates (template_key),
  version integer not null check (version >= 1),
  subject text,
  body text not null,
  published_at timestamptz not null default now(),
  published_by_owner_email text not null,
  unique (template_key, version)
);

-- Reuses the immutability trigger function added for platform_owner_audit_events
-- in 20260812055458_platform_operations_foundation -- same "history is forever" rule.
create trigger platform_message_template_versions_immutable
before update or delete on public.platform_message_template_versions
for each row execute function private.prevent_platform_history_mutation();

alter table public.platform_message_template_versions enable row level security;

revoke all on public.platform_message_template_versions from anon, authenticated;
grant select, insert on public.platform_message_template_versions to service_role;

-- Atomic publish: snapshot the current draft as the new published state, add a
-- permanent version row, and write an audit event, all in one transaction.
-- Required-placeholder validation happens in the API layer before this is ever
-- called -- this function trusts its caller, same as every other atomic RPC
-- in this codebase (see confirm_onboarding_application_payment etc.).
create or replace function public.publish_message_template(
  target_template_key text,
  actor_email text
)
returns public.platform_message_templates
language plpgsql
set search_path = pg_catalog, public
security invoker
as $$
declare
  current record;
  next_version integer;
  updated public.platform_message_templates;
begin
  if actor_email is null or char_length(trim(actor_email)) = 0 then
    raise exception 'An acting owner email is required to publish a template.' using errcode = 'check_violation';
  end if;

  select subject_draft, body_draft, published_version
  into current
  from public.platform_message_templates
  where template_key = target_template_key
  for update;

  if not found then
    raise exception 'The message template does not exist.' using errcode = 'foreign_key_violation';
  end if;
  if current.body_draft is null or char_length(trim(current.body_draft)) = 0 then
    raise exception 'A template cannot be published with empty content.' using errcode = 'check_violation';
  end if;

  next_version := current.published_version + 1;

  update public.platform_message_templates
  set subject_published = current.subject_draft,
    body_published = current.body_draft,
    published_version = next_version,
    published_at = now(),
    published_by_owner_email = actor_email
  where template_key = target_template_key
  returning * into updated;

  insert into public.platform_message_template_versions (
    template_key, version, subject, body, published_by_owner_email
  ) values (
    target_template_key, next_version, current.subject_draft, current.body_draft, actor_email
  );

  insert into public.platform_owner_audit_events (
    actor_owner_email, event_type, target_type, target_key, after_state
  ) values (
    actor_email, 'message_template.published', 'platform_message_template', target_template_key,
    jsonb_build_object('version', next_version)
  );

  return updated;
end;
$$;

revoke all on function public.publish_message_template(text, text) from public, anon, authenticated;
grant execute on function public.publish_message_template(text, text) to service_role;

-- Seed all 4 templates as already published on day one, so nothing about live
-- behavior changes the moment this migration lands. The password-setup copy
-- matches the exact wording currently hardcoded in setup-link.ts -- a later
-- part switches that email over to read from here, unchanged in wording.
insert into public.platform_message_templates (
  template_key, subject_draft, body_draft, subject_published, body_published,
  published_version, published_at, published_by_owner_email
) values
  (
    'password_setup',
    'Set up your {{business_name}} administrator account',
    '<p>You''ve been invited to administer <strong>{{business_name}}</strong> on UpliftContractor.</p><p><a href="{{setup_link}}">Set your password</a></p><p>This link expires in 24 hours and can only be used once.</p>',
    'Set up your {{business_name}} administrator account',
    '<p>You''ve been invited to administer <strong>{{business_name}}</strong> on UpliftContractor.</p><p><a href="{{setup_link}}">Set your password</a></p><p>This link expires in 24 hours and can only be used once.</p>',
    1, now(), 'system'
  ),
  (
    'application_receipt',
    'We received your UpliftContractor application',
    '<p>Thanks for applying for <strong>{{package_name}}</strong> ({{price}}).</p><p>{{payment_instructions}}</p>',
    'We received your UpliftContractor application',
    '<p>Thanks for applying for <strong>{{package_name}}</strong> ({{price}}).</p><p>{{payment_instructions}}</p>',
    1, now(), 'system'
  ),
  (
    'account_created_contact',
    'Your UpliftContractor account is ready',
    '<p>The account for <strong>{{business_name}}</strong> has been created and the administrator has been sent access instructions.</p>',
    'Your UpliftContractor account is ready',
    '<p>The account for <strong>{{business_name}}</strong> has been created and the administrator has been sent access instructions.</p>',
    1, now(), 'system'
  ),
  (
    'received_page',
    null,
    '<p>Thanks for applying for <strong>{{package_name}}</strong> ({{price}}).</p><p>{{payment_instructions}}</p>',
    null,
    '<p>Thanks for applying for <strong>{{package_name}}</strong> ({{price}}).</p><p>{{payment_instructions}}</p>',
    1, now(), 'system'
  );

-- Matching version-1 snapshot for every seeded template, so history is
-- consistent from the very first row (a published template has a version).
insert into public.platform_message_template_versions (
  template_key, version, subject, body, published_by_owner_email
)
select template_key, published_version, subject_published, body_published, published_by_owner_email
from public.platform_message_templates;
