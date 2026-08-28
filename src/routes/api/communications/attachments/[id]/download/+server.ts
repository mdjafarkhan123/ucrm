import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getOrganizationContext } from '$lib/server/auth/organization';
import { resolveOrganizationAccess } from '$lib/server/access/effective';
import { hasPermission } from '$lib/server/access/permission';
import { NO_STORE_HEADERS, databaseError, notFound, unauthorized } from '$lib/server/api/errors';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { createPresignedDownloadUrl } from '$lib/server/storage/r2';

// Mirrors /api/communications/inbound-attachments/[id]/download's authorization exactly -- the provider
// URL never reaches the browser and every download is authorized here. Unlike that route, there is no
// status to check: communication_outbound_attachments has no status column by design (a row exists only
// for a file that already sent successfully), so an existing row with an object_key is always available.
export const GET: RequestHandler = async (event) => {
	const auth = await getOrganizationContext(event);
	if (!auth) return unauthorized();

	let access;
	try {
		access = await resolveOrganizationAccess(
			event.locals.supabase,
			auth.organization.id,
			auth.user.id
		);
	} catch (error) {
		console.error('Could not resolve attachment access.', error);
		return databaseError();
	}
	const canView =
		hasPermission(access, 'conversations.view_team') ||
		hasPermission(access, 'conversations.view_assigned');
	if (!canView) {
		return json(
			{ error: 'You do not have access to conversations.', reason: 'permission_denied' },
			{ status: 403, headers: NO_STORE_HEADERS }
		);
	}

	const ownerClient = getOwnerSupabaseClient();
	const { data: attachment, error } = await ownerClient
		.from('communication_outbound_attachments')
		.select('object_key, file_name')
		.eq('organization_id', auth.organization.id)
		.eq('id', event.params.id)
		.maybeSingle();
	if (error) return databaseError();
	if (!attachment) return notFound('That file is not available.');

	try {
		const downloadUrl = await createPresignedDownloadUrl(
			attachment.object_key,
			attachment.file_name
		);
		return json({ download_url: downloadUrl }, { headers: NO_STORE_HEADERS });
	} catch {
		return json(
			{ error: 'File storage is not configured yet. Ask an admin to set up Cloudflare R2.' },
			{ status: 503, headers: NO_STORE_HEADERS }
		);
	}
};
