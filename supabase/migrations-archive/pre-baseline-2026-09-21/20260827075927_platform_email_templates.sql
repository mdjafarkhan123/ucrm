-- Communications Part 6b: Jafar's platform-owned Email Templates library
-- (docs/contractor-email-contract.md § "Templates, snippets, and branding").
--
-- Distinct from two existing tables that look similar but solve a different problem:
--   * `communications_snippets` -- short org-only reusable text, no platform origin, no versioning.
--   * `platform_message_templates` -- Jafar's own fixed 8-key system/security emails, with a
--     draft/publish split and immutable version history because a bad edit there is a compliance risk.
-- This table is Jafar's library of many reusable *content* templates that organizations copy into their
-- own editable copy (added in a later slice, once the org-side copy-on-write screen is scoped). Lower
-- stakes than system emails, so no draft/publish split: Jafar edits and it is live for org copying
-- immediately. `version` exists only so a copied org template can later detect "the platform template I
-- copied has since changed" -- it is bumped by trigger whenever subject or body changes, nothing reads it
-- as history.
--
-- Owner-only for this slice, same as `platform_message_templates` and `platform_packages`: no RLS policy
-- for `authenticated`, every access goes through a /api/jafar/* route on the service-role client. The
-- org-side read (filtered by package visibility) is a later slice's job.
create table public.platform_email_templates (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(trim(name)) between 1 and 120),
  -- Optional grouping only, same "folder is the entire taxonomy" choice as communications_snippets.
  folder text check (folder is null or char_length(trim(folder)) between 1 and 60),
  subject text not null check (char_length(trim(subject)) between 1 and 300),
  body text not null check (char_length(trim(body)) between 1 and 50000),
  version integer not null default 1 check (version >= 1),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.platform_email_templates is
  'Jafar-managed platform template library orgs copy from. Not communications_snippets (org-only, no '
  'origin) and not platform_message_templates (fixed-key system emails with draft/publish/history) -- see '
  'docs/contractor-email-contract.md § Templates, snippets, and branding.';

-- Package tiers this template is visible to for copying. No row for a template means visible to every
-- package -- an explicit "restricted to these tiers" list is opt-in, not opt-out, so a newly created
-- template defaults to visible everywhere without Jafar having to enumerate all three tiers by hand.
-- Mirrors `package_features`' package_key join table rather than an array column, for the same reason:
-- one place to see every template a given package tier can reach.
create table public.platform_email_template_packages (
  template_id uuid not null references public.platform_email_templates (id) on delete cascade,
  package_key text not null references public.platform_packages (package_key),
  created_at timestamptz not null default now(),
  primary key (template_id, package_key)
);

create index platform_email_template_packages_package_idx
  on public.platform_email_template_packages (package_key, template_id);

create or replace function private.bump_platform_email_template_version()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.subject is distinct from old.subject or new.body is distinct from old.body then
    new.version := old.version + 1;
  end if;
  return new;
end;
$$;

-- Fires before `..._set_updated_at` (alphabetical trigger order), so a bumped version and the refreshed
-- updated_at both land in the same row write.
create trigger platform_email_templates_bump_version
before update on public.platform_email_templates
for each row execute function private.bump_platform_email_template_version();

create trigger platform_email_templates_set_updated_at
before update on public.platform_email_templates
for each row execute function public.set_updated_at();

alter table public.platform_email_templates enable row level security;
alter table public.platform_email_template_packages enable row level security;

revoke all on public.platform_email_templates from anon, authenticated;
revoke all on public.platform_email_template_packages from anon, authenticated;

grant select, insert, update, delete on public.platform_email_templates to service_role;
grant select, insert, update, delete on public.platform_email_template_packages to service_role;
