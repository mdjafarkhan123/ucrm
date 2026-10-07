import { describe, expect, it, vi } from 'vitest';
import { GET } from './+server';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';

vi.mock('$lib/server/auth/owner', () => ({
	getOwnerSession: vi.fn(),
	isOwnerEmail: (email: string) => email === 'owner@example.com'
}));
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));

describe('The review queue', () => {
	it('names who prepared each Lead the way the history does', async () => {
		vi.mocked(getOwnerSession).mockResolvedValue({
			email: 'owner@example.com',
			sessionId: 'session-id',
			role: null,
			access: null,
			memberId: null,
			name: null
		});
		const lead = (id: string, preparedBy: string, email: string) => ({
			id,
			business_name: id,
			prepared_by: preparedBy,
			prepared_by_email: email
		});
		const rpc = vi.fn().mockResolvedValue({
			data: {
				leads: [
					// The database falls back to the email when it has no teammate name.
					lead('a', 'owner@example.com', 'owner@example.com'),
					lead('b', 'Sam Seller', 'sam@example.com'),
					lead('c', 'new@example.com', 'new@example.com')
				],
				next_cursor: null,
				total: 3
			},
			error: null
		});
		vi.mocked(getOwnerSupabaseClient).mockReturnValue({ rpc } as unknown as ReturnType<
			typeof getOwnerSupabaseClient
		>);

		const url = 'http://localhost/api/jafar/leads/review';
		const response = await GET({ url: new URL(url), request: new Request(url) } as never);
		const page = await response.json();

		expect(page.leads.map((entry: { prepared_by: string }) => entry.prepared_by)).toEqual([
			'Jafar',
			'Sam Seller',
			'new@example.com'
		]);
		expect(page.leads[0]).not.toHaveProperty('prepared_by_email');
	});
});
