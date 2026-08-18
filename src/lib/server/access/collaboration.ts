import { json } from '@sveltejs/kit';
import type { RequestEvent } from '@sveltejs/kit';
import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '$lib/database.types';
import { requireClientPermission } from '$lib/server/access/clients';
import { getOrganizationContext, type OrganizationContext } from '$lib/server/auth/organization';

export type LinkedEntityType = 'client' | 'property' | 'request';

// View follows the single customers.view gate for clients and properties (a Property's visibility already
// follows its owning Client). Manage differs: client-scoped writes ride customers.edit, property-scoped
// writes ride property.manage, matching private.can_manage_linked_entity in the migration.
function linkedEntityPermissionKey(
	entityType: Exclude<LinkedEntityType, 'request'>,
	mode: 'view' | 'manage'
): string {
	if (mode === 'view') return 'customers.view';
	return entityType === 'client' ? 'customers.edit' : 'property.manage';
}

export async function requireLinkedEntityAccess(
	event: RequestEvent,
	entityType: LinkedEntityType,
	mode: 'view' | 'manage'
): Promise<{ auth: OrganizationContext } | { response: Response }> {
	// Requests carry no permission keys of their own yet, so reaching a request's notes and files means
	// the same thing as reaching the request: membership. This mirrors private.can_manage_linked_entity,
	// and when request permissions land both sides change together.
	if (entityType === 'request') {
		const auth = await getOrganizationContext(event);
		if (!auth) {
			return {
				response: json(
					{ error: 'Authentication or organization membership required.' },
					{ status: 401 }
				)
			};
		}
		return { auth };
	}
	return requireClientPermission(event, linkedEntityPermissionKey(entityType, mode));
}

export function parseLinkedEntityQuery(
	url: URL
): { entity_type: LinkedEntityType; entity_id: string } | null {
	const entityType = url.searchParams.get('entity_type');
	const entityId = url.searchParams.get('entity_id');
	if (
		(entityType !== 'client' && entityType !== 'property' && entityType !== 'request') ||
		!entityId
	) {
		return null;
	}
	return { entity_type: entityType, entity_id: entityId };
}

// A pre-check ahead of the database's own polymorphic-entity trigger, so a bad entity_id fails with a
// clear 422 instead of a raw constraint error.
export async function linkedEntityBelongsToOrganization(
	supabase: SupabaseClient<Database>,
	organizationId: string,
	entityType: LinkedEntityType,
	entityId: string
): Promise<boolean> {
	// Requests are not soft-deleted — an unwanted one is archived — so only the two customer tables carry
	// the deleted_at filter.
	if (entityType === 'request') {
		const { data } = await supabase
			.from('requests')
			.select('id')
			.eq('id', entityId)
			.eq('organization_id', organizationId)
			.maybeSingle();
		return Boolean(data);
	}

	const table = entityType === 'client' ? 'clients' : 'properties';
	const { data } = await supabase
		.from(table)
		.select('id')
		.eq('id', entityId)
		.eq('organization_id', organizationId)
		.is('deleted_at', null)
		.maybeSingle();
	return Boolean(data);
}
