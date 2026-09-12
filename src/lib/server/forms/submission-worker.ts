// Contractor Settings Part 4D: the form-submission worker.
//
// Mirrors the geocoding worker's bounded drain loop (src/lib/server/geocoding/worker.ts) against a single
// RPC that does the whole claim/resolve/write cycle itself: process_next_form_submission. One wake drains
// the pending queue sequentially -- claim the oldest pending submission (`for update skip locked` inside the
// RPC), turn it into the real thing, and record the outcome -- until idle, the claim cap, or the time budget.
// There is no separate finalize step to call back into and nothing to inject (no external provider): every
// fact the RPC needs already lives in the database.

import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';

type RpcResult<T> = Promise<{ data: T | null; error: { message: string } | null }>;

export type FormSubmissionWorkerClient = {
	rpc(name: string, args?: Record<string, unknown>): RpcResult<unknown>;
};

export type ProcessedFormSubmissionResult =
	| { status: 'idle' }
	| { status: 'processed' | 'failed'; submission_id: string; [key: string]: unknown };

export type FormSubmissionDrainResult = {
	claimed: number;
	processed: number;
	failed: number;
	stoppedBy: 'idle' | 'max_claims' | 'time_budget';
};

type WorkerDependencies = { client?: FormSubmissionWorkerClient };

type DrainOptions = {
	maxClaims?: number;
	timeBudgetMs?: number;
	now?: () => number;
};

// Conservative defaults, to verify rather than to claim capacity -- the same numbers the geocoding worker
// uses for the same reason.
const DEFAULT_MAX_CLAIMS = 50;
const DEFAULT_TIME_BUDGET_MS = 20_000;

function rpcError(action: string, error: { message: string } | null) {
	return new Error(`${action}: ${error?.message ?? 'The database returned no result.'}`);
}

function resolveClient(client?: FormSubmissionWorkerClient): FormSubmissionWorkerClient {
	return client ?? (getOwnerSupabaseClient() as unknown as FormSubmissionWorkerClient);
}

// One claim/process cycle. A permanent failure is recorded on the row by the RPC itself and reported back
// here as 'failed', never thrown -- only a genuine infrastructure error (the RPC call itself failing) throws.
export async function processNextFormSubmission(
	dependencies: WorkerDependencies
): Promise<ProcessedFormSubmissionResult> {
	const client = resolveClient(dependencies.client);
	const result = await client.rpc('process_next_form_submission');
	if (result.error) throw rpcError('Could not process a form submission', result.error);
	return result.data as ProcessedFormSubmissionResult;
}

// One wake: drain the pending queue sequentially until it is idle, the claim cap is reached, or the time
// budget expires. Each cycle is its own claim, so a hot backlog is bounded per wake and the next wake simply
// continues -- exactly the geocoding worker's own recovery story.
export async function drainFormSubmissionQueue(
	dependencies: WorkerDependencies & DrainOptions
): Promise<FormSubmissionDrainResult> {
	const client = resolveClient(dependencies.client);
	const maxClaims = Math.max(1, Math.floor(dependencies.maxClaims ?? DEFAULT_MAX_CLAIMS));
	const timeBudgetMs = Math.max(0, dependencies.timeBudgetMs ?? DEFAULT_TIME_BUDGET_MS);
	const now = dependencies.now ?? Date.now;
	const deadline = now() + timeBudgetMs;

	const result: FormSubmissionDrainResult = {
		claimed: 0,
		processed: 0,
		failed: 0,
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

		const processed = await processNextFormSubmission({ client });
		if (processed.status === 'idle') {
			result.stoppedBy = 'idle';
			return result;
		}

		result.claimed += 1;
		if (processed.status === 'processed') result.processed += 1;
		else result.failed += 1;
	}
}
