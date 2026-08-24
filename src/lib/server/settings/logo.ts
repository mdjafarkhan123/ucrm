import { json } from '@sveltejs/kit';
import { LOGO_MIME_TYPES } from '$lib/server/validation/settings.schema';
import { getObjectStream } from '$lib/server/storage/r2';

// The stable application URL for the business logo. The picture behind it changes; the address does not,
// so the sidebar and any customer document can point at it with a plain `<img src>`. The revision on the
// end is what makes a replaced logo appear at once — the image itself is cached for a day.
export function organizationLogoUrl(revision: number) {
	return `/api/settings/branding/logo/view?v=${revision}`;
}

// Every upload gets a fresh uuid in its key, and the part after the organization prefix is exactly that:
// unique per upload, and no organization id in a header.
export function organizationLogoEtag(objectKey: string) {
	return `"${objectKey.split('/logo/')[1] ?? objectKey}"`;
}

/**
 * Streams a logo the caller has already been authorised to see. Deliberately knows nothing about who is
 * asking: the member route checks a permission, and the customer route will resolve a document access
 * token. Both end up here so the bytes are served the same safe way.
 */
export async function streamOrganizationLogo(
	objectKey: string,
	requestEtag: string | null
): Promise<Response> {
	const etag = organizationLogoEtag(objectKey);
	if (requestEtag === etag) return new Response(null, { status: 304, headers: { etag } });

	try {
		const object = await getObjectStream(objectKey);
		const contentType = (LOGO_MIME_TYPES as readonly string[]).includes(object.contentType ?? '')
			? (object.contentType as string)
			: 'image/png';

		return new Response(object.body, {
			headers: {
				'content-type': contentType,
				...(object.contentLength ? { 'content-length': String(object.contentLength) } : {}),
				etag,
				'x-content-type-options': 'nosniff',
				// Private because a permission check or an access token is the only thing between this and
				// another organization's branding. Cached for a day because the sidebar asks for this on
				// every page: a short window would have every signed-in person revalidating all day, and
				// each revalidation still costs the permission lookup and the settings read even when it
				// answers 304. A replaced logo does not wait for that day — callers that need it
				// immediately use the `?v=<revision>` URL the business read hands out, which is a
				// different cache entry the moment anything is saved. The ETag covers the bare URL.
				'cache-control': 'private, max-age=86400'
			}
		});
	} catch {
		return json(
			{ error: 'File storage is not configured yet. Ask an admin to set up Cloudflare R2.' },
			{ status: 503 }
		);
	}
}
