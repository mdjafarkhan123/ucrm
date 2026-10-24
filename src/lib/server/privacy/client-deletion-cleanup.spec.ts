import { beforeEach, describe, expect, it, vi } from 'vitest';
import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '$lib/database.types';
import { cleanUpClientDeletion, runClientDeletionCleanupSweep } from './client-deletion-cleanup';
import { deleteObjects } from '$lib/server/storage/r2';
import { raiseOwnerAlert } from '$lib/server/jafar/owner-alerts';

vi.mock('$lib/server/storage/r2', () => ({ deleteObjects: vi.fn() }));
vi.mock('$lib/server/jafar/owner-alerts', () => ({ raiseOwnerAlert: vi.fn() }));

const mockedDeleteObjects = vi.mocked(deleteObjects);
const mockedRaiseAlert = vi.mocked(raiseOwnerAlert);

type Receipt = {
	id: string;
	organization_id: string;
	component_results: Record<string, string>;
	pending_storage_object_keys: string[] | null;
	retry_count: number;
};

function receipt(overrides: Partial<Receipt> = {}): Receipt {
	return {
		id: 'receipt-1',
		organization_id: 'org-1',
		component_results: { database: 'succeeded', storage_objects: 'pending' },
		pending_storage_object_keys: ['org-1/files/a.jpg', 'org-1/files/a.jpg.thumb.jpg'],
		retry_count: 0,
		...overrides
	};
}

function clientWith(config: { byId?: Receipt | null; unfinished?: Receipt[] }) {
	const updates: Array<{ id: string; payload: Record<string, unknown> }> = [];
	const sweepFilters: Record<string, unknown> = {};

	const client = {
		from: vi.fn((table: string) => {
			if (table !== 'client_deletion_receipts') throw new Error(`unexpected table ${table}`);
			return {
				select: () => {
					const chain = {
						eq: () => ({ maybeSingle: async () => ({ data: config.byId ?? null, error: null }) }),
						neq: (column: string, value: unknown) => {
							sweepFilters.neq = [column, value];
							return chain;
						},
						lt: (column: string, value: unknown) => {
							sweepFilters.lt = [column, value];
							return chain;
						},
						order: () => chain,
						limit: async (count: number) => {
							sweepFilters.limit = count;
							return { data: config.unfinished ?? [], error: null };
						}
					};
					return chain;
				},
				update: (payload: Record<string, unknown>) => ({
					eq: async (_column: string, id: string) => {
						updates.push({ id, payload });
						return { error: null };
					}
				})
			};
		})
	} as unknown as SupabaseClient<Database>;

	return { client, updates, sweepFilters };
}

beforeEach(() => {
	vi.clearAllMocks();
	mockedDeleteObjects.mockResolvedValue([]);
	mockedRaiseAlert.mockResolvedValue('notification-1');
});

describe('cleanUpClientDeletion', () => {
	it('deletes every pending stored file and completes the receipt', async () => {
		const { client, updates } = clientWith({ byId: receipt() });

		const result = await cleanUpClientDeletion(client, 'receipt-1');

		expect(result).toEqual({ found: true, ok: true });
		expect(mockedDeleteObjects).toHaveBeenCalledWith([
			'org-1/files/a.jpg',
			'org-1/files/a.jpg.thumb.jpg'
		]);
		expect(updates).toHaveLength(1);
		expect(updates[0].id).toBe('receipt-1');
		expect(updates[0].payload).toMatchObject({
			component_results: { database: 'succeeded', storage_objects: 'succeeded' },
			pending_storage_object_keys: null,
			status: 'completed',
			last_error: null,
			retry_count: 0
		});
		expect(updates[0].payload.completed_at).toEqual(expect.any(String));
		expect(mockedRaiseAlert).not.toHaveBeenCalled();
	});

	it('keeps only the files that failed, marks the receipt failed_partial and alerts Jafar', async () => {
		mockedDeleteObjects.mockResolvedValue([{ key: 'org-1/files/a.jpg', reason: 'InternalError' }]);
		const { client, updates } = clientWith({ byId: receipt() });

		const result = await cleanUpClientDeletion(client, 'receipt-1');

		expect(result).toEqual({ found: true, ok: false });
		expect(updates[0].payload).toMatchObject({
			component_results: { database: 'succeeded', storage_objects: 'failed' },
			pending_storage_object_keys: ['org-1/files/a.jpg'],
			status: 'failed_partial',
			completed_at: null,
			last_error: '1 of 2 stored files could not be deleted: InternalError'
		});
		expect(mockedRaiseAlert).toHaveBeenCalledWith(
			client,
			expect.objectContaining({
				kind: 'client_deletion_cleanup_failed',
				target: { targetKind: 'organization', targetId: 'org-1' }
			})
		);
	});

	it('does nothing for a receipt that is already finished', async () => {
		const { client, updates } = clientWith({
			byId: receipt({ pending_storage_object_keys: null })
		});

		expect(await cleanUpClientDeletion(client, 'receipt-1')).toEqual({ found: true, ok: true });
		expect(mockedDeleteObjects).not.toHaveBeenCalled();
		expect(updates).toHaveLength(0);
	});

	it('reports a missing receipt without touching storage', async () => {
		const { client } = clientWith({ byId: null });

		expect(await cleanUpClientDeletion(client, 'nope')).toEqual({ found: false, ok: true });
		expect(mockedDeleteObjects).not.toHaveBeenCalled();
	});

	it('still completes the receipt when the alert itself cannot be raised', async () => {
		mockedDeleteObjects.mockResolvedValue([{ key: 'org-1/files/a.jpg', reason: 'InternalError' }]);
		mockedRaiseAlert.mockRejectedValue(new Error('alerts are down'));
		const { client, updates } = clientWith({ byId: receipt() });

		await expect(cleanUpClientDeletion(client, 'receipt-1')).resolves.toEqual({
			found: true,
			ok: false
		});
		expect(updates).toHaveLength(1);
	});
});

describe('runClientDeletionCleanupSweep', () => {
	it('retries unfinished receipts past the grace period and counts the outcomes', async () => {
		const now = new Date('2026-10-24T06:40:00.000Z');
		const failing = receipt({
			id: 'receipt-2',
			pending_storage_object_keys: ['org-1/files/b.pdf'],
			retry_count: 2
		});
		mockedDeleteObjects.mockImplementation(async (keys) =>
			keys.includes('org-1/files/b.pdf') ? [{ key: 'org-1/files/b.pdf', reason: 'SlowDown' }] : []
		);
		const { client, updates, sweepFilters } = clientWith({ unfinished: [receipt(), failing] });

		const result = await runClientDeletionCleanupSweep(client, now);

		expect(result).toEqual({ completed: 1, failed: 1 });
		expect(sweepFilters).toEqual({
			neq: ['status', 'completed'],
			lt: ['created_at', '2026-10-24T06:25:00.000Z'],
			limit: 50
		});
		expect(updates.map((update) => [update.id, update.payload.retry_count])).toEqual([
			['receipt-1', 1],
			['receipt-2', 3]
		]);
	});

	it('skips an unfinished receipt with nothing left to delete', async () => {
		const { client, updates } = clientWith({
			unfinished: [receipt({ pending_storage_object_keys: [] })]
		});

		expect(await runClientDeletionCleanupSweep(client)).toEqual({ completed: 0, failed: 0 });
		expect(updates).toHaveLength(0);
	});
});
