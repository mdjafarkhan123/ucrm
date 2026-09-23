-- Files and Media, Part 6F follow-up: keep file_links in sync with which image blocks a campaign draft
-- actually still holds.
--
-- finalize_file_processing already links every available campaign-image upload the moment its scan clears
-- (20260924090000), the same generic path a line photo or a logo uses. But a campaign's image blocks live
-- inside its own content jsonb, not a separate row per block the way quote_version_lines holds a line photo
-- -- so replacing or removing a block never removes the old File's link on its own. This mirrors
-- sync_line_photo_links' reasoning exactly (20260923100000): after every save, delete whichever
-- 'campaign_image' links no longer name a File any image block still references. Nothing is ever inserted
-- here -- finalize_file_processing already owns that half, including the case where a save lands before the
-- worker has linked a just-uploaded File.

CREATE OR REPLACE FUNCTION "public"."marketing_update_campaign_draft"("target_organization_id" "uuid", "target_campaign_id" "uuid", "actor_user_id" "uuid", "expected_revision" integer, "new_name" "text", "new_goal" "text", "new_customer_group_id" "uuid", "new_template_id" "uuid", "new_content" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'public'
    AS $$
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

  delete from public.file_links link
  where link.organization_id = target_organization_id
    and link.entity_type = 'marketing_campaign'
    and link.entity_id = campaign_row.id
    and link.role = 'campaign_image'
    and not link.protected
    and not exists (
      select 1
      from jsonb_array_elements(coalesce(new_content -> 'blocks', '[]'::jsonb)) as block
      where block ->> 'type' = 'image'
        and block ->> 'file_id' ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        and (block ->> 'file_id')::uuid = link.file_id
    );

  return jsonb_build_object('revision', new_revision, 'updated_at', new_updated_at);
end;
$$;
