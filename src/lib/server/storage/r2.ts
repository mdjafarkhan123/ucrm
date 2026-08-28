import {
	S3Client,
	PutObjectCommand,
	GetObjectCommand,
	DeleteObjectCommand,
	HeadObjectCommand
} from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';
import { getR2Env, type R2Env } from './r2-env';
import type { LinkedEntityType } from '$lib/server/access/collaboration';

const UPLOAD_URL_TTL_SECONDS = 300;
const DOWNLOAD_URL_TTL_SECONDS = 300;

let cached: { env: R2Env; client: S3Client } | null = null;

function getR2(): { env: R2Env; client: S3Client } {
	if (cached) return cached;
	const r2Env = getR2Env();
	const client = new S3Client({
		region: 'auto',
		endpoint: r2Env.R2_ENDPOINT,
		credentials: {
			accessKeyId: r2Env.R2_ACCESS_KEY_ID,
			secretAccessKey: r2Env.R2_SECRET_ACCESS_KEY
		}
	});
	cached = { env: r2Env, client };
	return cached;
}

function sanitizeFileName(fileName: string): string {
	const cleaned = fileName.trim().replace(/[^a-zA-Z0-9._-]+/g, '_');
	return cleaned.slice(-140) || 'file';
}

// Scoping the key by organization and entity means a leaked or guessed object key still can't be paired
// with another organization's presigned request, since every operation re-derives the key server-side.
export function buildAttachmentObjectKey(
	organizationId: string,
	entityType: LinkedEntityType,
	entityId: string,
	fileName: string
): string {
	return `${organizationId}/${entityType}/${entityId}/${crypto.randomUUID()}-${sanitizeFileName(fileName)}`;
}

// The small copy lives beside its original and is always a JPEG. Deriving the key rather than generating a
// new one keeps the pair together, so the org/entity prefix check that guards attachment creation covers
// both, and deleting the row can find the preview without storing a second lookup.
export function buildThumbnailObjectKey(objectKey: string): string {
	return `${objectKey}.thumb.jpg`;
}

export const THUMBNAIL_MIME_TYPE = 'image/jpeg';

// A signature is not an attachment: it is never listed, never downloaded by name, and never shown beside
// a quote's files. Its own prefix keeps it out of every path that walks attachment keys.
export function buildSignatureObjectKey(organizationId: string, quoteId: string): string {
	return `${organizationId}/quote-signatures/${quoteId}/${crypto.randomUUID()}.png`;
}

// A logo is not an attachment either: one per organization, replaced rather than listed, and served
// inline from our own origin forever. Its own `<org>/logo/` prefix is what `set_organization_logo`
// checks, so a key issued for one organization can never be committed against another.
export function buildOrganizationLogoObjectKey(organizationId: string, fileName: string): string {
	return `${organizationId}/logo/${crypto.randomUUID()}-${sanitizeFileName(fileName)}`;
}

// The representative's signature image, uploaded as a file rather than drawn. Its own `<org>/
// quote-representative-signature/` prefix is what `set_organization_quote_representative` checks, matching
// the logo's trust boundary.
export function buildOrganizationQuoteRepresentativeSignatureObjectKey(
	organizationId: string,
	fileName: string
): string {
	return `${organizationId}/quote-representative-signature/${crypto.randomUUID()}-${sanitizeFileName(fileName)}`;
}

// A downloaded inbound attachment is never re-derivable from a presigned upload -- it already left the
// provider once. Its own `<org>/inbound-email-attachments/<message>/` prefix keeps it out of every path
// that walks contractor-uploaded attachments, matching the signature/logo prefixes' isolation.
export function buildInboundEmailAttachmentObjectKey(
	organizationId: string,
	inboundMessageId: string,
	fileName: string
): string {
	return `${organizationId}/inbound-email-attachments/${inboundMessageId}/${crypto.randomUUID()}-${sanitizeFileName(fileName)}`;
}

// The composer's paperclip. Its own `<org>/outbound-email-attachments/` prefix is what
// attach_communication_outbound_files checks server-side, matching every other upload's isolation.
export function buildOutboundEmailAttachmentObjectKey(
	organizationId: string,
	fileName: string
): string {
	return `${organizationId}/outbound-email-attachments/${crypto.randomUUID()}-${sanitizeFileName(fileName)}`;
}

export async function createPresignedUploadUrl(
	objectKey: string,
	mimeType: string
): Promise<string> {
	const { client, env } = getR2();
	const command = new PutObjectCommand({
		Bucket: env.R2_BUCKET,
		Key: objectKey,
		ContentType: mimeType
	});
	return getSignedUrl(client, command, { expiresIn: UPLOAD_URL_TTL_SECONDS });
}

// A signature is the one upload the browser never gets a presigned URL for. Presigning hands the caller
// a window to put whatever bytes they like at a key we then trust; a signature has to be the bytes we
// checked. So it arrives inside the request, is verified here, and is written by us.
export async function putObject(
	objectKey: string,
	body: Uint8Array,
	mimeType: string
): Promise<void> {
	const { client, env } = getR2();
	await client.send(
		new PutObjectCommand({
			Bucket: env.R2_BUCKET,
			Key: objectKey,
			Body: body,
			ContentType: mimeType,
			ContentLength: body.byteLength
		})
	);
}

export async function createPresignedDownloadUrl(
	objectKey: string,
	fileName: string
): Promise<string> {
	const { client, env } = getR2();
	const command = new GetObjectCommand({
		Bucket: env.R2_BUCKET,
		Key: objectKey,
		ResponseContentDisposition: `attachment; filename="${fileName.replace(/"/g, '')}"`
	});
	return getSignedUrl(client, command, { expiresIn: DOWNLOAD_URL_TTL_SECONDS });
}

// Photos are shown inline on the page, which a presigned link cannot do well: it expires after five
// minutes, so every image on a page left open goes broken. Reading the object here and streaming it back
// through our own route keeps an image a plain, permanent URL the browser can cache.
export async function getObjectStream(objectKey: string): Promise<{
	body: ReadableStream;
	contentType?: string;
	contentLength?: number;
}> {
	const { client, env } = getR2();
	const result = await client.send(new GetObjectCommand({ Bucket: env.R2_BUCKET, Key: objectKey }));
	if (!result.Body) throw new Error('That file is empty.');

	return {
		body: result.Body.transformToWebStream(),
		contentType: result.ContentType,
		contentLength: result.ContentLength
	};
}

// A presigned upload URL is a window to put whatever bytes the caller likes at a key we then trust. For
// a file we later serve inline from our own origin that is not good enough, so before the key is saved
// we ask storage what actually landed there.
// The outbound email worker needs the full bytes to hand Brevo as base64 -- a bounded fan-out over at
// most 10 attachments, unlike getObjectStream's browser-facing response which must not buffer.
export async function getObjectBytes(objectKey: string): Promise<Uint8Array> {
	const { client, env } = getR2();
	const result = await client.send(new GetObjectCommand({ Bucket: env.R2_BUCKET, Key: objectKey }));
	if (!result.Body) throw new Error('That file is empty.');
	return result.Body.transformToByteArray();
}

export async function headObject(
	objectKey: string
): Promise<{ contentType?: string; contentLength?: number }> {
	const { client, env } = getR2();
	const result = await client.send(
		new HeadObjectCommand({ Bucket: env.R2_BUCKET, Key: objectKey })
	);
	return { contentType: result.ContentType, contentLength: result.ContentLength };
}

export async function deleteObject(objectKey: string): Promise<void> {
	const { client, env } = getR2();
	await client.send(new DeleteObjectCommand({ Bucket: env.R2_BUCKET, Key: objectKey }));
}
