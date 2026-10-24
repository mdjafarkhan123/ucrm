import { beforeEach, describe, expect, it, vi } from 'vitest';
import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '$lib/database.types';
import { runScheduledClientDeletions } from './client-deletion-scheduled';
import { cleanUpClientDeletion } from '$lib/server/privacy/client-deletion-cleanup';
import { raiseOwnerAlert } from '$lib/server/jafar/owner-alerts';

vi.mock('$lib/server/privacy/client-deletion-cleanup', () => ({ cleanUpClientDeletion: vi.fn() }));
vi.mock('$lib/server/jafar/owner-alerts', () => ({ raiseOwnerAlert: vi.fn() }));

const mockedCleanUp = vi.mocked(cleanUpClientDeletion);
const mockedRaiseAlert = vi.mocked(raiseOwnerAlert);

type Due = { id: string; organization_id: string; client_id: string };

function due(n: number): Due {
	return { id: `deletion-${n}`, organization_id: 'org-1', client_id: `client-${n}` };
}

function clientWith(config: {
	batches: Due[][];
	refuse?: Set<string>;
	alertDue?: boolean;
}) {
	const calls: Array<{ fn: string; args: Record<string, unknown> }> = [];
	let batch = 0;
	const client = {
		rpc: vi.fn(async (fn: string, args: Record<string, unknown>) => {
			calls.push({ fn, args });
			if (fn === 'claim_due_client_deletions') return { data: config.batches[batch++] ?? [], error: null };
			if (fn === 'run_client_purge') {
				if (config.refuse?.has(args.p_client_id as string)) {
					return { data: null, error: { message: 'This client cannot be deleted yet: open invoice.' } };
				}
				return { data: { applied: true, receipt_id: `receipt-${args.p_client_id}` }, error: null };
			}
			if (fn === 'record_client_deletion_purge_failure') {
				return { data: config.alertDue ?? false, error: null };
			}
			throw new Error(`unexpected rpc ${fn}`);
		})
	} as unknown as SupabaseClient<Database>;
	return { client, calls };
}

beforeEach(() => {
	vi.clearAllMocks();
	mockedCleanUp.mockResolvedValue({ found: true, ok: true });
	mockedRaiseAlert.mockResolvedValue('notification-1');
});

describe('runScheduledClientDeletions', () => {
	it('deletes every due customer for good and cleans up their stored files', async () => {
		const { client, calls } = clientWith({ batches: [[due(1), due(2)]] });

		const result = await runScheduledClientDeletions(client);

		expect(result).toEqual({ purged: 2, failed: 0 });
		expect(calls.filter((call) => call.fn === 'run_client_purge').map((call) => call.args)).toEqual([
			{ p_organization_id: 'org-1', p_client_id: 'client-1', p_trigger_kind: 'scheduled' },
			{ p_organization_id: 'org-1', p_client_id: 'client-2', p_trigger_kind: 'scheduled' }
		]);
		expect(mockedCleanUp).toHaveBeenCalledWith(client, 'receipt-client-1');
		expect(mockedCleanUp).toHaveBeenCalledWith(client, 'receipt-client-2');
	});

	it('keeps claiming full batches until nothing is due', async () => {
		const full = [1, 2, 3, 4, 5].map(due);
		const { client, calls } = clientWith({ batches: [full, [due(6)]] });

		const result = await runScheduledClientDeletions(client);

		expect(result.purged).toBe(6);
		expect(calls.filter((call) => call.fn === 'claim_due_client_deletions')).toHaveLength(2);
	});

	it('records a refusal for the next hour and alerts only when a day of failures says so', async () => {
		const { client, calls } = clientWith({
			batches: [[due(1), due(2)]],
			refuse: new Set(['client-1']),
			alertDue: true
		});

		const result = await runScheduledClientDeletions(client);

		expect(result).toEqual({ purged: 1, failed: 1 });
		expect(calls).toContainEqual({
			fn: 'record_client_deletion_purge_failure',
			args: { target_deletion_id: 'deletion-1', failure: 'This client cannot be deleted yet: open invoice.' }
		});
		expect(mockedRaiseAlert).toHaveBeenCalledTimes(1);
		expect(mockedRaiseAlert.mock.calls[0][1]).toMatchObject({
			kind: 'client_deletion_scheduled_failed',
			target: { targetKind: 'organization', targetId: 'org-1' }
		});
	});

	it('does not alert while failures are younger than a day', async () => {
		const { client } = clientWith({ batches: [[due(1)]], refuse: new Set(['client-1']), alertDue: false });

		await runScheduledClientDeletions(client);

		expect(mockedRaiseAlert).not.toHaveBeenCalled();
	});

	it('stops claiming once its time budget is spent', async () => {
		const full = [1, 2, 3, 4, 5].map(due);
		const { client, calls } = clientWith({ batches: [full, full, full] });
		let clock = 0;

		await runScheduledClientDeletions(client, { budgetMs: 10, now: () => (clock += 6) });

		expect(calls.filter((call) => call.fn === 'claim_due_client_deletions')).toHaveLength(1);
	});
});
