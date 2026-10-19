-- The same members who create shared client tags may change their palette colour.
create policy "permitted members can recolour tags" on public.tags
for update to authenticated
using (private.is_organization_member(organization_id) and private.has_permission(organization_id, 'customers.edit'))
with check (private.is_organization_member(organization_id) and private.has_permission(organization_id, 'customers.edit'));
