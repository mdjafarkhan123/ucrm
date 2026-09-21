-- The editor foreign key gets its covering index, matching the profile/branding/hours editor indexes that
-- already exist. This is one row per organization, so the write cost is nothing and the ON DELETE SET NULL
-- path does not have to scan the table when a user is removed. (The board indexes are held to a much higher
-- bar precisely because opportunities gets a row per Request.)
create index if not exists organization_settings_pipeline_editor_idx
  on public.organization_settings(pipeline_updated_by)
  where pipeline_updated_by is not null;
