import { describe, expect, it, vi } from 'vitest';
import { runFileProcessingWorker, type FileWorkerClient } from './processing-worker';
import { ScannerUnavailableError, type ScanResult, type ScanSession } from './scanner';

const JPEG_BYTES = Uint8Array.from([0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10, 0x4a, 0x46]);

const claimedFile = {
	id: 'file-1',
	organization_id: 'org-1',
	display_name: 'roof.jpg',
	size_bytes: JPEG_BYTES.byteLength,
	object_key: 'org-1/files/abc-roof.jpg',
	claim_token: 'claim-1'
};

function streamOf(bytes: Uint8Array): ReadableStream<Uint8Array> {
	return new ReadableStream<Uint8Array>({
		start(controller) {
			controller.enqueue(bytes);
			controller.close();
		}
	});
}

function scanSession(result: ScanResult | Error): ScanSession {
	return {
		write: vi.fn(async () => {}),
		finish: vi.fn(async () => {
			if (result instanceof Error) throw result;
			return result;
		}),
		abort: vi.fn()
	};
}

// One claimed file, then an empty claim so the worker's drain loop stops.
function clientWith(calls: Record<string, unknown>[], files = [claimedFile]): FileWorkerClient {
	let claims = 0;
	return {
		rpc: vi.fn(async (name: string, args?: Record<string, unknown>) => {
			calls.push({ name, ...args });
			if (name === 'claim_file_processing_jobs') {
				claims += 1;
				return { data: claims === 1 ? files : [], error: null };
			}
			return { data: null, error: null };
		})
	};
}

const THUMBNAIL_BYTES = Uint8Array.from([0xff, 0xd8, 0xff, 0xdb]);

function dependencies(overrides: Record<string, unknown> = {}) {
	return {
		readObject: async () => streamOf(JPEG_BYTES),
		measureObject: async () => JPEG_BYTES.byteLength,
		writeObject: vi.fn(async () => {}),
		makeThumbnail: vi.fn(async () => THUMBNAIL_BYTES),
		startScan: async () => scanSession({ clean: true }),
		hasScanner: () => true,
		...overrides
	};
}

describe('runFileProcessingWorker', () => {
	it('makes a clean, matching upload available with its checksum', async () => {
		const calls: Record<string, unknown>[] = [];
		const result = await runFileProcessingWorker({
			client: clientWith(calls),
			...dependencies()
		});

		expect(result).toMatchObject({ claimed: 1, available: 1, failed: 0, quarantined: 0 });
		const finalize = calls.find((call) => call.name === 'finalize_file_processing');
		expect(finalize).toMatchObject({ target_state: 'available', target_claim_token: 'claim-1' });
		expect(finalize?.target_checksum_sha256).toMatch(/^[0-9a-f]{64}$/);
	});

	it('stores a preview beside the original and records its key', async () => {
		const calls: Record<string, unknown>[] = [];
		const deps = dependencies();
		const result = await runFileProcessingWorker({ client: clientWith(calls), ...deps });

		expect(result.thumbnails).toBe(1);
		expect(deps.writeObject).toHaveBeenCalledWith(
			'org-1/files/abc-roof.jpg.thumb.jpg',
			THUMBNAIL_BYTES,
			'image/jpeg'
		);
		expect(calls.find((call) => call.name === 'finalize_file_processing')).toMatchObject({
			target_state: 'available',
			target_thumbnail_object_key: 'org-1/files/abc-roof.jpg.thumb.jpg'
		});
	});

	it('publishes a file with no preview rather than holding it back', async () => {
		const calls: Record<string, unknown>[] = [];
		const deps = dependencies({ makeThumbnail: vi.fn(async () => null) });
		const result = await runFileProcessingWorker({ client: clientWith(calls), ...deps });

		expect(result).toMatchObject({ available: 1, thumbnails: 0 });
		expect(deps.writeObject).not.toHaveBeenCalled();
		expect(calls.find((call) => call.name === 'finalize_file_processing')).toMatchObject({
			target_state: 'available',
			target_thumbnail_object_key: null
		});
	});

	it('publishes the file even when storing its preview fails', async () => {
		const calls: Record<string, unknown>[] = [];
		const result = await runFileProcessingWorker({
			client: clientWith(calls),
			...dependencies({
				writeObject: vi.fn(async () => {
					throw new Error('R2 is not answering.');
				})
			})
		});

		expect(result).toMatchObject({ available: 1, thumbnails: 0 });
		expect(calls.find((call) => call.name === 'finalize_file_processing')).toMatchObject({
			target_state: 'available',
			target_thumbnail_object_key: null
		});
	});

	it('does not try to preview a document', async () => {
		const calls: Record<string, unknown>[] = [];
		const pdf = Uint8Array.from([0x25, 0x50, 0x44, 0x46, 0x2d, 0x31, 0x2e, 0x37]);
		const deps = dependencies({
			readObject: async () => streamOf(pdf),
			measureObject: async () => pdf.byteLength
		});
		const result = await runFileProcessingWorker({
			client: clientWith(calls, [
				{
					...claimedFile,
					display_name: 'quote.pdf',
					size_bytes: pdf.byteLength,
					object_key: 'org-1/files/abc-quote.pdf'
				}
			]),
			...deps
		});

		expect(result).toMatchObject({ available: 1, thumbnails: 0 });
		expect(deps.makeThumbnail).not.toHaveBeenCalled();
	});

	it('makes no preview from bytes the scanner flagged', async () => {
		const deps = dependencies({
			startScan: async () => scanSession({ clean: false, signature: 'Eicar-Test' })
		});
		const result = await runFileProcessingWorker({ client: clientWith([]), ...deps });

		expect(result).toMatchObject({ quarantined: 1, thumbnails: 0 });
		expect(deps.makeThumbnail).not.toHaveBeenCalled();
	});

	it('quarantines a file the scanner flags, without storing the signature name', async () => {
		const calls: Record<string, unknown>[] = [];
		const result = await runFileProcessingWorker({
			client: clientWith(calls),
			...dependencies({
				startScan: async () => scanSession({ clean: false, signature: 'Eicar-Test' })
			})
		});

		expect(result).toMatchObject({ quarantined: 1, available: 0 });
		const finalize = calls.find((call) => call.name === 'finalize_file_processing');
		expect(finalize).toMatchObject({ target_state: 'quarantined' });
		expect(String(finalize?.target_error)).not.toContain('Eicar');
	});

	it('fails a file whose bytes are not what its name claims', async () => {
		const calls: Record<string, unknown>[] = [];
		const disguised = Uint8Array.from([0x4d, 0x5a, 0x90, 0x00, 0x03, 0x00, 0x00, 0x00]);
		const result = await runFileProcessingWorker({
			client: clientWith(calls),
			...dependencies({
				readObject: async () => streamOf(disguised),
				measureObject: async () => disguised.byteLength
			})
		});

		expect(result).toMatchObject({ failed: 1, available: 0 });
		expect(calls.find((call) => call.name === 'finalize_file_processing')).toMatchObject({
			target_state: 'failed'
		});
	});

	it('hands the claim back when the scanner is unreachable, and publishes nothing', async () => {
		const calls: Record<string, unknown>[] = [];
		const result = await runFileProcessingWorker({
			client: clientWith(calls),
			...dependencies({
				startScan: async () => {
					throw new ScannerUnavailableError('connection refused');
				}
			})
		});

		expect(result).toMatchObject({ deferred: 1, available: 0, failed: 0, quarantined: 0 });
		expect(calls.some((call) => call.name === 'finalize_file_processing')).toBe(false);
		expect(calls.find((call) => call.name === 'release_file_processing_claim')).toMatchObject({
			target_file_id: 'file-1'
		});
	});

	it('claims nothing at all when no scanner is configured', async () => {
		const calls: Record<string, unknown>[] = [];
		const result = await runFileProcessingWorker({
			client: clientWith(calls),
			...dependencies({ hasScanner: () => false })
		});

		expect(result.claimed).toBe(0);
		expect(calls).toHaveLength(0);
	});
});
