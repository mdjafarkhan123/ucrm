-- Profile photos: each person uploads their own picture, and every avatar in the app shows it.
--
-- `avatar_url` already feeds every avatar the app draws, so it stays the one field readers use. It now
-- only ever holds the app's own address for the photo (`/api/profile-photos/<user>?v=<photo>`), which
-- checks the viewer shares an organization with that person before streaming the bytes. A link to
-- anywhere else on the internet would let one teammate learn every other teammate's IP address the moment
-- their avatar was drawn, so the column refuses it.
--
-- `avatar_object_key` is where the re-encoded photo lives in R2. Both are written together, only by
-- `set_profile_photo`, which the server calls after it has cropped, resized and stripped the image.

alter table public.profiles
	add column avatar_object_key text,
	add constraint profiles_avatar_object_key_format check (
		avatar_object_key is null
		or avatar_object_key ~ '^profile-photos/[0-9a-f-]{36}/[0-9a-f-]{36}\.webp$'
	),
	add constraint profiles_avatar_url_is_app_route check (
		avatar_url is null
		or avatar_url ~ '^/api/profile-photos/[0-9a-f-]{36}\?v=[0-9a-f-]{36}$'
	),
	add constraint profiles_avatar_url_matches_object check ((avatar_url is null) = (avatar_object_key is null));

-- A signed-in person could previously write any value into their own avatar_url straight from the
-- browser. The name stays editable as before; the photo columns are the server's alone.
revoke update on table public.profiles from anon, authenticated;
grant update (full_name) on table public.profiles to authenticated;

-- Points a person's photo at a newly stored one (or clears it when `new_photo_id` is null) and hands back
-- the key it replaced, so the server can delete the old bytes. The row lock means two uploads racing from
-- two tabs each get the true previous key, and neither leaves an orphan the other forgot.
create function public.set_profile_photo(target_user_id uuid, new_photo_id uuid)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
	previous_object_key text;
begin
	select profile.avatar_object_key
	into previous_object_key
	from public.profiles as profile
	where profile.id = target_user_id
	for update;

	if not found then
		raise exception 'That profile does not exist.' using errcode = 'P0002';
	end if;

	update public.profiles
	set
		avatar_object_key = case
			when new_photo_id is null then null
			else format('profile-photos/%s/%s.webp', target_user_id, new_photo_id)
		end,
		avatar_url = case
			when new_photo_id is null then null
			else format('/api/profile-photos/%s?v=%s', target_user_id, new_photo_id)
		end
	where id = target_user_id;

	return previous_object_key;
end;
$$;

revoke all on function public.set_profile_photo(uuid, uuid) from public, anon, authenticated;
grant execute on function public.set_profile_photo(uuid, uuid) to service_role;
