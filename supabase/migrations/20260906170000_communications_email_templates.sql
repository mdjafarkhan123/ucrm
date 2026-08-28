-- Communications Part 6c: organization-side copy of Jafar's platform Email Templates library
-- (docs/contractor-email-contract.md § "Templates, snippets, and branding").
--
-- An organization never edits a platform template directly. Copying snapshots subject/body plus the
-- platform template's version at copy time into a fully organization-owned row; later platform edits never
-- touch it. `source_version_copied_at` is the only thing that makes "a newer version exists" computable --
-- the org-side read joins this table to `platform_email_templates` and compares versions itself, so there is
-- no sync job and no risk of a silent overwrite (contract: "never auto-overwrite").
--
-- `source_template_id` is `on delete set null` rather than cascade: if Jafar later removes a platform
-- template, organizations that already copied it keep their own copy, they just lose the "newer version"
-- comparison (source_version_copied_at is left as the last known value).
--
-- Same permission split GHL and Jobber use for shared-library content: anyone who can compose a message can
-- select a template (`conversations.send`, same as Snippets), but only owners/admins can add, edit, or
-- remove what's in the library (`private.is_organization_admin`), since a bad edit here changes what every
-- teammate sends. This is a stricter split than Snippets, which only ever gated on `conversations.send` --
-- Snippets are throwaway personal shorthand, Templates are the shared library.
create table public.communications_email_templates (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  source_template_id uuid references public.platform_email_templates(id) on delete set null,
  source_version_copied_at integer check (source_version_copied_at is null or source_version_copied_at >= 1),
  -- Optional grouping only, same "folder is the entire taxonomy" choice as communications_snippets.
  folder text check (folder is null or char_length(trim(folder)) between 1 and 60),
  name text not null check (char_length(trim(name)) between 1 and 120),
  subject text not null check (char_length(trim(subject)) between 1 and 300),
  body text not null check (char_length(trim(body)) between 1 and 50000),
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.communications_email_templates is
  'Organization-owned copies of platform_email_templates (copy-on-write) or organization-created templates. '
  'Not communications_snippets (throwaway personal text) -- see docs/contractor-email-contract.md § '
  'Templates, snippets, and branding.';

-- The only list order the picker and the settings screen need: alphabetical by name within an org. Same
-- bounded-per-tenant reasoning as communications_snippets_org_title_idx -- no separate folder or
-- source_template_id index, this library is a small handful of rows per organization.
create index communications_email_templates_org_name_idx
  on public.communications_email_templates(organization_id, name, id);

create trigger communications_email_templates_set_updated_at
before update on public.communications_email_templates
for each row execute function public.set_updated_at();

alter table public.communications_email_templates enable row level security;

create policy "members who can send can view email templates"
on public.communications_email_templates for select to authenticated
using (
  private.is_organization_member(organization_id)
  and private.has_permission(organization_id, 'conversations.send')
);

create policy "admins can create email templates"
on public.communications_email_templates for insert to authenticated
with check (private.is_organization_admin(organization_id));

create policy "admins can update email templates"
on public.communications_email_templates for update to authenticated
using (private.is_organization_admin(organization_id))
with check (private.is_organization_admin(organization_id));

create policy "admins can delete email templates"
on public.communications_email_templates for delete to authenticated
using (private.is_organization_admin(organization_id));

revoke all on public.communications_email_templates from anon, authenticated;
grant select, insert, update, delete on public.communications_email_templates to authenticated;
