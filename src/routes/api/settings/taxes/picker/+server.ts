import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getOrganizationContext } from '$lib/server/auth/organization';
import { resolveOrganizationAccess } from '$lib/server/access/effective';
import { hasPermission } from '$lib/server/access/permission';
import { PRIVATE_READ_HEADERS, databaseError, validationError } from '$lib/server/api/errors';

// The Taxes destination itself is owner/admin only, but a Quote or Property editor with neither key still
// needs the active rate list and the resolved Business default to populate a picker — so this read is gated
// on any one of the three permissions that can reach a tax choice, not on `settings.taxes.manage` alone.
export const GET: RequestHandler = async (event) => {
	const auth = await getOrganizationContext(event);
	if (!auth)
		return json({ error: 'Authentication or organization membership required.' }, { status: 401 });

	let access;
	try {
		access = await resolveOrganizationAccess(
			event.locals.supabase,
			auth.organization.id,
			auth.user.id
		);
	} catch {
		return databaseError();
	}

	const canView =
		hasPermission(access, 'quotes.edit') ||
		hasPermission(access, 'property.manage') ||
		hasPermission(access, 'settings.taxes.manage');
	if (!canView) {
		return json(
			{ error: 'You do not have access to view tax settings.', reason: 'permission_denied' },
			{ status: 403 }
		);
	}

	const propertyId = event.url.searchParams.get('property_id');
	if (propertyId && !/^[0-9a-f-]{36}$/i.test(propertyId)) {
		return validationError({ property_id: 'That property could not be found.' });
	}

	const organizationId = auth.organization.id;

	// Business default is always resolved; the property-effective answer only exists when a Quote (which
	// always has a property) is asking — a bare Property dialog has nothing to inherit from itself.
	const [ratesResult, businessDefaultResult, propertyDefaultResult] = await Promise.all([
		event.locals.supabase
			.from('organization_tax_rates')
			.select('id, name, rate_basis_points')
			.eq('organization_id', organizationId)
			.eq('is_active', true)
			.order('name'),
		event.locals.supabase.rpc('organization_tax_picker', {
			target_organization_id: organizationId,
			target_property_id: null
		}),
		propertyId
			? event.locals.supabase.rpc('organization_tax_picker', {
					target_organization_id: organizationId,
					target_property_id: propertyId
				})
			: Promise.resolve({ data: null, error: null })
	]);

	if (ratesResult.error || businessDefaultResult.error || propertyDefaultResult.error)
		return databaseError();

	const firstRow = (rows: typeof businessDefaultResult.data) =>
		(rows ?? [])[0] ?? {
			source: 'not_configured',
			name: null,
			rate_basis_points: 0,
			rate_id: null
		};

	return json(
		{
			rates: ratesResult.data ?? [],
			business_default: firstRow(businessDefaultResult.data),
			property_default: propertyId ? firstRow(propertyDefaultResult.data) : null
		},
		{ headers: PRIVATE_READ_HEADERS }
	);
};
