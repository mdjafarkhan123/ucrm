-- The advisor flags all three editor foreign keys as uncovered: without these, removing a user
-- seq-scans organization_settings looking for rows to null out. Partial, because most rows have
-- never been edited by anyone.
create index organization_settings_profile_editor_idx
  on public.organization_settings (profile_updated_by)
  where profile_updated_by is not null;

create index organization_settings_branding_editor_idx
  on public.organization_settings (branding_updated_by)
  where branding_updated_by is not null;

create index organization_settings_hours_editor_idx
  on public.organization_settings (hours_updated_by)
  where hours_updated_by is not null;
