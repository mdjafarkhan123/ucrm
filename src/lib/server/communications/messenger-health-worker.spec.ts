import { afterEach, describe, expect, it, vi } from 'vitest';
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: () => ({}) }));
vi.mock('./messenger-connections', () => ({ loadMessengerPageToken: vi.fn() }));
import {
	checkDueMessengerConnections,
	type MessengerHealthClient
} from './messenger-health-worker';

afterEach(() => vi.restoreAllMocks());
const now = new Date('2026-10-23T12:00:00Z');
function client(count = 6) {
	const rows = Array.from({ length: count }, (_, i) => ({
		id: `c${i}`,
		organization_id: `org${i}`,
		page_id: `page${i}`,
		updated_at: '2026-10-23T10:00:00Z'
	}));
	return {
		due: vi.fn(async () => rows),
		claim: vi.fn(async () => true),
		pageToken: vi.fn(async () => 'secret'),
		finish: vi.fn(async () => {})
	} satisfies MessengerHealthClient;
}
describe('Messenger health worker', () => {
	it('bounds Page and provider fanout and isolates a failing Page', async () => {
		const db = client();
		let running = 0;
		let peak = 0;
		const check = vi.fn(async (page: string) => {
			running++;
			peak = Math.max(peak, running);
			await new Promise((resolve) => setTimeout(resolve, 2));
			running--;
			if (page === 'page0') throw new Error('temporary outage');
			return page === 'page1' ? ('permission_missing' as const) : ('healthy' as const);
		});
		vi.spyOn(console, 'warn').mockImplementation(() => {});
		const result = await checkDueMessengerConnections({ client: db, check, now });
		expect(result).toEqual({ checked: 5, reconnect: 1, deferred: 1, skipped: 0 });
		expect(peak).toBe(3);
		expect(db.due).toHaveBeenCalledWith('2026-10-23T11:00:00.000Z', 6);
		expect(db.finish).not.toHaveBeenCalledWith(
			expect.objectContaining({ id: 'c0' }),
			expect.anything(),
			expect.anything()
		);
	});
	it('does not inspect a Page when another wake or a reconnect won the claim', async () => {
		const db = client(1);
		db.claim.mockResolvedValue(false);
		const check = vi.fn();
		expect(await checkDueMessengerConnections({ client: db, check, now })).toEqual({
			checked: 0,
			reconnect: 0,
			deferred: 0,
			skipped: 1
		});
		expect(check).not.toHaveBeenCalled();
		expect(db.pageToken).not.toHaveBeenCalled();
	});
	it('marks missing credentials for reconnect without attempting a Graph call', async () => {
		const db: MessengerHealthClient = { ...client(1), pageToken: async () => null };
		const check = vi.fn();
		expect((await checkDueMessengerConnections({ client: db, check, now })).reconnect).toBe(1);
		expect(check).not.toHaveBeenCalled();
		expect(db.finish).toHaveBeenCalledWith(
			expect.objectContaining({ id: 'c0' }),
			now.toISOString(),
			'token_invalid'
		);
	});
});
