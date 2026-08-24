# Eleven older trigger functions in `private` are executable by everyone

- **Priority:** P3


- **Campaign:** `contractor-settings`, found during item 7's grant cleanup, 2026-08-31.
- **Reason:** the Part 3 trigger functions are locked to nobody, and item 7 brought
  `private.validate_client_owner` in line with them. The eleven Clients and collaboration trigger functions
  written before that convention still carry Postgres's default PUBLIC execute:
  `create_client_communication_preferences`, `enforce_client_conversion`, `enforce_client_primary_property`,
  `log_attachment_activity`, `log_note_link_activity`, `log_property_contact_activity`,
  `log_tag_assignment_activity`, `set_client_conversion_on_insert`, `set_first_property_primary`,
  `validate_linked_entity`, `validate_property_billing_address`. Postgres refuses to run a trigger function
  as a plain call, so none of this is reachable - it is a consistency gap, not a hole.
- **Reactivation trigger:** the Clients or collaboration schema is next touched, or an app-wide grant sweep
  is picked up.
- **Prerequisites:** none. One `revoke all on function ... from public, anon, authenticated, service_role;`
  per function, in one migration. Triggers keep firing: Postgres checks EXECUTE when a trigger is created,
  not when it fires, which item 7's matrix test asserts for `validate_client_owner`.
- **Checkpoint:** `select p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace where
  n.nspname = 'private' and has_function_privilege('anon', p.oid, 'EXECUTE');`

