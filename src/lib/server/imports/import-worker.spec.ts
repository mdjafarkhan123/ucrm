import { describe, expect, it, vi } from 'vitest';
import {
	drainImportQueue,
	processNextImportRow,
	type ImportWorkerClient,
	type ProcessedImportRowResult
} from './import-worker';

function clientFrom(sequence: ProcessedImportRowResult[]): ImportWorkerClient {
	let i = 0;
	return {
		rpc: vi.fn(async () => {
			const next = sequence[i] ?? ({ status: 'idle' } as ProcessedImportRowResult);
			i += 1;
			return { data: next, error: null };
		})
	};
}

describe('processNextImportRow', () => {
	it('returns the RPC payload for one claim', async () => {
		const client = clientFrom([
			{ status: 'processed', row_id: 'r1', batch_id: 'b1', action: 'create' }
		]);
		expect(await processNextImportRow({ client })).toMatchObject({
			status: 'processed',
			row_id: 'r1'
		});
		expect(client.rpc).toHaveBeenCalledWith('process_next_import_row');
	});

	it('throws only on a genuine infrastructure error', async () => {
		const client: ImportWorkerClient = {
			rpc: vi.fn(async () => ({ data: null, error: { message: 'connection reset' } }))
		};
		await expect(processNextImportRow({ client })).rejects.toThrow(/connection reset/);
	});
});

describe('drainImportQueue', () => {
	it('drains processed and failed rows until idle', async () => {
		const client = clientFrom([
			{ status: 'processed', row_id: 'r1', batch_id: 'b1', action: 'create' },
			{ status: 'failed', row_id: 'r2', batch_id: 'b1', error: 'duplicate_contact' },
			{ status: 'processed', row_id: 'r3', batch_id: 'b1', action: 'update' },
			{ status: 'idle' }
		]);

		const result = await drainImportQueue({ client, generateErrorFile: vi.fn() });

		expect(result).toMatchObject({ claimed: 3, processed: 2, failed: 1, stoppedBy: 'idle' });
	});

	it('generates the error file when a completed batch has failed/held rows', async () => {
		const client = clientFrom([
			{ status: 'processed', row_id: 'r1', batch_id: 'b1', action: 'create' },
			{
				status: 'batch_completed',
				batch_id: 'b1',
				organization_id: 'org-1',
				error_count: 2,
				held_count: 1
			},
			{ status: 'idle' }
		]);
		const generateErrorFile = vi
			.fn()
			.mockResolvedValue({ objectKey: 'org-1/client-imports/errors/b1.csv' });

		const result = await drainImportQueue({ client, generateErrorFile });

		expect(generateErrorFile).toHaveBeenCalledWith({
			client,
			organizationId: 'org-1',
			batchId: 'b1'
		});
		expect(result).toMatchObject({ batchesCompleted: 1, errorFilesGenerated: 1, claimed: 1 });
	});

	it('skips the error file for a clean completed batch', async () => {
		const client = clientFrom([
			{
				status: 'batch_completed',
				batch_id: 'b1',
				organization_id: 'org-1',
				error_count: 0,
				held_count: 0
			},
			{ status: 'idle' }
		]);
		const generateErrorFile = vi.fn();

		const result = await drainImportQueue({ client, generateErrorFile });

		expect(generateErrorFile).not.toHaveBeenCalled();
		expect(result).toMatchObject({ batchesCompleted: 1, errorFilesGenerated: 0 });
	});

	it('stops at the claim cap', async () => {
		const client = clientFrom(
			Array.from({ length: 10 }, (_, n) => ({
				status: 'processed' as const,
				row_id: `r${n}`,
				batch_id: 'b1',
				action: 'create'
			}))
		);

		const result = await drainImportQueue({ client, maxClaims: 3, generateErrorFile: vi.fn() });

		expect(result).toMatchObject({ claimed: 3, stoppedBy: 'max_claims' });
	});

	it('stops when the time budget is exhausted before any claim', async () => {
		const client = clientFrom([
			{ status: 'processed', row_id: 'r1', batch_id: 'b1', action: 'create' }
		]);
		let clock = 1_000;
		const now = () => clock;

		const result = await drainImportQueue({
			client,
			timeBudgetMs: 0,
			now: () => {
				const value = clock;
				clock += 1;
				return value;
			},
			generateErrorFile: vi.fn()
		});
		void now;

		expect(result.stoppedBy).toBe('time_budget');
		expect(result.claimed).toBe(0);
	});
});
