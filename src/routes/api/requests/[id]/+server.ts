import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganization } from '$lib/server/auth/organization';
import {
	NO_STORE_HEADERS,
	PRIVATE_READ_HEADERS,
	databaseError,
	notFound,
	unauthorized,
	validationError
} from '$lib/server/api/errors';
import { requestPatchSchema, zodFieldErrors } from '$lib/server/validation/foundation.schema';
import { deriveRequestStatus } from '$lib/server/requests/status';
import { organizationTimezone } from '$lib/server/requests/timezone';
import { embeddedOne } from '$lib/server/api/embedded';

const NOT_FOUND = 'That request could not be found.';

const DETAIL_SELECT = `id, client_id, property_id, title, description, service_type, source, preferred_time, status, created_at, updated_at,
	 client:clients!requests_client_organization_fk(id, display_name, company_name, client_type),
	 property:properties!requests_property_organization_fk(id, label, address_line1, address_line2, city, state_region, postal_code, country, access_notes),
	 assessment:assessments(id, starts_at, ends_at, all_day, instructions, completed_at)`;

// Everything the detail page's blocks read, in one round trip. Notes, tags, and attachments stay with the
// collaboration API — those cards already own their own data and write to it.
export const GET: RequestHandler = async (event) => {
	const auth = await requireOrganization(event);
	if (!auth) return unauthorized();

	const organizationId = auth.organization.id;
	const supabase = event.locals.supabase;

	const { data: row, error } = await supabase
		.from('requests')
		.select(DETAIL_SELECT)
		.eq('organization_id', organizationId)
		.eq('id', event.params.id)
		.maybeSingle();
	if (error) return databaseError();
	if (!row) return notFound(NOT_FOUND);

	const assessment = embeddedOne(row.assessment);
	const [
		{ data: assignees, error: assigneesError },
		{ data: contactMethods, error: contactMethodsError },
		timezone
	] = await Promise.all([
		assessment
			? supabase
					.from('assessment_assignees')
					.select('user_id')
					.eq('organization_id', organizationId)
					.eq('assessment_id', assessment.id)
			: Promise.resolve({ data: [], error: null }),
		supabase
			.from('client_contact_methods')
			.select('kind, value')
			.eq('organization_id', organizationId)
			.eq('client_id', row.client_id)
			.eq('is_primary', true),
		organizationTimezone(supabase, organizationId)
	]);
	if (assigneesError || contactMethodsError) return databaseError();

	return json(
		{
			request: {
				...row,
				client: embeddedOne(row.client),
				property: embeddedOne(row.property),
				assessment: assessment
					? { ...assessment, assignee_ids: (assignees ?? []).map((row) => row.user_id) }
					: null,
				stored_status: row.status,
				status: deriveRequestStatus(row.status, assessment, timezone),
				email: (contactMethods ?? []).find((method) => method.kind === 'email')?.value ?? null,
				phone: (contactMethods ?? []).find((method) => method.kind === 'phone')?.value ?? null
			}
		},
		{ headers: PRIVATE_READ_HEADERS }
	);
};

// Partial by design: every block on the detail page saves only the fields it owns, the moment the office
// hits Save on that block.
export const PATCH: RequestHandler = async (event) => {
	const auth = await requireOrganization(event);
	if (!auth) return unauthorized();

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}

	const parsed = requestPatchSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const organizationId = auth.organization.id;
	const supabase = event.locals.supabase;
	const patch = parsed.data;

	const { data: existing, error: existingError } = await supabase
		.from('requests')
		.select('id, client_id, property_id')
		.eq('organization_id', organizationId)
		.eq('id', event.params.id)
		.maybeSingle();
	if (existingError) return databaseError();
	if (!existing) return notFound(NOT_FOUND);

	// A property belongs to exactly one client, so moving a request to another client without naming the
	// property would leave it pointing at an address that client does not own.
	const clientId = patch.client_id ?? existing.client_id;
	const propertyId = patch.property_id ?? existing.property_id;
	if (patch.client_id && !patch.property_id && patch.client_id !== existing.client_id) {
		return validationError({ property_id: 'Choose which property of the new client to use.' });
	}

	if (patch.client_id || patch.property_id) {
		const [{ data: client }, { data: property }] = await Promise.all([
			supabase
				.from('clients')
				.select('id')
				.eq('organization_id', organizationId)
				.eq('id', clientId)
				.is('deleted_at', null)
				.maybeSingle(),
			supabase
				.from('properties')
				.select('id')
				.eq('organization_id', organizationId)
				.eq('id', propertyId)
				.eq('client_id', clientId)
				.is('deleted_at', null)
				.maybeSingle()
		]);
		if (!client) return validationError({ client_id: 'Choose a client in your organization.' });
		if (!property)
			return validationError({ property_id: 'Choose a property belonging to this client.' });
	}

	const { data, error } = await supabase
		.from('requests')
		.update({ ...patch, client_id: clientId, property_id: propertyId })
		.eq('organization_id', organizationId)
		.eq('id', event.params.id)
		.select('id, title, description, service_type, preferred_time, status, updated_at')
		.maybeSingle();
	if (error) return databaseError();
	if (!data) return notFound(NOT_FOUND);

	return json({ request: data }, { headers: NO_STORE_HEADERS });
};
