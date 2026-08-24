-- Team & access, part 3A, item 4, correction found by its own pgTAP run.
--
-- 20260828090000's closing grants revoked everything from anon and authenticated but said nothing about
-- service_role, so Supabase's default privileges on new public tables left service_role holding UPDATE,
-- DELETE and TRUNCATE on both new tables. The immutability trigger still refused every edit, so no history
-- could actually be rewritten -- but "append-only" should not rest on a trigger alone when the grant is the
-- cheaper half of the guarantee. service_role keeps exactly what the commands need: read, and insert on the
-- history itself.
--
-- The shapes table is reference data seeded by migrations. Nothing writes it at runtime, so service_role
-- reads it and nothing more.

revoke all on public.organization_member_access_events from service_role;
grant select, insert on public.organization_member_access_events to service_role;

revoke all on public.member_access_event_shapes from service_role;
grant select on public.member_access_event_shapes to service_role;
