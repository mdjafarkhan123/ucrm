-- Paid-launch trust Part 13 (A): nine public functions still hold `anon` EXECUTE though every real caller is
-- an authenticated session (event.locals.supabase.rpc(...) or the platform-owner client). All are security
-- invoker, so RLS already refused a signed-out caller -- this closes the reachability, not a live leak.
revoke execute on function public.create_client(jsonb) from anon;
revoke execute on function public.update_client(jsonb) from anon;
revoke execute on function public.delete_property(uuid) from anon;
revoke execute on function public.create_note(uuid, text, uuid, text, boolean) from anon;
revoke execute on function public.manage_platform_package_version(
  text, text, uuid, text, text, text, integer, text[], text, integer, text
) from anon;
revoke execute on function public.pricing_line_total_minor(numeric, bigint) from anon;
revoke execute on function public.labor_cost_total_minor(integer, bigint) from anon;

-- Trigger functions are never invoked by a role calling them directly (Postgres runs a trigger under the
-- executor, not through the firing role's own EXECUTE privilege), so this cannot change trigger behavior --
-- it only removes an RPC surface PostgREST would otherwise still list.
revoke execute on function public.set_updated_at() from anon;
revoke execute on function public.prevent_automation_recipe_version_mutation() from anon;
