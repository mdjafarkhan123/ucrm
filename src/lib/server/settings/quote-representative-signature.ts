import { json } from '@sveltejs/kit';
import {
	buildOrganizationQuoteRepresentativeSignatureObjectKey,
	deleteObject,
	getObjectStream,
	putObject
} from '$lib/server/storage/r2';
import {
	decodeSignatureImage,
	discardSignatureImage,
	SIGNATURE_MIME_TYPE
} from '$lib/server/quotes/signatures';
import { QUOTE_REPRESENTATIVE_SIGNATURE_MIME_TYPES } from '$lib/server/validation/settings.schema';

export { decodeSignatureImage, discardSignatureImage };

// Same stable-URL reasoning as the logo: a presigned link expires in five minutes, so the customer preview
// and the Settings page both need a permanent address instead. The revision on the end is what makes a
// replaced signature appear at once; the object itself is cached for a day.
export function organizationQuoteRepresentativeSignatureUrl(revision: number) {
	return `/api/settings/quotes/representative/signature-view?v=${revision}`;
}

function representativeSignatureEtag(objectKey: string) {
	return `"${objectKey.split('/quote-representative-signature/')[1] ?? objectKey}"`;
}

export async function streamRepresentativeSignature(
	objectKey: string,
	requestEtag: string | null
): Promise<Response> {
	const etag = representativeSignatureEtag(objectKey);
	if (requestEtag === etag) return new Response(null, { status: 304, headers: { etag } });

	try {
		const object = await getObjectStream(objectKey);
		const contentType = (QUOTE_REPRESENTATIVE_SIGNATURE_MIME_TYPES as readonly string[]).includes(
			object.contentType ?? ''
		)
			? (object.contentType as string)
			: SIGNATURE_MIME_TYPE;

		return new Response(object.body, {
			headers: {
				'content-type': contentType,
				...(object.contentLength ? { 'content-length': String(object.contentLength) } : {}),
				etag,
				'x-content-type-options': 'nosniff',
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

// A drawn representative signature is stored the same way a Quote signature is: decoded and verified on the
// server, never trusted from a presigned upload. An uploaded file goes through the presigned-URL route
// instead (settings/quotes/representative/signature-upload), same as the logo.
export async function storeDrawnRepresentativeSignature(
	organizationId: string,
	image: { bytes: Uint8Array }
): Promise<string> {
	const objectKey = buildOrganizationQuoteRepresentativeSignatureObjectKey(
		organizationId,
		'drawn.png'
	);
	await putObject(objectKey, image.bytes, SIGNATURE_MIME_TYPE);
	return objectKey;
}

export async function discardRepresentativeSignature(
	objectKey: string | null | undefined
): Promise<void> {
	if (!objectKey) return;
	try {
		await deleteObject(objectKey);
	} catch {
		// Best effort, matching discardSignatureImage: an orphaned object is cheaper than a broken save.
	}
}
