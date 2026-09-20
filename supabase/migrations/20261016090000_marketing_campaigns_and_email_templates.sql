-- Marketing (M3): campaign drafts and the branded email template library.
--
-- Three tables:
--   * marketing_platform_templates -- Jafar's 4 starter templates. Owner-managed, seeded once below; no
--     Jafar-facing editor UI yet (out of scope for this slice), matching platform_email_templates' shape.
--   * marketing_email_templates -- an organization's own copies. Copying snapshots blocks/subject plus the
--     platform template's version at copy time; later platform edits never touch the copy. Same
--     "copy-on-write, never auto-overwrite" contract as communications_email_templates.
--   * marketing_campaigns -- one campaign draft per row. Content (subject, preview text, blocks) is
--     validated by Zod in src/lib/marketing/campaign-content.ts; the database only guards that it is a json
--     object, same convention as form_versions.content.
--
-- Access follows the Marketing module's own convention (marketing_customer_groups), not Communications':
-- RLS on with no policy, service role only, every read/write goes through /api/marketing/* after a
-- requireOrganizationPermission check. This keeps one access pattern across the whole Marketing module
-- rather than mixing in Communications' authenticated-RLS-policy shape.

-- 1. Platform starter templates. ----------------------------------------------------------------------

create table public.marketing_platform_templates (
  id uuid primary key default gen_random_uuid(),
  key text not null unique check (char_length(trim(key)) between 1 and 60),
  name text not null check (char_length(trim(name)) between 1 and 120),
  goal text check (goal in ('bring_back', 'promote_service', 'announcement', 'blank')),
  subject text not null check (char_length(trim(subject)) between 1 and 300),
  preview_text text check (preview_text is null or char_length(trim(preview_text)) between 1 and 200),
  blocks jsonb not null check (jsonb_typeof(blocks) = 'array'),
  version integer not null default 1 check (version >= 1),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.marketing_platform_templates is
  'Jafar-managed starter templates the create-campaign journey offers to copy. version is bumped by trigger '
  'whenever subject/preview_text/blocks change, so an organization''s copy can detect a newer master without '
  'a sync job -- same shape as platform_email_templates.';

create function private.bump_marketing_platform_template_version()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.subject is distinct from old.subject
     or new.preview_text is distinct from old.preview_text
     or new.blocks is distinct from old.blocks then
    new.version := old.version + 1;
  end if;
  return new;
end;
$$;

-- Fires before `..._set_updated_at` (alphabetical trigger order), so a bumped version and the refreshed
-- updated_at land in the same row write.
create trigger marketing_platform_templates_bump_version
before update on public.marketing_platform_templates
for each row execute function private.bump_marketing_platform_template_version();

create trigger marketing_platform_templates_set_updated_at
before update on public.marketing_platform_templates
for each row execute function public.set_updated_at();

alter table public.marketing_platform_templates enable row level security;
revoke all on public.marketing_platform_templates from anon, authenticated;
grant select, insert, update, delete on public.marketing_platform_templates to service_role;

-- 2. An organization's own copies. --------------------------------------------------------------------

create table public.marketing_email_templates (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  source_template_id uuid references public.marketing_platform_templates(id) on delete set null,
  source_version_copied_at integer check (source_version_copied_at is null or source_version_copied_at >= 1),
  name text not null check (char_length(trim(name)) between 1 and 120),
  subject text not null check (char_length(trim(subject)) between 1 and 300),
  preview_text text check (preview_text is null or char_length(trim(preview_text)) between 1 and 200),
  blocks jsonb not null check (jsonb_typeof(blocks) = 'array'),
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.marketing_email_templates is
  'Organization-owned copies of marketing_platform_templates, one row per copy-on-use. source_template_id '
  'is on delete set null (not cascade): removing a platform template never removes an organization''s '
  'already-copied content, it only loses the "newer version exists" comparison.';

-- The only order the picker needs: alphabetical by name within an org. Same bounded-per-tenant reasoning
-- as communications_email_templates_org_name_idx -- a small handful of rows per organization.
create index marketing_email_templates_org_name_idx
  on public.marketing_email_templates(organization_id, name, id);

create trigger marketing_email_templates_set_updated_at
before update on public.marketing_email_templates
for each row execute function public.set_updated_at();

alter table public.marketing_email_templates enable row level security;
revoke all on public.marketing_email_templates from anon, authenticated;
grant select, insert, update, delete on public.marketing_email_templates to service_role;

-- 3. Campaign drafts. -----------------------------------------------------------------------------------

create table public.marketing_campaigns (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  name text not null check (char_length(trim(name)) between 1 and 160),
  goal text not null check (goal in ('bring_back', 'promote_service', 'announcement', 'blank')),
  customer_group_id uuid references public.marketing_customer_groups(id) on delete set null,
  template_id uuid references public.marketing_email_templates(id) on delete set null,
  -- Every blueprint state is listed now even though only 'draft' is reachable before M4 builds launch,
  -- cancellation and delivery -- avoids a churny later migration just to widen this list.
  status text not null default 'draft'
    check (status in ('draft', 'scheduled', 'sending', 'completed', 'cancelled', 'needs_attention')),
  -- subject, preview_text, blocks -- validated by Zod in src/lib/marketing/campaign-content.ts before any
  -- write reaches here. The database only guards that it is a json object, same convention as
  -- form_versions.content.
  content jsonb not null default '{}'::jsonb check (jsonb_typeof(content) = 'object'),
  revision integer not null default 1 check (revision >= 1),
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint marketing_campaigns_org_id_key unique (organization_id, id)
);

comment on table public.marketing_campaigns is
  'One campaign draft per row. revision is bumped only by marketing_update_campaign_draft, which refuses a '
  'stale write with P0409 rather than overwriting -- same lock shape as quote_versions.revision.';

create index marketing_campaigns_org_status_created_idx
  on public.marketing_campaigns(organization_id, status, created_at desc, id desc);
create index marketing_campaigns_customer_group_idx
  on public.marketing_campaigns(customer_group_id) where customer_group_id is not null;
create index marketing_campaigns_template_idx
  on public.marketing_campaigns(template_id) where template_id is not null;

create trigger marketing_campaigns_set_updated_at
before update on public.marketing_campaigns
for each row execute function public.set_updated_at();

alter table public.marketing_campaigns enable row level security;
revoke all on public.marketing_campaigns from anon, authenticated;
grant select, insert, update, delete on public.marketing_campaigns to service_role;

-- 4. Safe-save locking for the draft. --------------------------------------------------------------------
--
-- Mirrors update_quote_draft's shape exactly, including the P0409 errcode: Postgres' own serialization
-- failure code (40001) is auto-retried indefinitely by PostgREST, which never helps here because a stale
-- revision never becomes fresh on retry (see 20260824092150_stale_revision_conflicts_are_not_retryable.sql
-- for the incident that taught this). Called only by the service role from
-- src/lib/server/marketing/campaigns.ts -- never by `authenticated` directly, to keep one access pattern
-- across the Marketing module.
create function public.marketing_update_campaign_draft(
  target_organization_id uuid,
  target_campaign_id uuid,
  actor_user_id uuid,
  expected_revision integer,
  new_name text,
  new_goal text,
  new_customer_group_id uuid,
  new_template_id uuid,
  new_content jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  campaign_row public.marketing_campaigns;
  clean_name text;
  new_revision integer;
  new_updated_at timestamptz;
begin
  clean_name := nullif(trim(coalesce(new_name, '')), '');
  if clean_name is null or char_length(clean_name) > 160 then
    raise exception 'Give this campaign a name under 160 characters.' using errcode = 'check_violation';
  end if;

  if new_goal not in ('bring_back', 'promote_service', 'announcement', 'blank') then
    raise exception 'Unknown campaign goal.' using errcode = 'check_violation';
  end if;

  if new_content is null or jsonb_typeof(new_content) <> 'object' then
    raise exception 'Campaign content must be an object.' using errcode = 'check_violation';
  end if;

  select * into campaign_row
  from public.marketing_campaigns
  where id = target_campaign_id and organization_id = target_organization_id
  for update;

  if campaign_row.id is null then
    raise exception 'This campaign no longer exists.' using errcode = 'check_violation';
  end if;

  if campaign_row.status <> 'draft' then
    raise exception 'Only a draft campaign can be changed.' using errcode = 'check_violation';
  end if;

  if expected_revision is distinct from campaign_row.revision then
    raise exception 'Someone else changed this campaign while you were editing. Reload and try again.'
      using errcode = 'P0409';
  end if;

  if new_customer_group_id is not null and not exists (
    select 1 from public.marketing_customer_groups g
    where g.id = new_customer_group_id
      and g.organization_id = target_organization_id
      and g.archived_at is null
  ) then
    raise exception 'Choose a saved customer group.' using errcode = 'check_violation';
  end if;

  if new_template_id is not null and not exists (
    select 1 from public.marketing_email_templates t
    where t.id = new_template_id and t.organization_id = target_organization_id
  ) then
    raise exception 'Choose a valid template.' using errcode = 'check_violation';
  end if;

  update public.marketing_campaigns
  set name = clean_name,
      goal = new_goal,
      customer_group_id = new_customer_group_id,
      template_id = new_template_id,
      content = new_content,
      revision = revision + 1,
      updated_by = actor_user_id
  where id = campaign_row.id
  returning revision, updated_at into new_revision, new_updated_at;

  return jsonb_build_object('revision', new_revision, 'updated_at', new_updated_at);
end;
$$;

comment on function public.marketing_update_campaign_draft(
  uuid, uuid, uuid, integer, text, text, uuid, uuid, jsonb
) is
  'Saves a campaign draft. Refuses with P0409 when expected_revision does not match the stored revision, so '
  'the caller reloads instead of overwriting a change it never saw. Only a draft-status campaign can be '
  'changed; M4''s launch/cancel commands own every other status transition.';

revoke all on function public.marketing_update_campaign_draft(
  uuid, uuid, uuid, integer, text, text, uuid, uuid, jsonb
) from public, anon, authenticated;
grant execute on function public.marketing_update_campaign_draft(
  uuid, uuid, uuid, integer, text, text, uuid, uuid, jsonb
) to service_role;

-- 5. Seed the four starter templates. ----------------------------------------------------------------------
-- Kept deliberately light (heading, text, button) rather than seeding a placeholder image: no real branded
-- asset exists yet, and an external placeholder image URL would just be a broken image in every preview.
-- The image block itself remains available for a contractor to add once Business Profile branding assets
-- exist to point it at.

insert into public.marketing_platform_templates (key, name, goal, subject, preview_text, blocks) values
(
  'bring_back',
  'We miss you / book again',
  'bring_back',
  'We miss you, {{customer_first_name}}!',
  'It''s been a while — let''s get you back on the schedule.',
  jsonb_build_array(
    jsonb_build_object('id', gen_random_uuid(), 'type', 'heading', 'level', 'h1',
      'text', 'We miss you, {{customer_first_name}}!'),
    jsonb_build_object('id', gen_random_uuid(), 'type', 'text',
      'text', 'It''s been a little while since we last worked together. We''d love to help again, '
        || 'whether it''s a quick fix or a bigger project.'),
    jsonb_build_object('id', gen_random_uuid(), 'type', 'button', 'label', 'Book now', 'url', '#'),
    jsonb_build_object('id', gen_random_uuid(), 'type', 'divider')
  )
),
(
  'seasonal_reminder',
  'Seasonal service reminder',
  'promote_service',
  'Time for your seasonal service, {{customer_first_name}}',
  'A friendly reminder to book your seasonal service.',
  jsonb_build_array(
    jsonb_build_object('id', gen_random_uuid(), 'type', 'heading', 'level', 'h1',
      'text', 'Time for your seasonal service'),
    jsonb_build_object('id', gen_random_uuid(), 'type', 'text',
      'text', 'The season is changing, and now''s the best time to book so you get a slot before things '
        || 'fill up.'),
    jsonb_build_object('id', gen_random_uuid(), 'type', 'button', 'label', 'Schedule now', 'url', '#'),
    jsonb_build_object('id', gen_random_uuid(), 'type', 'divider')
  )
),
(
  'complementary_offer',
  'Complementary service offer',
  'promote_service',
  'A service you might also need',
  'Here''s something else {{business_name}} can help with.',
  jsonb_build_array(
    jsonb_build_object('id', gen_random_uuid(), 'type', 'heading', 'level', 'h1',
      'text', 'Something else we can help with'),
    jsonb_build_object('id', gen_random_uuid(), 'type', 'text',
      'text', 'While we''re on the subject, here''s another service our customers often add on.'),
    jsonb_build_object('id', gen_random_uuid(), 'type', 'button', 'label', 'Learn more', 'url', '#'),
    jsonb_build_object('id', gen_random_uuid(), 'type', 'divider')
  )
),
(
  'announcement',
  'Business announcement',
  'announcement',
  'News from {{business_name}}',
  'We''ve got something to share with you.',
  jsonb_build_array(
    jsonb_build_object('id', gen_random_uuid(), 'type', 'heading', 'level', 'h1',
      'text', 'News from {{business_name}}'),
    jsonb_build_object('id', gen_random_uuid(), 'type', 'text',
      'text', 'We wanted to let you know about something new.'),
    jsonb_build_object('id', gen_random_uuid(), 'type', 'divider')
  )
);
