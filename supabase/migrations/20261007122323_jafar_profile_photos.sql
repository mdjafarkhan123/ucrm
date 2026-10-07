-- Profile photos in the Jafar Panel. Jafar and his teammates are not Supabase users (ADR 0008), so their
-- photos cannot live on `profiles` like a contractor's. A teammate's sits on their `platform_team_members`
-- row; Jafar has no row of his own, so his sits on the single `platform_owner_settings` row.
--
-- The same rules as contractor photos (20261007100121): the address only ever points at the app's own
-- route, which checks for a live `/jafar` session before streaming the bytes, and the two columns are
-- written together, only by the functions below.

alter table public.platform_team_members
	add column avatar_object_key text,
	add column avatar_url text,
	add constraint platform_team_members_avatar_object_key_format check (
		avatar_object_key is null
		or avatar_object_key ~ '^platform-photos/[0-9a-f-]{36}/[0-9a-f-]{36}\.webp$'
	),
	add constraint platform_team_members_avatar_url_is_app_route check (
		avatar_url is null
		or avatar_url ~ '^/api/jafar/photos/[0-9a-f-]{36}\?v=[0-9a-f-]{36}$'
	),
	add constraint platform_team_members_avatar_url_matches_object check (
		(avatar_url is null) = (avatar_object_key is null)
	);

alter table public.platform_owner_settings
	add column owner_avatar_object_key text,
	add column owner_avatar_url text,
	add constraint platform_owner_settings_owner_avatar_object_key_format check (
		owner_avatar_object_key is null
		or owner_avatar_object_key ~ '^platform-photos/owner/[0-9a-f-]{36}\.webp$'
	),
	add constraint platform_owner_settings_owner_avatar_url_is_app_route check (
		owner_avatar_url is null
		or owner_avatar_url ~ '^/api/jafar/photos/owner\?v=[0-9a-f-]{36}$'
	),
	add constraint platform_owner_settings_owner_avatar_url_matches_object check (
		(owner_avatar_url is null) = (owner_avatar_object_key is null)
	);

-- Points a teammate's photo at a newly stored one (or clears it when `new_photo_id` is null) and hands back
-- the key it replaced, so the server can delete the old bytes. The row lock means two uploads racing from
-- two tabs each get the true previous key. Owner and teammate are separate functions so a missing member
-- id can never fall through to changing Jafar's own photo.
create function public.set_platform_team_member_photo(target_member_id uuid, new_photo_id uuid default null)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
	previous_object_key text;
begin
	select member.avatar_object_key
	into previous_object_key
	from public.platform_team_members as member
	where member.id = target_member_id
	for update;

	if not found then
		raise exception 'That teammate does not exist.' using errcode = 'P0002';
	end if;

	update public.platform_team_members
	set
		avatar_object_key = case
			when new_photo_id is null then null
			else format('platform-photos/%s/%s.webp', target_member_id, new_photo_id)
		end,
		avatar_url = case
			when new_photo_id is null then null
			else format('/api/jafar/photos/%s?v=%s', target_member_id, new_photo_id)
		end
	where id = target_member_id;

	return previous_object_key;
end;
$$;

create function public.set_platform_owner_photo(new_photo_id uuid default null)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
	previous_object_key text;
begin
	insert into public.platform_owner_settings (id)
	values (true)
	on conflict (id) do nothing;

	select settings.owner_avatar_object_key
	into previous_object_key
	from public.platform_owner_settings as settings
	where settings.id = true
	for update;

	update public.platform_owner_settings
	set
		owner_avatar_object_key = case
			when new_photo_id is null then null
			else format('platform-photos/owner/%s.webp', new_photo_id)
		end,
		owner_avatar_url = case
			when new_photo_id is null then null
			else format('/api/jafar/photos/owner?v=%s', new_photo_id)
		end
	where id = true;

	return previous_object_key;
end;
$$;

revoke all on function public.set_platform_team_member_photo(uuid, uuid) from public, anon, authenticated;
grant execute on function public.set_platform_team_member_photo(uuid, uuid) to service_role;
revoke all on function public.set_platform_owner_photo(uuid) from public, anon, authenticated;
grant execute on function public.set_platform_owner_photo(uuid) to service_role;
