import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getOrganizationContext } from '$lib/server/auth/organization';
import { databaseError, validationError } from '$lib/server/api/errors';
import { createPresignedDownloadUrl } from '$lib/server/storage/r2';

// Hands the office a file to keep. Short-lived and single-purpose: the link is minted per click, so a URL
// that leaks out of a chat log is useless minutes later.
export const GET: RequestHandler = async (event) => {
	const fileId = event.params.id;
	if (!/^[0-9a-f-]{36}$/i.test(fileId)) return validationError({ id: 'That file was not found.' });

	const auth = await getOrganizationContext(event);
	if (!auth)
		return json({ error: 'Authentication or organization membership required.' }, { status: 401 });

	const { data: file, error } = await event.locals.supabase
		.from('files')
		.select('id, display_name, object_key, processing_state')
		.eq('id', fileId)
		.maybeSingle();
	if (error) return databaseError();
	if (!file) return json({ error: 'That file was not found.' }, { status: 404 });
	if (file.processing_state !== 'available')
		return json({ error: 'That file is not ready yet.' }, { status: 409 });

	try {
		// The saved filename is the File's display name, so a renamed file downloads under the name the
		// office gave it rather than the storage key's uuid.
		const downloadUrl = await createPresignedDownloadUrl(file.object_key, file.display_name);
		return json({ download_url: downloadUrl });
	} catch {
		return json(
			{ error: 'File storage is not configured yet. Ask an admin to set up Cloudflare R2.' },
			{ status: 503 }
		);
	}
};
