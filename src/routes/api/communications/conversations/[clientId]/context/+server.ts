import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import {
	hasPermission,
	requireOrganizationPermission,
	featureUnavailable
} from '$lib/server/access/permission';
import {
	databaseError,
	notFound,
	PRIVATE_READ_HEADERS,
	validationError
} from '$lib/server/api/errors';
import {
	CONTEXT_SECTIONS,
	CONTEXT_SECTION_PERMISSIONS,
	CONTEXT_SECTION_PRICE_PERMISSIONS,
	isContextSection
} from '$lib/communications/context-sections';
import { readContextSection } from '$lib/server/communications/conversation-context';
import { organizationFormatting } from '$lib/server/requests/timezone';

// The inbox's customer context rail. Without a `section` it returns only the client -- identity, primary
// contact methods, and which of the record tabs this member may see -- so opening a conversation costs two
// small reads however much work the customer has. Each record tab (`?section=quotes`, ...) is then read on
// its own when the member reaches for it.
//
// A tab the member may not see is left out of `sections`, and asking for it anyway gets an empty answer
// rather than a 403 or a hidden count, so a denied domain discloses nothing. The tabs' own row-level
// security and gated money functions still apply underneath.
export const GET: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'customers.view');
	if ('response' in check) return check.response;
	const unavailable = featureUnavailable(check.access, 'communications.inbox');
	if (unavailable) return unavailable;

	const clientId = event.params.clientId;
	if (!clientId) return validationError({ form: 'Choose a valid conversation.' });

	const organizationId = check.auth.organization.id;
	const supabase = event.locals.supabase;

	const canSee = (permission: string | null) =>
		permission === null || hasPermission(check.access, permission);

	const requestedSection = event.url.searchParams.get('section');
	if (requestedSection !== null) {
		if (!isContextSection(requestedSection)) {
			return validationError({ section: 'Choose a valid section.' });
		}

		const formatting = await organizationFormatting(organizationId);
		const locale = formatting.ok ? formatting.formatting.locale : 'en-US';

		if (!canSee(CONTEXT_SECTION_PERMISSIONS[requestedSection])) {
			return json({ items: [], has_more: false, locale }, { headers: PRIVATE_READ_HEADERS });
		}

		const pricePermission = CONTEXT_SECTION_PRICE_PERMISSIONS[requestedSection];
		const read = await readContextSection(requestedSection, {
			supabase,
			organizationId,
			clientId,
			canSeePrice: pricePermission ? hasPermission(check.access, pricePermission) : false
		});
		if (!read.ok) return databaseError();

		return json(
			{ items: read.items, has_more: read.hasMore, locale },
			{ headers: PRIVATE_READ_HEADERS }
		);
	}

	const [clientResult, contactMethodsResult] = await Promise.all([
		supabase
			.from('clients')
			.select('id, display_name, company_name, client_type')
			.eq('id', clientId)
			.eq('organization_id', organizationId)
			.is('deleted_at', null)
			.maybeSingle(),
		supabase
			.from('client_contact_methods')
			.select('kind, value')
			.eq('client_id', clientId)
			.eq('organization_id', organizationId)
			.eq('is_primary', true)
	]);

	if (clientResult.error || contactMethodsResult.error) return databaseError();
	if (!clientResult.data) return notFound('That client could not be found.');

	const contactByKind = new Map(
		(contactMethodsResult.data ?? []).map((method) => [method.kind, method.value])
	);

	return json(
		{
			client: {
				...clientResult.data,
				email: contactByKind.get('email') ?? null,
				phone: contactByKind.get('phone') ?? null
			},
			sections: CONTEXT_SECTIONS.filter((section) => canSee(CONTEXT_SECTION_PERMISSIONS[section]))
		},
		{ headers: PRIVATE_READ_HEADERS }
	);
};
