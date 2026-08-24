import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { hasPermission, requireOrganizationPermission } from '$lib/server/access/permission';
import { PRIVATE_READ_HEADERS, databaseError, notFound } from '$lib/server/api/errors';
import { organizationQuoteRepresentativeSignatureUrl } from '$lib/server/settings/quote-representative-signature';

// One read for every Quote Settings section. Quote Settings is hidden entirely from every role except
// owner and admin (same as Taxes), so the one permission that gates the page also gates this read and every
// write below it — there is no broader "view" key. Target margin's own table carries a wider read policy
// (quotes.view_cost OR settings.quotes.manage) for a future finance-only consumer, but owner/admin already
// satisfy it, so this route needs no extra check to include it.
export const GET: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'settings.quotes.manage');
	if ('response' in check) return check.response;

	const organizationId = check.auth.organization.id;

	const [settingsResult, marginResult] = await Promise.all([
		event.locals.supabase
			.from('organization_settings')
			.select(
				'quote_terms, quote_terms_revision, quote_terms_updated_by, quote_terms_updated_at, quote_representative_enabled, quote_representative_name, quote_representative_title, quote_representative_signature_object_key, quote_representative_revision, quote_representative_updated_by, quote_representative_updated_at, quote_require_customer_signature, quote_signature_policy_revision, quote_signature_policy_updated_by, quote_signature_policy_updated_at'
			)
			.eq('organization_id', organizationId)
			.maybeSingle(),
		event.locals.supabase
			.from('organization_quote_target_margin')
			.select('target_margin_basis_points, revision, updated_by, updated_at')
			.eq('organization_id', organizationId)
			.maybeSingle()
	]);

	if (settingsResult.error || marginResult.error) return databaseError();
	if (!settingsResult.data) return notFound('These settings could not be found.');

	const settings = settingsResult.data;
	const margin = marginResult.data;
	const canViewCost = hasPermission(check.access, 'quotes.view_cost');

	const editorIds = [
		settings.quote_terms_updated_by,
		settings.quote_representative_updated_by,
		settings.quote_signature_policy_updated_by,
		margin?.updated_by ?? null
	].filter((id): id is string => typeof id === 'string');

	const editorNames = new Map<string, string | null>();
	if (editorIds.length > 0) {
		const { data: editors } = await event.locals.supabase
			.from('profiles')
			.select('id, full_name')
			.in('id', [...new Set(editorIds)]);
		for (const editor of editors ?? []) editorNames.set(editor.id, editor.full_name);
	}

	const editor = (id: string | null, at: string | null) =>
		id ? { name: editorNames.get(id) ?? null, at } : null;

	return json(
		{
			permissions: {
				manage: true,
				view_cost: canViewCost
			},
			terms: {
				terms: settings.quote_terms,
				revision: settings.quote_terms_revision,
				last_editor: editor(settings.quote_terms_updated_by, settings.quote_terms_updated_at)
			},
			representative: {
				enabled: settings.quote_representative_enabled,
				name: settings.quote_representative_name,
				title: settings.quote_representative_title,
				signature_url: settings.quote_representative_signature_object_key
					? organizationQuoteRepresentativeSignatureUrl(settings.quote_representative_revision)
					: null,
				revision: settings.quote_representative_revision,
				last_editor: editor(
					settings.quote_representative_updated_by,
					settings.quote_representative_updated_at
				)
			},
			target_margin: {
				// Absent entirely rather than null when the viewer lacks cost visibility, so a page bug can
				// never accidentally render a value nobody was supposed to receive. `settings.quotes.manage`
				// does not imply `quotes.view_cost` — permissions are individually overridable per member.
				basis_points: margin && canViewCost ? margin.target_margin_basis_points : undefined,
				revision: margin?.revision ?? 1,
				last_editor: margin && canViewCost ? editor(margin.updated_by, margin.updated_at) : null
			},
			signature_policy: {
				require_customer_signature: settings.quote_require_customer_signature,
				revision: settings.quote_signature_policy_revision,
				last_editor: editor(
					settings.quote_signature_policy_updated_by,
					settings.quote_signature_policy_updated_at
				)
			}
		},
		{ headers: PRIVATE_READ_HEADERS }
	);
};
