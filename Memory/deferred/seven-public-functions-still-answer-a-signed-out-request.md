# Seven public functions still answer a signed-out request

- **Priority:** P1


- **Campaign:** none - found during `contractor-settings` item 7's grant cleanup, 2026-08-31.
- **Reason:** item 7 took `anon` off the three Part 1 settings write commands, which were SECURITY DEFINER
  and therefore the ones that mattered. Seven others still hold `anon` EXECUTE: `create_client`,
  `update_client`, `delete_property`, `create_note`, `manage_platform_package_version`,
  `pricing_line_total_minor` and `set_updated_at`. All seven are security invoker, so RLS answers a
  signed-out caller with nothing and no data is exposed - but they are published at `/rest/v1/rpc/...` to
  anyone holding the publishable key, and three of them are writes. They belong to Clients, Quotes and the
  Platform Owner, not to 3A.
- **Reactivation trigger:** the owning domain is next touched, or an app-wide grant sweep is picked up.
- **Prerequisites:** confirm each one has no signed-out caller - the customer-facing quote portal uses its
  own token routes, so none is expected - then `revoke execute ... from anon` per function.
- **Checkpoint:** `select p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace where
  n.nspname = 'public' and p.prokind = 'f' and has_function_privilege('anon', p.oid, 'EXECUTE');`

