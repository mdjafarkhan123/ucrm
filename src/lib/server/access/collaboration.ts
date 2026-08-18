import type { RequestEvent } from '@sveltejs/kit';
import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '$lib/database.types';
import { requireClientPermission } from '$lib/server/access/clients';
import type { OrganizationContext } from '$lib/server/auth/organization';

export type LinkedEntityType = 'client' | 'property';

// View follows the single customers.view gate for both entity types (a Property's visibility already
// follows its owning Client). Manage differs: client-scoped writes ride customers.edit, property-scoped
// writes ride property.manage, matching private.can_manage_linked_entity in the migration.
function linkedEntityPermissionKey(entityType: LinkedEntityType, mode: 'view' | 'manage'): string {
	if (mode === 'view') return 'customers.view';
	return entityType === 'client' ? 'customers.edit' : 'property.manage';
}

export async function requireLinkedEntityAccess(
	event: RequestEvent,
	entityType: LinkedEntityType,
	mode: 'view' | 'manage'
): Promise<{ auth: OrganizationContext } | { response: Response }> {
	return requireClientPermission(event, linkedEntityPermissionKey(entityType, mode));
}

export function parseLinkedEntityQuery(
	url: URL
): { entity_type: LinkedEntityType; entity_id: string } | null {
	const entityType = url.searchParams.get('entity_type');
	const entityId = url.searchParams.get('entity_id');
	if ((entityType !== 'client' && entityType !== 'property') || !entityId) return null;
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
