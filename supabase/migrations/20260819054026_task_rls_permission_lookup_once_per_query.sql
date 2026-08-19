-- The Task policy repeated the mistake the Pipeline board policies were already corrected for: calling
-- the membership and permission helpers once per returned row. The answer is the same for every row in
-- a query, so it is resolved once, the same way public.opportunities does it. The Brief only ever reads
-- ten Tasks at a time, but Schedule will read a whole team's list, and that is where this would show.
--
-- It also fixes a real gap: private.permitted_organizations requires the organization to still be
-- active, which the pair of helpers below did not check.

drop policy "permitted members can view tasks" on public.tasks;

create policy "permitted members can view tasks"
on public.tasks for select to authenticated
using (organization_id in (select private.permitted_organizations('pipeline.view')));
