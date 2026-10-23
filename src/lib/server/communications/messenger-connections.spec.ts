import { describe, expect, it, vi } from 'vitest';

vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: () => ({}) }));
vi.mock('$env/dynamic/private', () => ({ env: {} }));

const { messengerConnectionView, messengerPageChoiceState } =
	await import('./messenger-connections');

describe('messengerPageChoiceState', () => {
	const ours = new Map([
		['1', 'active'],
		['2', 'needs_reconnect'],
		['3', 'disconnected']
	]);
	const elsewhere = new Set(['9']);
	const page = (id: string, canMessage = true) => ({ id, canMessage });

	it('greys out a Page already on this business', () => {
		expect(messengerPageChoiceState(page('1'), ours, elsewhere)).toBe('connected');
	});
	it('lets a Page that needs a new key be ticked again', () => {
		expect(messengerPageChoiceState(page('2'), ours, elsewhere)).toBe('reconnect');
	});
	it('offers a disconnected Page as new, so its threads resume', () => {
		expect(messengerPageChoiceState(page('3'), ours, elsewhere)).toBe('available');
	});
	it('refuses a Page another business has', () => {
		expect(messengerPageChoiceState(page('9'), ours, elsewhere)).toBe('elsewhere');
	});
	it('refuses a Page the person cannot message from', () => {
		expect(messengerPageChoiceState(page('5', false), ours, elsewhere)).toBe('no_permission');
		expect(messengerPageChoiceState(page('2', false), ours, elsewhere)).toBe('no_permission');
	});
});

describe('messengerConnectionView', () => {
	const row = {
		id: 'c1',
		page_id: '1',
		page_name: 'Uplift Contractor',
		status: 'active',
		needs_reconnect_reason: null,
		is_default: true,
		connected_at: '2026-10-23T01:00:00Z',
		updated_at: '2026-10-23T02:00:00Z',
		last_event_received_at: null
	};
	const none = { connectedByName: 'Jafar Khan', lastMessage: null };

	it('waits for a test until the first message arrives', () => {
		expect(messengerConnectionView(row, none).status).toBe('waiting');
	});
	it('says receiving once a message has arrived', () => {
		expect(
			messengerConnectionView({ ...row, last_event_received_at: '2026-10-23T03:00:00Z' }, none)
				.status
		).toBe('receiving');
	});
	it('says what went wrong and since when when Facebook ended it', () => {
		const view = messengerConnectionView(
			{ ...row, status: 'needs_reconnect', needs_reconnect_reason: 'permission_missing' },
			none
		);
		expect(view).toMatchObject({
			status: 'reconnect',
			reason: 'permission_missing',
			problem_at: '2026-10-23T02:00:00Z'
		});
	});
});
