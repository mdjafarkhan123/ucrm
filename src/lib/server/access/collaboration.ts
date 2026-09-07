import { json } from '@sveltejs/kit';
import type { RequestEvent } from '@sveltejs/kit';
import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '$lib/database.types';
import { requireClientPermission } from '$lib/server/access/clients';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { getOrganizationContext, type OrganizationContext } from '$lib/server/auth/organization';

export type LinkedEntityType =
	'client' | 'property' | 'request' | 'quote' | 'job_expense' | 'job' | 'visit';

// View follows the single customers.view gate for clients and properties (a Property's visibility already
// follows its owning Client). Manage differs: client-scoped writes ride customers.edit, property-scoped
// writes ride property.manage, matching private.can_manage_linked_entity in the migration.
function linkedEntityPermissionKey(
	entityType: Exclude<LinkedEntityType, 'request' | 'quote' | 'job_expense' | 'job' | 'visit'>,
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
	// A quote's notes and files follow the quote itself: reading one needs quotes.view, writing to one
	// needs quotes.edit. Same pair the quote's own routes use, and the same pair the database checks.
	if (entityType === 'quote') {
		const check = await requireOrganizationPermission(
			event,
			mode === 'view' ? 'quotes.view' : 'quotes.edit'
		);
		return 'response' in check ? { response: check.response } : { auth: check.auth };
	}

	// A job expense's receipt follows the expense. The coarse gate here is jobs.view — the same one that
	// lets a person open the job — because the fine own/team rule (my own expense with expenses.record, or
	// anyone's with expenses.manage_team) is a row-level fact the attachments table's own RLS already
	// enforces through can_view_linked_entity / can_manage_linked_entity. A flat permission cannot express
	// it, and a second copy here would be a second place to get it wrong.
	if (entityType === 'job_expense') {
		const check = await requireOrganizationPermission(event, 'jobs.view');
		return 'response' in check ? { response: check.response } : { auth: check.auth };
	}

	// Job and visit records take the same shape for the same reason. Jobber puts notes and files beside the
	// Jobs ladder rather than inside it, so the coarse gate here is jobs.view — being able to open the job —
	// and never jobs.edit. Whether this person may write, and whether the row is theirs, is the row-level
	// field_records.record / field_records.manage_team rule that private.can_manage_linked_record enforces.
	if (entityType === 'job' || entityType === 'visit') {
		const check = await requireOrganizationPermission(event, 'jobs.view');
		return 'response' in check ? { response: check.response } : { auth: check.auth };
	}

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
		(entityType !== 'client' &&
			entityType !== 'property' &&
			entityType !== 'request' &&
			entityType !== 'quote' &&
			entityType !== 'job_expense' &&
			entityType !== 'job' &&
			entityType !== 'visit') ||
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
	// Requests, quotes, job expenses, jobs and visits are not soft-deleted — an unwanted one is archived or
	// removed — so only the two customer tables carry the deleted_at filter.
	if (
		entityType === 'request' ||
		entityType === 'quote' ||
		entityType === 'job_expense' ||
		entityType === 'job' ||
		entityType === 'visit'
	) {
		const table =
			entityType === 'request'
				? 'requests'
				: entityType === 'quote'
					? 'quotes'
					: entityType === 'job_expense'
						? 'job_expenses'
						: entityType === 'job'
							? 'jobs'
							: 'job_visits';
		const { data } = await supabase
			.from(table)
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
