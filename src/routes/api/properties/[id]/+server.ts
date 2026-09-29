import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireClientPermission } from '$lib/server/access/clients';
import { databaseError, validationError } from '$lib/server/api/errors';
import { propertyAddressSchema, zodFieldErrors } from '$lib/server/validation/foundation.schema';

const NOT_FOUND = { error: 'That address could not be found.' };

// Edits one property's address in place. The client it belongs to never moves here, and neither does
// which property is primary — both would be a different decision than "fix this address".
export const PATCH: RequestHandler = async (event) => {
	const access = await requireClientPermission(event, 'property.manage');
	if ('response' in access) return access.response;

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}

	const parsed = propertyAddressSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const { label, address_line2, state_region, postal_code, access_notes, ...rest } = parsed.data;

	const { data, error } = await event.locals.supabase
		.from('properties')
		.update({
			...rest,
			// An empty box means the office cleared the field, so it is stored as nothing rather than "". An
			// absent name is left alone.
			label: label === undefined ? undefined : label.trim() || null,
			address_line2: address_line2?.trim() || null,
			state_region: state_region?.trim() || null,
			postal_code: postal_code?.trim() || null,
			access_notes: access_notes?.trim() || null
		})
		.eq('id', event.params.id)
		.eq('organization_id', access.auth.organization.id)
		.is('deleted_at', null)
		.select(
			'id, label, address_line1, address_line2, city, state_region, postal_code, country, access_notes, is_primary, is_billing_address, tax_rate_id'
		)
		.maybeSingle();

	// A rate id from another organization, or one that no longer exists, fails the composite tenant-safe FK
	// rather than any check this route runs itself.
	if (error?.code === '23503')
		return validationError({ tax_rate_id: 'Choose a tax rate from your organization.' });
	if (error) return databaseError();
	if (!data) return json(NOT_FOUND, { status: 404 });
	return json({ property: data });
};

// Deletes one property for good, together with the requests, quotes and jobs at that address, the way Jobber
// does. `public.delete_property` owns the whole thing in one transaction: the permission checks, the refusal
// when any of that work was invoiced, paid a deposit or was sent to the customer, the cascade, and the
// promotion of a replacement primary the deferred one-primary check requires.
export const DELETE: RequestHandler = async (event) => {
	const access = await requireClientPermission(event, 'property.manage');
	if ('response' in access) return access.response;

	const { error } = await event.locals.supabase.rpc('delete_property', {
		p_property_id: event.params.id
	});

	// A property this member cannot reach reads as missing, never as someone else's.
	if (error?.code === 'P0002') return json(NOT_FOUND, { status: 404 });
	// The database writes these for people: which record blocks the delete, or which permission is missing.
	if (error?.code === '23514' || error?.code === 'P0409')
		return json({ error: error.message }, { status: 409 });
	if (error?.code === '42501') return json({ error: error.message }, { status: 403 });
	if (error) return databaseError();
	return new Response(null, { status: 204 });
};
