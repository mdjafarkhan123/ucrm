-- Team & access, part 3A, item 7, found by the security advisor while closing the grant cleanup.
--
-- The three part 1 settings write commands are SECURITY DEFINER and were executable by `anon`, which
-- means PostgREST published them at /rest/v1/rpc/... to anybody holding the publishable key, signed in
-- or not. Nothing was ever at risk: each one opens with private.has_permission, and a signed-out caller
-- has no membership, so the call raises 42501 "You do not have access to change business settings."
-- Confirmed live under `set local role anon` before writing this.
--
-- The check is still the thing that decides. The grant should simply never have put a signed-out request
-- in front of it -- a definer function runs as its owner, so the guard inside is the only wall, and one
-- wall is not enough for a write. authenticated keeps EXECUTE: that is how the settings pages save.
--
-- The other public functions anon can still reach are all security invoker, so RLS answers them with
-- nothing, and they belong to Clients, Quotes and the Platform Owner rather than to 3A. They are logged
-- in Memory/deferred/INDEX.md.

revoke execute on function
  public.save_organization_business_profile(
    uuid, integer, text, text, text, text, text, text, text, text, text, text, text, boolean, text,
    text, boolean, boolean)
  from anon;

revoke execute on function
  public.save_organization_branding(uuid, integer, text)
  from anon;

revoke execute on function
  public.save_organization_business_hours(uuid, integer, text, jsonb)
  from anon;
