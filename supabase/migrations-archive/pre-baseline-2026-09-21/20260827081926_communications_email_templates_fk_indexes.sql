-- Closes two unindexed-FK advisories the previous migration triggered, matching
-- communications_snippets_created_by_idx / catalog_items_created_by_idx.
--
-- created_by: without this, a user deletion's ON DELETE SET NULL against communications_email_templates is
-- a sequential scan.
--
-- source_template_id: unlike created_by, this one is not bounded to a single organization -- deleting one
-- platform_email_templates row (Jafar retiring a library template) fans its ON DELETE SET NULL out across
-- every organization's copies, so a full-table scan here scales with the whole platform, not one tenant.
create index communications_email_templates_created_by_idx
  on public.communications_email_templates(created_by)
  where created_by is not null;

create index communications_email_templates_source_template_id_idx
  on public.communications_email_templates(source_template_id)
  where source_template_id is not null;
