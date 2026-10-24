import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '$lib/database.types';
import { raiseOwnerAlert } from '$lib/server/jafar/owner-alerts';
import { cleanUpClientDeletion } from '$lib/server/privacy/client-deletion-cleanup';

/**
 * Data privacy Part 6c: day 30. A customer moved to Recently Deleted is deleted for good once their 30 days are
 * up (`docs/data-privacy-client-delete-restore.md` § Day 30). Each due row is leased for 30 minutes, handed to the
 * permanent delete (`run_client_purge`, trigger `scheduled`), then its stored files are cleaned up straight away.
 * A refusal (new open money, a message mid-send) is kept on the row and retried next hour; after a day of
 * failures Jafar gets one alert.
 */

const BATCH_SIZE = 5;
// The route has 60 seconds; a heavy customer takes up to ~10 s, so stop claiming with room to finish.
const TIME_BUDGET_MS = 40_000;

export type ScheduledClientDeletionResult = { purged: number; failed: number };

export async function runScheduledClientDeletions(
	client: SupabaseClient<Database>,
	options: { budgetMs?: number; now?: () => number } = {}
): Promise<ScheduledClientDeletionResult> {
	const now = options.now ?? Date.now;
	const deadline = now() + (options.budgetMs ?? TIME_BUDGET_MS);
	const result: ScheduledClientDeletionResult = { purged: 0, failed: 0 };

	while (now() < deadline) {
		const { data: due, error } = await client.rpc('claim_due_client_deletions', {
			batch_size: BATCH_SIZE
		});
		if (error) throw error;
		if (!due?.length) break;

		for (const deletion of due) {
			const { data, error: purgeError } = await client.rpc('run_client_purge', {
				p_organization_id: deletion.organization_id,
				p_client_id: deletion.client_id,
				p_trigger_kind: 'scheduled'
			});

			if (purgeError) {
				result.failed += 1;
				await recordFailure(client, deletion.id, deletion.organization_id, purgeError.message);
				continue;
			}

			result.purged += 1;
			const receiptId = (data as { receipt_id?: string } | null)?.receipt_id;
			if (receiptId) {
				await cleanUpClientDeletion(client, receiptId).catch((cleanupError) =>
					console.error('Could not clean up after a scheduled client delete.', cleanupError)
				);
			}
		}

		if (due.length < BATCH_SIZE) break;
	}

	return result;
}

async function recordFailure(
	client: SupabaseClient<Database>,
	deletionId: string,
	organizationId: string,
	message: string
) {
	const { data: alertDue, error } = await client.rpc('record_client_deletion_purge_failure', {
		target_deletion_id: deletionId,
		failure: message
	});
	if (error) {
		console.error('Could not record a failed scheduled client delete.', error);
		return;
	}
	if (!alertDue) return;

	await raiseOwnerAlert(client, {
		kind: 'client_deletion_scheduled_failed',
		severity: 'attention',
		title: 'A deleted customer has not been deleted for good after 30 days',
		body: `Delete ${deletionId}. ${message}. It is tried again every hour.`.slice(0, 500),
		target: { targetKind: 'organization', targetId: organizationId }
	}).catch((alertError) =>
		console.error('Could not raise the scheduled client delete alert.', alertError)
	);
}
