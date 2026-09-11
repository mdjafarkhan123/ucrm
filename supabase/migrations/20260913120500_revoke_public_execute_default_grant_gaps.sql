-- Paid-launch trust Part 13 (A) correction: revoking from `anon` alone does nothing when the function still
-- holds Postgres's default `PUBLIC` execute grant -- every role, anon included, inherits access through
-- PUBLIC regardless of an explicit per-role revoke. These three still had that default grant.
revoke all on function public.labor_cost_total_minor(integer, bigint) from public;
grant execute on function public.labor_cost_total_minor(integer, bigint) to authenticated;

-- Trigger functions are never invoked by a role calling them directly, so no role needs EXECUTE on them at all.
revoke all on function public.set_updated_at() from public;
revoke all on function public.prevent_automation_recipe_version_mutation() from public;
