-- Communications Part 6 (first slice): Snippets -- short, folder-organized reusable text for the
-- Conversations composer (docs/contractor-email-contract.md § "Templates, snippets, and branding").
-- Deliberately not Templates: no platform library, no org-owned copy-on-write, no automation sync. Just a
-- flat, low-stakes reusable-text list, so this stays a single RLS-gated table with no revision protection
-- and no RPC layer -- the same shape as the Price Book picker's own plain `catalog.edit` insert/update, not
-- the revision-protected Settings management commands beside it.
--
-- Gated on `conversations.send`, the same permission that already governs sending a message: a snippet is
-- only useful to someone who can compose one, and GHL gates its own Snippets feature on that same single
-- "view & manage conversation" capability rather than a separate key.

create table public.communications_snippets (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  -- Optional grouping only. Left null, a snippet just shows under "Uncategorized" in the picker; there is
  -- no folder table to keep in sync, so renaming or clearing this field is the entire folder model.
  folder text check (folder is null or char_length(trim(folder)) between 1 and 60),
  title text not null check (char_length(trim(title)) between 1 and 120),
  body text not null check (char_length(trim(body)) between 1 and 4000),
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.communications_snippets is
  'Reusable text for the Conversations composer. Not Templates: no platform library, no versioning, no '
  'automation binding -- see docs/contractor-email-contract.md § Templates, snippets, and branding.';

-- The only list order the picker and the settings screen need: alphabetical by title within an org. Folder
-- is a plain equality filter left off this index on purpose -- a business's snippet library is a bounded,
-- per-tenant handful of rows (the same reasoning `catalog_items` used for its own category/labor/taxable
-- filters), so a second index would cost more on every write than it would ever save on a read.
create index communications_snippets_org_title_idx
  on public.communications_snippets(organization_id, title, id);

create trigger communications_snippets_set_updated_at
before update on public.communications_snippets
for each row execute function public.set_updated_at();

alter table public.communications_snippets enable row level security;

create policy "members who can send can view snippets"
on public.communications_snippets for select to authenticated
using (
  private.is_organization_member(organization_id)
  and private.has_permission(organization_id, 'conversations.send')
);

create policy "members who can send can create snippets"
on public.communications_snippets for insert to authenticated
with check (
  private.is_organization_member(organization_id)
  and private.has_permission(organization_id, 'conversations.send')
);

create policy "members who can send can update snippets"
on public.communications_snippets for update to authenticated
using (
  private.is_organization_member(organization_id)
  and private.has_permission(organization_id, 'conversations.send')
)
with check (
  private.is_organization_member(organization_id)
  and private.has_permission(organization_id, 'conversations.send')
);

create policy "members who can send can delete snippets"
on public.communications_snippets for delete to authenticated
using (
  private.is_organization_member(organization_id)
  and private.has_permission(organization_id, 'conversations.send')
);

revoke all on public.communications_snippets from anon, authenticated;
grant select, insert, update, delete on public.communications_snippets to authenticated;
