import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import {
	databaseError,
	notFound,
	PRIVATE_READ_HEADERS,
	validationError
} from '$lib/server/api/errors';

// Part 5D's work-context right panel: one client's identity, contact methods, and a small recent set of
// its real related work. Every category rides the same row-level security its own feature already
// enforces (quotes.view on `quotes`, pipeline.view on `opportunities`) -- a viewer without one of those
// permissions gets an empty array back from Postgres itself, not a 403 or a hidden count, which is exactly
// the "no disclosure for denied domains" behavior the approved plan asks for. Requests carry no extra
// permission beyond organization membership, matching `GET /api/requests`.
const RELATED_WORK_LIMIT = 3;

export const GET: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'customers.view');
	if ('response' in check) return check.response;

	const clientId = event.params.clientId;
	if (!clientId) return validationError({ form: 'Choose a valid conversation.' });

	const organizationId = check.auth.organization.id;
	const supabase = event.locals.supabase;

	const [
		clientResult,
		contactMethodsResult,
		propertiesResult,
		requestsResult,
		quotesResult,
		opportunitiesResult
	] = await Promise.all([
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
			.eq('is_primary', true),
		// `properties_client_active_idx (client_id, deleted_at, created_at)` gives this its scan and its
		// order for free -- ordering by created_at rather than is_primary/updated_at is what rides that
		// index instead of sorting after the fact.
		supabase
			.from('properties')
			.select('id, label, address_line1, city, state_region, postal_code')
			.eq('client_id', clientId)
			.eq('organization_id', organizationId)
			.is('deleted_at', null)
			.order('created_at', { ascending: false })
			.limit(RELATED_WORK_LIMIT),
		supabase
			.from('requests')
			.select('id, title, status, created_at')
			.eq('client_id', clientId)
			.eq('organization_id', organizationId)
			.order('created_at', { ascending: false })
			.limit(RELATED_WORK_LIMIT),
		supabase
			.from('quotes')
			.select('id, quote_number, title, status, created_at')
			.eq('client_id', clientId)
			.eq('organization_id', organizationId)
			.order('created_at', { ascending: false })
			.limit(RELATED_WORK_LIMIT),
		supabase
			.from('opportunities')
			.select('id, title, stage, created_at')
			.eq('client_id', clientId)
			.eq('organization_id', organizationId)
			.order('created_at', { ascending: false })
			.limit(RELATED_WORK_LIMIT)
	]);

	if (
		clientResult.error ||
		contactMethodsResult.error ||
		propertiesResult.error ||
		requestsResult.error ||
		quotesResult.error ||
		opportunitiesResult.error
	) {
		return databaseError();
	}
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
			properties: propertiesResult.data ?? [],
			requests: requestsResult.data ?? [],
			quotes: quotesResult.data ?? [],
			opportunities: opportunitiesResult.data ?? []
		},
		{ headers: PRIVATE_READ_HEADERS }
	);
};
