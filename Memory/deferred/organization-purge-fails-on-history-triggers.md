# Organization purge fails once the organization has history-protected rows

**Why it waits:** Found 2026-09-28 during deferred-sweep 6C, outside that part. A rolled-back rehearsal of
`public.apply_organization_purge`'s delete on Raad LTD failed with P0409 "Published quote versions cannot be
changed or deleted." `private.reject_published_quote_version_change`, `reject_published_quote_child_change`
and `job_costing_events_are_append_only` ignore `app.organization_purge_in_progress`; only
`job_signatures_are_append_only` honors it. So a real closed organization with any sent quote cannot be purged.
**Brings it back:** Next Jafar-panel or launch-readiness work, or any organization reaching its purge date.
**Known constraints:** The same triggers already step aside for `private.property_delete_in_progress()`
(migration `20260929140000`); the fix is to also accept the purge setting, then re-run the rolled-back
rehearsal until the delete succeeds and check for further blockers.
