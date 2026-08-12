-- Cover the composite tenant-scoped foreign key used when validating request properties.
create index requests_organization_property_idx on public.requests(organization_id, property_id);

;
