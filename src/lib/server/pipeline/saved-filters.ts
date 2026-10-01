import { json } from '@sveltejs/kit';
import type { PostgrestError } from '@supabase/supabase-js';
import { databaseError, notFound, validationError } from '$lib/server/api/errors';
import type { OrganizationContext } from '$lib/server/auth/organization';
import type { SavedFilter } from '$lib/pipeline/api';

export const SAVED_FILTER_NOT_FOUND =
	'That saved filter could not be found. Refresh and try again.';
export const SAVED_FILTER_COLUMNS = 'id, name, query, user_id';

// Owners and administrators share filters with the team and look after the shared list. The same people
// `private.is_organization_admin` lets through in the table's policies.
export function canShareFilters(auth: OrganizationContext) {
	return auth.organization.role === 'owner' || auth.organization.role === 'admin';
}

type SavedFilterRow = { id: string; name: string; query: string; user_id: string | null };

export function presentSavedFilter(row: SavedFilterRow, canShare: boolean): SavedFilter {
	const shared = row.user_id === null;
	return {
		id: row.id,
		name: row.name,
		query: row.query,
		shared,
		// Your own filters are always yours to change; the shared ones only an administrator's.
		can_edit: !shared || canShare
	};
}

// The table answers in database codes; a person should read a sentence. A second "Hot leads" in the same
// list is the name's fault, a full list is the form's, and a refusal from the policies is a permission
// problem the route has already told the caller about — so it is reported the same way.
export function savedFilterWriteError(error: PostgrestError) {
	if (error.code === '23505')
		return validationError({ name: 'You already have a filter with that name.' }, 409);
	if (error.code === '23514') return validationError({ form: error.message });
	if (error.code === '42501')
		return json({ error: 'You do not have access to change that filter.' }, { status: 403 });
	return databaseError();
}

export function savedFilterMissing() {
	return notFound(SAVED_FILTER_NOT_FOUND);
}
