import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireClientPermission } from '$lib/server/access/clients';
import { databaseError, validationError } from '$lib/server/api/errors';
import {
	clientWriteSchema,
	deriveClientDisplayName,
	zodFieldErrors
} from '$lib/server/validation/foundation.schema';
import {
	duplicateResponse,
	findExactDuplicates,
	readWriteFailure
} from '$lib/server/clients/duplicates';

const NOT_FOUND = { error: 'That client could not be found.' };

// Everything the create/edit form and the detail page need, in one request. The form reads the primary
// property; the detail page lists them all. Tags, notes, and attachments stay with the collaboration API,
// since their cards already own that data and write to it.
export const GET: RequestHandler = async (event) => {
	const access = await requireClientPermission(event, 'customers.view');
	if ('response' in access) return access.response;

	const organizationId = access.auth.organization.id;
	const clientId = event.params.id;
	const supabase = event.locals.supabase;

	const { data: client, error } = await supabase
		.from('clients')
		.select(
			'id, display_name, client_type, first_name, last_name, company_name, lifecycle_status, lead_source, lead_temperature, next_follow_up_at, converted_to_customer_at, archived_at, created_at, updated_at'
		)
		.eq('organization_id', organizationId)
		.eq('id', clientId)
		.is('deleted_at', null)
		.maybeSingle();
	if (error) return databaseError();
	if (!client) return json(NOT_FOUND, { status: 404 });

	const [
		{ data: contactMethods, error: contactMethodsError },
		{ data: properties, error: propertiesError },
		{ data: preferences, error: preferencesError },
		{ data: tagAssignments, error: tagAssignmentsError }
	] = await Promise.all([
		supabase
			.from('client_contact_methods')
			.select('id, kind, value, is_primary')
			.eq('organization_id', organizationId)
			.eq('client_id', clientId),
		supabase
			.from('properties')
			.select(
				'id, label, address_line1, address_line2, city, state_region, postal_code, country, access_notes, is_primary, is_billing_address, tax_rate_id'
			)
			.eq('organization_id', organizationId)
			.eq('client_id', clientId)
			.is('deleted_at', null),
		supabase
			.from('client_communication_preferences')
			.select(
				'contact_policy, quote_follow_ups, invoice_reminders, appointment_reminders, job_follow_ups, review_requests, marketing, sms_opt_out_at, sms_opt_in_at'
			)
			.eq('organization_id', organizationId)
			.eq('client_id', clientId)
			.maybeSingle(),
		supabase
			.from('tag_assignments')
			.select('tag_id')
			.eq('organization_id', organizationId)
			.eq('entity_type', 'client')
			.eq('entity_id', clientId)
	]);
	if (contactMethodsError || propertiesError || preferencesError || tagAssignmentsError)
		return databaseError();

	const primaryOf = (kind: 'email' | 'phone') =>
		(contactMethods ?? []).find((method) => method.kind === kind && method.is_primary)?.value ??
		null;

	return json({
		client: {
			...client,
			contact_methods: contactMethods ?? [],
			email: primaryOf('email'),
			phone: primaryOf('phone'),
			primary_property:
				(properties ?? []).find((property) => property.is_primary) ?? properties?.[0] ?? null,
			// Primary first, then the rest in a stable order, so the detail page's address list reads the
			// way the office thinks about it.
			properties: [...(properties ?? [])].sort((left, right) =>
				left.is_primary === right.is_primary
					? left.address_line1.localeCompare(right.address_line1)
					: left.is_primary
						? -1
						: 1
			),
			property_count: (properties ?? []).length,
			preferences,
			tag_ids: (tagAssignments ?? []).map((assignment) => assignment.tag_id)
		}
	});
};

export const PATCH: RequestHandler = async (event) => {
	const access = await requireClientPermission(event, 'customers.edit');
	if ('response' in access) return access.response;

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}

	const parsed = clientWriteSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const organizationId = access.auth.organization.id;
	const clientId = event.params.id;

	// The client being edited never counts as its own duplicate.
	const duplicates = await findExactDuplicates(event.locals.supabase, organizationId, {
		...parsed.data,
		excludeClientId: clientId
	});
	if ('failed' in duplicates) return databaseError();
	if (duplicates.matches.length > 0) return duplicateResponse(duplicates.matches);

	const { data, error } = await event.locals.supabase.rpc('update_client', {
		payload: {
			organization_id: organizationId,
			id: clientId,
			display_name: deriveClientDisplayName(parsed.data),
			...parsed.data
		}
	});

	if (error) {
		const failure = readWriteFailure(error);
		if (failure.kind === 'not_found') return json(NOT_FOUND, { status: 404 });
		if (failure.kind === 'duplicate') {
			const raced = await findExactDuplicates(event.locals.supabase, organizationId, {
				...parsed.data,
				excludeClientId: clientId
			});
			if ('failed' in raced) return databaseError();
			return duplicateResponse(raced.matches, failure.field);
		}
		// A customer cannot be turned back into a lead; the database says so and the office should see why.
		if (failure.kind === 'rule')
			return json({ error: failure.message, field_errors: {} }, { status: 422 });
		return databaseError();
	}

	return json({ client: data });
};
