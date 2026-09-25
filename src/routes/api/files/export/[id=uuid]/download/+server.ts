import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { databaseError } from '$lib/server/api/errors';
import { createPresignedDownloadUrl } from '$lib/server/storage/r2';

// Unlike the customer file share (Part 7D), this download needs no bearer token: the owner is already
// signed in, so files.export plus the row's own organization_id -- both already enforced by RLS on the
// select below -- are the whole gate. A presigned URL is minted fresh per click, matching /api/files/[id]/download.
export const GET: RequestHandler = async (event) => {
	const access = await requireOrganizationPermission(event, 'files.export');
	if ('response' in access) return access.response;

	const { data: exportRow, error } = await event.locals.supabase
		.from('organization_exports')
		.select('id, status, object_key')
		.eq('id', event.params.id)
		.maybeSingle();
	if (error) {
		console.error('Could not look up an organization export for download.', error);
		return databaseError();
	}
	if (!exportRow || exportRow.status !== 'available' || !exportRow.object_key) {
		return json({ error: 'That export is not ready to download.' }, { status: 404 });
	}

	try {
		const downloadUrl = await createPresignedDownloadUrl(
			exportRow.object_key,
			'organization-export.zip'
		);
		return json({ download_url: downloadUrl });
	} catch {
		return json(
			{ error: 'File storage is not configured yet. Ask an admin to set up Cloudflare R2.' },
			{ status: 503 }
		);
	}
};
