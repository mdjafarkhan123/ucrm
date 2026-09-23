-- Part 6D — the frontend now uploads a logo through the shared File Manager pipeline
-- ($lib/settings/api.ts's uploadOrganizationLogo, via /api/files/uploads and finalize_file_processing),
-- so the temporary bridge from 20260923140000 is no longer called by anything and can go for good.
drop function public.set_organization_logo(uuid, text);
