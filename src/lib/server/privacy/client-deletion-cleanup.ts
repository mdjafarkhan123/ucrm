import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '$lib/database.types';
import { raiseOwnerAlert } from '$lib/server/jafar/owner-alerts';
import { deleteObjects } from '$lib/server/storage/r2';

/**
 * Data privacy Part 3b: the stored file copies a permanent customer delete leaves behind. The database delete
 * (`run_client_purge`) parks every file, signature and message attachment key on its receipt; this removes them
 * from R2 after the delete commits and completes the receipt. Twilio's message log is left alone, as HighLevel
 * does. Modelled on the organization purge's provider cleanup (`organization-closure-cron.ts`).
 */

// The sweep leaves a fresh receipt to the delete that made it, which runs its own cleanup straight after
// committing, so the two never write the same receipt at once.
const SWEEP_GRACE_MS = 15 * 60 * 1000;
const SWEEP_BATCH_SIZE = 50;

type CleanupReceipt = {
	id: string;
	organization_id: string;
	component_results: unknown;
	pending_storage_object_keys: string[] | null;
	retry_count: number;
};

export type ClientDeletionCleanupResult = { completed: number; failed: number };

const RECEIPT_COLUMNS =
	'id, organization_id, component_results, pending_storage_object_keys, retry_count';

/**
 * Deletes the receipt's pending storage objects and records the outcome. Only the keys that failed stay
 * pending, so a retry never repeats finished work; an object already gone counts as deleted. The receipt is
 * completed when nothing is left, and a failure leaves it failed_partial with an alert for Jafar.
 */
async function finishStorageCleanup(
	client: SupabaseClient<Database>,
	receipt: CleanupReceipt,
	isRetry: boolean
): Promise<boolean> {
	const pendingKeys = receipt.pending_storage_object_keys ?? [];
	const failures = pendingKeys.length > 0 ? await deleteObjects(pendingKeys) : [];
	const succeeded = failures.length === 0;

	const components = {
		...((receipt.component_results as Record<string, string> | null) ?? {}),
		storage_objects: succeeded ? 'succeeded' : 'failed'
	};
	const lastError = succeeded
		? null
		: `${failures.length} of ${pendingKeys.length} stored files could not be deleted: ${failures[0].reason}`.slice(
				0,
				2000
			);

	const { error: updateError } = await client
		.from('client_deletion_receipts')
		.update({
			component_results: components,
			pending_storage_object_keys: succeeded ? null : failures.map((failure) => failure.key),
			status: succeeded ? 'completed' : 'failed_partial',
			completed_at: succeeded ? new Date().toISOString() : null,
			last_error: lastError,
			retry_count: isRetry ? receipt.retry_count + 1 : receipt.retry_count
		})
		.eq('id', receipt.id);
	if (updateError) console.error('Could not update the client deletion receipt.', updateError);

	if (!succeeded) {
		await raiseOwnerAlert(client, {
			kind: 'client_deletion_cleanup_failed',
			severity: 'attention',
			title: 'A deleted customer still has stored files that could not be removed',
			body: `Receipt ${receipt.id}. ${lastError}. The daily sweep will try again.`.slice(0, 500),
			target: { targetKind: 'organization', targetId: receipt.organization_id }
		}).catch((alertError) =>
			console.error('Could not raise the client-deletion cleanup alert.', alertError)
		);
	}

	return succeeded && !updateError;
}

/**
 * Cleans up after one permanent delete, by its receipt id. The delete-now route and the scheduled delete call
 * this right after `run_client_purge` returns; it is also safe to call again on a receipt that is already
 * finished, which then does nothing.
 */
export async function cleanUpClientDeletion(
	client: SupabaseClient<Database>,
	receiptId: string,
	options: { isRetry?: boolean } = {}
): Promise<{ found: boolean; ok: boolean }> {
	const { data: receipt, error } = await client
		.from('client_deletion_receipts')
		.select(RECEIPT_COLUMNS)
		.eq('id', receiptId)
		.maybeSingle();
	if (error) throw error;
	if (!receipt) return { found: false, ok: true };
	if (!receipt.pending_storage_object_keys?.length) return { found: true, ok: true };

	const ok = await finishStorageCleanup(client, receipt, options.isRetry ?? false);
	return { found: true, ok };
}

/**
 * The daily retry: every unfinished receipt older than the grace period, oldest first, a batch per run.
 * Reads through the receipts' partial index on unfinished rows.
 */
export async function runClientDeletionCleanupSweep(
	client: SupabaseClient<Database>,
	now: Date = new Date()
): Promise<ClientDeletionCleanupResult> {
	const result: ClientDeletionCleanupResult = { completed: 0, failed: 0 };

	const { data: receipts, error } = await client
		.from('client_deletion_receipts')
		.select(RECEIPT_COLUMNS)
		.neq('status', 'completed')
		.lt('created_at', new Date(now.getTime() - SWEEP_GRACE_MS).toISOString())
		.order('created_at', { ascending: true })
		.limit(SWEEP_BATCH_SIZE);
	if (error) throw error;

	for (const receipt of receipts ?? []) {
		if (!receipt.pending_storage_object_keys?.length) continue;
		const ok = await finishStorageCleanup(client, receipt, true);
		if (ok) result.completed += 1;
		else result.failed += 1;
	}

	return result;
}
