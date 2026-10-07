-- Removing a photo passes no photo id at all, so the argument defaults to null; the generated client then
-- types it as optional instead of demanding a string the removal does not have.
create or replace function public.set_profile_photo(target_user_id uuid, new_photo_id uuid default null)
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
