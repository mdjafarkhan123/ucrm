import {
	S3Client,
	PutObjectCommand,
	GetObjectCommand,
	DeleteObjectCommand
} from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';
import { getR2Env, type R2Env } from './r2-env';

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
	entityType: 'client' | 'property',
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

export async function deleteObject(objectKey: string): Promise<void> {
	const { client, env } = getR2();
	await client.send(new DeleteObjectCommand({ Bucket: env.R2_BUCKET, Key: objectKey }));
}
