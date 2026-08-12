-- The legacy owner operation is server-only. Revoke the default PUBLIC execute
-- privilege explicitly from browser roles.
revoke execute on function public.record_legacy_organization_package(uuid, uuid, date, text)
  from public, anon, authenticated;
grant execute on function public.record_legacy_organization_package(uuid, uuid, date, text)
  to service_role;
