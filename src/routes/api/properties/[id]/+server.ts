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
			// An empty box means the office cleared the field, so it is stored as nothing rather than "".
			label: label?.trim() || undefined,
			address_line2: address_line2?.trim() || null,
			state_region: state_region?.trim() || null,
			postal_code: postal_code?.trim() || null,
			access_notes: access_notes?.trim() || null
		})
		.eq('id', event.params.id)
		.eq('organization_id', access.auth.organization.id)
		.is('deleted_at', null)
		.select(
			'id, label, address_line1, address_line2, city, state_region, postal_code, country, access_notes, is_primary, is_billing_address'
		)
		.maybeSingle();

	if (error) return databaseError();
	if (!data) return json(NOT_FOUND, { status: 404 });
	return json({ property: data });
};

// Removes one property from its client. The work happens in `public.delete_property` so the soft delete and
// the promotion of a replacement primary share a transaction — split across two requests, the first would be
// refused by the deferred check that a client with properties has exactly one primary.
export const DELETE: RequestHandler = async (event) => {
	const access = await requireClientPermission(event, 'property.manage');
	if ('response' in access) return access.response;

	const { error } = await event.locals.supabase.rpc('delete_property', {
		p_property_id: event.params.id
	});

	// RLS hides other organizations' rows, so a property this member cannot reach reads as missing.
	if (error?.code === 'P0002') return json(NOT_FOUND, { status: 404 });
	if (error) return databaseError();
	return new Response(null, { status: 204 });
};
