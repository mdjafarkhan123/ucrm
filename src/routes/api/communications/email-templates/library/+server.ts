import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationAdmin } from '$lib/server/access/permission';
import { PRIVATE_READ_HEADERS, databaseError } from '$lib/server/api/errors';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';

// Jafar's platform library, filtered to what the organization's current package actually includes, plus
// which entries the organization has already copied -- so the "copy from library" screen can show "Copy"
// or "Already added" without a second round trip. Owners/admins only: this is the source list for the
// admin-only copy action, browsing it is not useful to a plain sender.
export const GET: RequestHandler = async (event) => {
	const check = await requireOrganizationAdmin(event, 'conversations.send');
	if ('response' in check) return check.response;

	const owner = getOwnerSupabaseClient();
	const [templatesResult, visibilityResult, copiesResult] = await Promise.all([
		owner
			.from('platform_email_templates')
			.select('id, folder, name, subject, body, version')
			.order('name'),
		owner.from('platform_email_template_packages').select('template_id, package_key'),
		event.locals.supabase
			.from('communications_email_templates')
			.select('id, source_template_id, source_version_copied_at')
			.eq('organization_id', check.auth.organization.id)
			.not('source_template_id', 'is', null)
	]);
	if (templatesResult.error || visibilityResult.error || copiesResult.error) return databaseError();

	const restrictionsByTemplate = new Map<string, string[]>();
	for (const row of visibilityResult.data ?? []) {
		const keys = restrictionsByTemplate.get(row.template_id) ?? [];
		keys.push(row.package_key);
		restrictionsByTemplate.set(row.template_id, keys);
	}

	const copyByTemplate = new Map(
		(copiesResult.data ?? []).map((copy) => [copy.source_template_id as string, copy])
	);

	const effectivePackageKey = check.access.package.effective_key;
	const templates = (templatesResult.data ?? [])
		.filter((template) => {
			const restrictedTo = restrictionsByTemplate.get(template.id) ?? [];
			return restrictedTo.length === 0 || restrictedTo.includes(effectivePackageKey);
		})
		.map((template) => {
			const copy = copyByTemplate.get(template.id);
			return {
				...template,
				copied_template_id: copy?.id ?? null,
				update_available: Boolean(copy && copy.source_version_copied_at !== template.version)
			};
		});

	return json({ templates }, { headers: PRIVATE_READ_HEADERS });
};
