-- Package builder P3a added three trigger functions in `private` without taking EXECUTE away from PUBLIC,
-- anon and authenticated, which the rule set in 20260921150000 forbids (private_trigger_functions_execute_grants
-- catches it). Nothing needs the grant: a trigger runs its function regardless, and a trigger function cannot
-- be called directly.

revoke all on function private.prevent_frozen_package_edition_change() from public, anon, authenticated;
revoke all on function private.prevent_frozen_package_edition_terms_change() from public, anon, authenticated;
revoke all on function private.validate_organization_package_agreement() from public, anon, authenticated;
