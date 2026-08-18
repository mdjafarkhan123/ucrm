-- Requests and Assessments, Part 1b.
-- The requests list is keyset paginated on (created_at desc, id desc) — "Requested" is the column Jobber
-- sorts by, and offset pagination is not allowed in this app. Nothing indexed created_at, so the cursor
-- had nothing to ride.

create index requests_organization_created_idx
  on public.requests (organization_id, created_at desc, id desc);

-- The status filter chip narrows the same keyset scan. The old (organization_id, status, updated_at desc)
-- index could not serve it: the cursor sorts by created_at, so that index would force a sort. No query
-- used it — requests are only read by the crm overview route, which sorts by updated_at and is served by
-- requests_organization_updated_idx.
drop index if exists public.requests_organization_status_idx;

create index requests_organization_status_created_idx
  on public.requests (organization_id, status, created_at desc, id desc);
