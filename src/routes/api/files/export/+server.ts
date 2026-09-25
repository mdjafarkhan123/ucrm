import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { NO_STORE_HEADERS, PRIVATE_READ_HEADERS, databaseError } from '$lib/server/api/errors';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';

// "Export everything" (Files and Media, Part 8B). files.export is owner-only in role_permissions
// (20260925140000_files_media_organization_export.sql), so a member without it never reaches this --
// there is no further role check to write here.
export const POST: RequestHandler = async (event) => {
	const access = await requireOrganizationPermission(event, 'files.export');
	if ('response' in access) return access.response;

	const { data, error } = await getOwnerSupabaseClient().rpc('request_organization_export', {
		target_organization_id: access.auth.organization.id,
		target_actor_id: access.auth.user.id
	});
	if (error) {
		console.error('Could not start an organization export.', error);
		return databaseError();
	}

	return json({ export: data }, { status: 202, headers: NO_STORE_HEADERS });
};

const HISTORY_LIMIT = 10;

// The last few exports for this organization -- queued/processing so the button can say "in progress",
// available so it can offer a download, failed/expired so the owner is not left guessing. Read under the
// caller's own policies (files.export-gated RLS), same shape as GET /api/files/shares.
export const GET: RequestHandler = async (event) => {
	const access = await requireOrganizationPermission(event, 'files.export');
	if ('response' in access) return access.response;

	const { data, error } = await event.locals.supabase
		.from('organization_exports')
		.select('id, status, file_count, total_bytes, error, requested_at, completed_at, expires_at')
		.order('requested_at', { ascending: false })
		.limit(HISTORY_LIMIT);
	if (error) {
		console.error('Could not list organization exports.', error);
		return databaseError();
	}

	return json({ exports: data ?? [] }, { headers: PRIVATE_READ_HEADERS });
};
