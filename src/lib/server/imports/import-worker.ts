// Onboarding & Data Portability, Part 1, step 5b: the client-import drain loop.
//
// Mirrors the form-submission worker (src/lib/server/forms/submission-worker.ts) against a single RPC that does
// the whole claim/resolve/write cycle itself: process_next_import_row. One wake drains the ready queue
// sequentially -- claim the oldest ready row, turn it into (or onto) a real client, record the outcome -- until
// the queue is idle, the claim cap, or the time budget. When the RPC reports a batch just finished
// ('batch_completed'), the loop builds and stores that batch's per-row error file.
//
// Bulk-import sizing (deliberately unlike the forms worker's trickle defaults): a high claim cap so the time
// budget -- kept safely under pg_net's HTTP timeout -- is the real bound, letting a few-thousand-row import
// usually drain in one or two wakes. Each row is a handful of small single-row writes.

import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { generateImportErrorFile } from './error-file';

type RpcResult<T> = Promise<{ data: T | null; error: { message: string } | null }>;

export type ImportWorkerClient = {
	rpc(name: string, args?: Record<string, unknown>): RpcResult<unknown>;
};

export type ProcessedImportRowResult =
	| { status: 'idle' }
	| { status: 'processed' | 'failed'; row_id: string; batch_id: string; [key: string]: unknown }
	| {
			status: 'batch_completed';
			batch_id: string;
			organization_id: string;
			error_count: number;
			held_count: number;
	  };

export type ImportDrainResult = {
	claimed: number;
	processed: number;
	failed: number;
	batchesCompleted: number;
	errorFilesGenerated: number;
	stoppedBy: 'idle' | 'max_claims' | 'time_budget';
};

type ErrorFileGenerator = (args: {
	client: ImportWorkerClient;
	organizationId: string;
	batchId: string;
}) => Promise<{ objectKey: string | null }>;

type WorkerDependencies = { client?: ImportWorkerClient; generateErrorFile?: ErrorFileGenerator };

type DrainOptions = {
	maxClaims?: number;
	timeBudgetMs?: number;
	now?: () => number;
};

// The time budget is the real bound (kept under the pg_net 50s HTTP timeout the wake uses); the claim cap is a
// high backstop so it, not row count, is what usually stops a wake.
const DEFAULT_MAX_CLAIMS = 5_000;
const DEFAULT_TIME_BUDGET_MS = 20_000;

function rpcError(action: string, error: { message: string } | null) {
	return new Error(`${action}: ${error?.message ?? 'The database returned no result.'}`);
}

function resolveClient(client?: ImportWorkerClient): ImportWorkerClient {
	return client ?? (getOwnerSupabaseClient() as unknown as ImportWorkerClient);
}

// One claim/process cycle. A permanent row failure is recorded on the row by the RPC and reported back here as
// 'failed', never thrown -- only a genuine infrastructure error (the RPC call itself failing) throws.
export async function processNextImportRow(
	dependencies: WorkerDependencies
): Promise<ProcessedImportRowResult> {
	const client = resolveClient(dependencies.client);
	const result = await client.rpc('process_next_import_row');
	if (result.error) throw rpcError('Could not process an import row', result.error);
	return result.data as ProcessedImportRowResult;
}

const defaultGenerateErrorFile: ErrorFileGenerator = ({ client, organizationId, batchId }) =>
	generateImportErrorFile({
		client: client as never,
		organizationId,
		batchId
	});

// One wake: drain the ready queue sequentially until idle, the claim cap, or the time budget. Each cycle is its
// own claim, so a hot backlog is bounded per wake and the next wake simply continues. Finalizing a drained
// batch is itself one of these cycles (the RPC returns 'batch_completed' when it finds no row to claim), and we
// generate that batch's error file on the spot.
export async function drainImportQueue(
	dependencies: WorkerDependencies & DrainOptions
): Promise<ImportDrainResult> {
	const client = resolveClient(dependencies.client);
	const generateErrorFile = dependencies.generateErrorFile ?? defaultGenerateErrorFile;
	const maxClaims = Math.max(1, Math.floor(dependencies.maxClaims ?? DEFAULT_MAX_CLAIMS));
	const timeBudgetMs = Math.max(0, dependencies.timeBudgetMs ?? DEFAULT_TIME_BUDGET_MS);
	const now = dependencies.now ?? Date.now;
	const deadline = now() + timeBudgetMs;

	const result: ImportDrainResult = {
		claimed: 0,
		processed: 0,
		failed: 0,
		batchesCompleted: 0,
		errorFilesGenerated: 0,
		stoppedBy: 'idle'
	};

	while (true) {
		if (result.claimed >= maxClaims) {
			result.stoppedBy = 'max_claims';
			return result;
		}
		if (now() >= deadline) {
			result.stoppedBy = 'time_budget';
			return result;
		}

		const outcome = await processNextImportRow({ client });

		if (outcome.status === 'idle') {
			result.stoppedBy = 'idle';
			return result;
		}

		if (outcome.status === 'batch_completed') {
			result.batchesCompleted += 1;
			// Only a batch with something the office must act on gets a file (error_count/held_count seed it).
			if (outcome.error_count > 0 || outcome.held_count > 0) {
				const { objectKey } = await generateErrorFile({
					client,
					organizationId: outcome.organization_id,
					batchId: outcome.batch_id
				});
				if (objectKey) result.errorFilesGenerated += 1;
			}
			// A finalized batch is not a claimed row; keep looping to drain any other batch's rows.
			continue;
		}

		result.claimed += 1;
		if (outcome.status === 'processed') result.processed += 1;
		else result.failed += 1;
	}
}
