-- Organizations created before the tenancy foundation need the same defaults
-- that the organizations_create_settings trigger supplies to new records.
insert into public.organization_settings (organization_id)
select id
from public.organizations
on conflict (organization_id) do nothing;;
