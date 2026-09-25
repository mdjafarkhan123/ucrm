import { error as httpError } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { fileShareTokenHash, resolveFileShare } from '$lib/server/files/share-links';
import { streamOrganizationLogo } from '$lib/server/settings/logo';

// The business logo on a file share's page. A share is a set of files rather than an issued document, so
// it shows the business's current logo; the object key itself never reaches the browser. A turned-off or
// expired link still shows it, above the business's phone and email.
export const GET: RequestHandler = async (event) => {
	const tokenHash = fileShareTokenHash(event.params.token);
	const share = tokenHash ? await resolveFileShare(tokenHash) : null;
	const objectKey = share?.business.logo_object_key;
	if (!objectKey) throw httpError(404, 'No logo is available.');

	return streamOrganizationLogo(objectKey, event.request.headers.get('if-none-match'));
};
