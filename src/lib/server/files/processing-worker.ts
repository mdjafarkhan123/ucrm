// The Files and Media processing pipeline.
//
// One pass per upload, and only one: the object is read out of R2 a single time, and the same chunks feed
// the signature sample, the checksum and the malware scanner as they go by. A 100 MB file therefore costs
// one download and a few kilobytes of memory rather than a 100 MB buffer, which is what makes a bounded
// worker on a single container the right shape for this instead of a worker fleet. The one exception is
// an image small enough to deserve a preview: those bytes are kept, because no image decoder can work
// from a stream, and the cap in `derivatives.ts` is what keeps that bounded.
//
// The states a File can leave here in:
//   available    - size, signature and scan all agreed. The only path to a usable File.
//   failed       - the file is not what it claimed to be, or is not a type we accept.
//   quarantined  - the scanner found something. The object stays in R2, unreadable, for the purge sweep.
//   pending      - our own infrastructure could not do the check. The claim is handed back and retried.

import { createHash } from 'node:crypto';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import {
	THUMBNAIL_MIME_TYPE,
	buildThumbnailObjectKey,
	deleteObject,
	getObjectStream,
	headObject,
	putObject
} from '$lib/server/storage/r2';
import { createThumbnail, wantsThumbnail } from './derivatives';
import { SIGNATURE_SAMPLE_BYTES, checkUploadedContent, type ContentVerdict } from './upload-policy';
import {
	ScannerUnavailableError,
	openScanSession,
	scannerIsConfigured,
	type ScanResult,
	type ScanSession
} from './scanner';

type ClaimedFile = {
	id: string;
	organization_id: string;
	display_name: string;
	size_bytes: number;
	object_key: string;
	claim_token: string;
};

type RpcResult<T> = Promise<{ data: T | null; error: { message: string } | null }>;

export type FileWorkerClient = {
	rpc(name: string, args?: Record<string, unknown>): RpcResult<unknown>;
};

export type FileProcessingDependencies = {
	client?: FileWorkerClient;
	readObject?: (objectKey: string) => Promise<ReadableStream<Uint8Array>>;
	measureObject?: (objectKey: string) => Promise<number>;
	removeObject?: (objectKey: string) => Promise<void>;
	writeObject?: (objectKey: string, body: Uint8Array, mimeType: string) => Promise<void>;
	makeThumbnail?: (source: Uint8Array) => Promise<Uint8Array | null>;
	startScan?: () => Promise<ScanSession>;
	hasScanner?: () => boolean;
};

export type FileProcessingResult = {
	claimed: number;
	available: number;
	failed: number;
	quarantined: number;
	deferred: number;
	thumbnails: number;
};

const BATCH_SIZE = 10;

function rpcError(action: string, error: { message: string } | null) {
	return new Error(`${action}: ${error?.message ?? 'The database returned no result.'}`);
}

async function defaultReadObject(objectKey: string): Promise<ReadableStream<Uint8Array>> {
	const { body } = await getObjectStream(objectKey);
	return body as ReadableStream<Uint8Array>;
}

async function defaultMeasureObject(objectKey: string): Promise<number> {
	const { contentLength } = await headObject(objectKey);
	if (typeof contentLength !== 'number')
		throw new Error('Storage did not report a size for that object.');
	return contentLength;
}

type PassOutcome = {
	verdict: ContentVerdict;
	scan: ScanResult | null;
	checksum: string;
	// The original bytes, kept only for an image small enough to be worth a preview. Everything else --
	// a 100 MB PDF, a video -- streams past without being held.
	previewSource: Uint8Array | null;
};

// Reads the object once. The scan session is opened before the first chunk so a scanner that is already
// unreachable costs nothing, and it is aborted the moment the content check fails -- there is no point
// scanning bytes we have already decided to refuse.
async function inspect(
	file: ClaimedFile,
	actualSize: number,
	stream: ReadableStream<Uint8Array>,
	startScan: () => Promise<ScanSession>
): Promise<PassOutcome> {
	const hash = createHash('sha256');
	const sample: number[] = [];
	const session = await startScan();
	const reader = stream.getReader();

	// Decided before the first byte arrives, from the size storage reports, so the collected chunks can
	// never grow past the cap even if the object is not what it claimed to be.
	const collecting = wantsThumbnail(file.display_name, actualSize);
	const collected: Uint8Array[] = [];

	try {
		for (;;) {
			const { done, value } = await reader.read();
			if (done) break;
			if (!value || value.byteLength === 0) continue;

			if (sample.length < SIGNATURE_SAMPLE_BYTES)
				sample.push(...value.subarray(0, SIGNATURE_SAMPLE_BYTES - sample.length));

			if (collecting) collected.push(value);

			hash.update(value);
			await session.write(value);
		}
	} catch (error) {
		session.abort();
		throw error;
	} finally {
		reader.releaseLock();
	}

	const verdict = checkUploadedContent(
		file.display_name,
		Uint8Array.from(sample),
		actualSize,
		file.size_bytes
	);
	if (!verdict.ok) {
		session.abort();
		return { verdict, scan: null, checksum: hash.digest('hex'), previewSource: null };
	}

	const scan = await session.finish();
	return {
		verdict,
		scan,
		checksum: hash.digest('hex'),
		// A preview is made only from bytes that passed both checks, so libvips never decodes content the
		// scanner has not cleared.
		previewSource: collecting && scan.clean ? concatenate(collected) : null
	};
}

function concatenate(chunks: Uint8Array[]): Uint8Array {
	const total = chunks.reduce((sum, chunk) => sum + chunk.byteLength, 0);
	const whole = new Uint8Array(total);
	let offset = 0;
	for (const chunk of chunks) {
		whole.set(chunk, offset);
		offset += chunk.byteLength;
	}
	return whole;
}

// Makes and stores the preview, and answers with the key the File should record -- or null, which means
// "this File has no preview" and is a perfectly normal answer for a PDF, a spreadsheet, or an image the
// decoder could not read. The key is derived from the original's, so a retry after a crash overwrites the
// same object instead of leaving a new one behind.
async function storePreview(
	file: ClaimedFile,
	previewSource: Uint8Array | null,
	writeObject: (objectKey: string, body: Uint8Array, mimeType: string) => Promise<void>,
	makeThumbnail: (source: Uint8Array) => Promise<Uint8Array | null>
): Promise<string | null> {
	if (!previewSource) return null;

	const thumbnail = await makeThumbnail(previewSource);
	if (!thumbnail) return null;

	const thumbnailObjectKey = buildThumbnailObjectKey(file.object_key);
	try {
		await writeObject(thumbnailObjectKey, thumbnail, THUMBNAIL_MIME_TYPE);
	} catch (error) {
		console.error('Could not store the preview for an uploaded file.', {
			fileId: file.id,
			error: error instanceof Error ? error.message : error
		});
		return null;
	}

	return thumbnailObjectKey;
}

export async function runFileProcessingWorker(
	dependencies: FileProcessingDependencies = {}
): Promise<FileProcessingResult> {
	const injectedClient = dependencies.client;
	const client: FileWorkerClient =
		injectedClient ?? (getOwnerSupabaseClient() as unknown as FileWorkerClient);
	const readObject = dependencies.readObject ?? defaultReadObject;
	const measureObject = dependencies.measureObject ?? defaultMeasureObject;
	const writeObject = dependencies.writeObject ?? putObject;
	const makeThumbnail = dependencies.makeThumbnail ?? createThumbnail;
	const startScan = dependencies.startScan ?? openScanSession;
	const hasScanner = dependencies.hasScanner ?? scannerIsConfigured;

	const result: FileProcessingResult = {
		claimed: 0,
		available: 0,
		failed: 0,
		quarantined: 0,
		deferred: 0,
		thumbnails: 0
	};

	// Without a scanner there is no safe outcome to reach, so nothing is claimed at all. Uploads stay
	// pending and visible to their uploader as still processing, which is what the contract asks for:
	// publication pauses rather than releasing content nothing has checked.
	if (!hasScanner()) return result;

	const claimed = await client.rpc('claim_file_processing_jobs', { batch_size: BATCH_SIZE });
	if (claimed.error) throw rpcError('Could not claim files for processing', claimed.error);
	const files = Array.isArray(claimed.data) ? (claimed.data as ClaimedFile[]) : [];
	result.claimed = files.length;

	// Deliberately one at a time. Each file already streams at network speed, and running several at once
	// would multiply scanner connections and R2 reads on a container that also serves the app.
	for (const file of files) {
		let outcome: PassOutcome;
		try {
			const actualSize = await measureObject(file.object_key);
			outcome = await inspect(file, actualSize, await readObject(file.object_key), startScan);
		} catch (error) {
			// Our fault, not the file's: hand the claim back and try again on a later tick.
			if (error instanceof ScannerUnavailableError) {
				result.deferred += 1;
				const released = await client.rpc('release_file_processing_claim', {
					target_file_id: file.id,
					target_claim_token: file.claim_token
				});
				if (released.error) throw rpcError('Could not release a file claim', released.error);
				continue;
			}

			// Storage could not produce the object. The stale-claim window retries it; the attempt counter
			// is what eventually retires an object that is genuinely unreadable.
			result.deferred += 1;
			console.error('Could not read an uploaded file for processing.', {
				fileId: file.id,
				error: error instanceof Error ? error.message : error
			});
			continue;
		}

		let args: Record<string, unknown>;
		if (!outcome.verdict.ok) {
			args = {
				target_file_id: file.id,
				target_claim_token: file.claim_token,
				target_state: 'failed',
				target_checksum_sha256: outcome.checksum,
				target_error: outcome.verdict.reason
			};
			result.failed += 1;
		} else if (outcome.scan && !outcome.scan.clean) {
			// The signature name is logged for us and never stored: the contractor is told the file is
			// unsafe, not handed a malware family to search for.
			console.warn('An uploaded file was quarantined by the malware scanner.', {
				fileId: file.id,
				organizationId: file.organization_id,
				signature: outcome.scan.signature
			});
			args = {
				target_file_id: file.id,
				target_claim_token: file.claim_token,
				target_state: 'quarantined',
				target_checksum_sha256: outcome.checksum,
				target_error: 'This file was flagged as unsafe, so it was blocked.'
			};
			result.quarantined += 1;
		} else {
			// The preview is written before the File is published, never after: a grid that can see a File
			// must already be able to draw it, and a derivative whose own write failed simply leaves the
			// File without one rather than holding up its availability.
			const thumbnailObjectKey = await storePreview(
				file,
				outcome.previewSource,
				writeObject,
				makeThumbnail
			);
			if (thumbnailObjectKey) result.thumbnails += 1;

			args = {
				target_file_id: file.id,
				target_claim_token: file.claim_token,
				target_state: 'available',
				target_checksum_sha256: outcome.checksum,
				target_thumbnail_object_key: thumbnailObjectKey
			};
			result.available += 1;
		}

		const finalized = await client.rpc('finalize_file_processing', args);
		if (finalized.error) throw rpcError('Could not finalize a file', finalized.error);
	}

	return result;
}

export type AbandonedUploadSweepResult = { removed: number; objectsDeleted: number };

// Uploads the browser started and never finished: a closed tab, a lost connection, a cancelled picker.
// The database decides what is abandoned and hands back the keys; this only deletes the objects behind
// them, so an object another record is using can never be reached from here.
export async function sweepAbandonedFileUploads(
	dependencies: FileProcessingDependencies = {}
): Promise<AbandonedUploadSweepResult> {
	const injectedClient = dependencies.client;
	const client: FileWorkerClient =
		injectedClient ?? (getOwnerSupabaseClient() as unknown as FileWorkerClient);
	const removeObject = dependencies.removeObject ?? deleteObject;

	const swept = await client.rpc('sweep_abandoned_file_uploads', {
		older_than_hours: 24,
		batch_size: 200
	});
	if (swept.error) throw rpcError('Could not sweep abandoned uploads', swept.error);
	const rows = Array.isArray(swept.data) ? (swept.data as { object_key: string }[]) : [];

	let objectsDeleted = 0;
	for (const row of rows) {
		try {
			await removeObject(row.object_key);
			objectsDeleted += 1;
		} catch (error) {
			// The row is already gone, so a storage failure here leaves an object with nothing pointing at
			// it. Logged rather than retried: the next bucket audit collects it, and failing the sweep
			// would block every other abandoned upload behind one bad key.
			console.error('Could not delete an abandoned upload object.', {
				objectKey: row.object_key,
				error: error instanceof Error ? error.message : error
			});
		}
	}

	return { removed: rows.length, objectsDeleted };
}

export type TrashPurgeSweepResult = { purged: number; objectsDeleted: number };

// Files trashed 30+ days ago. The database logs and clears each row's storage keys and hands them back so
// the objects behind them can be deleted; the files row itself is never removed (see the Part 8A migration).
export async function sweepExpiredTrash(
	dependencies: FileProcessingDependencies = {}
): Promise<TrashPurgeSweepResult> {
	const injectedClient = dependencies.client;
	const client: FileWorkerClient =
		injectedClient ?? (getOwnerSupabaseClient() as unknown as FileWorkerClient);
	const removeObject = dependencies.removeObject ?? deleteObject;

	const purged = await client.rpc('purge_expired_trashed_files', {
		older_than_days: 30,
		batch_size: 100
	});
	if (purged.error) throw rpcError('Could not purge expired trash', purged.error);
	const rows = Array.isArray(purged.data)
		? (purged.data as { object_key: string; thumbnail_object_key: string | null }[])
		: [];

	let objectsDeleted = 0;
	for (const row of rows) {
		const keys = [row.object_key, ...(row.thumbnail_object_key ? [row.thumbnail_object_key] : [])];
		for (const key of keys) {
			try {
				await removeObject(key);
				objectsDeleted += 1;
			} catch (error) {
				// The row is already logged and cleared, so a storage failure here leaves an object with
				// nothing pointing at it. Logged rather than retried, matching the abandoned-upload sweep.
				console.error('Could not delete a purged file object.', {
					objectKey: key,
					error: error instanceof Error ? error.message : error
				});
			}
		}
	}

	return { purged: rows.length, objectsDeleted };
}
