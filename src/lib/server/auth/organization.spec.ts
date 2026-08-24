import { beforeEach, describe, expect, it, vi } from 'vitest';
import { getOrganizationContext } from './organization';

const userId = '00000000-0000-4000-8000-000000000031';
const user = { id: userId } as never;

function eventWith(result: { data: unknown; error: unknown }) {
	const filters: Record<string, unknown> = {};
	const builder = {
		select: () => builder,
		eq: (column: string, value: unknown) => {
			filters[column] = value;
			return builder;
		},
		maybeSingle: () => Promise.resolve(result)
	};
	const from = vi.fn(() => builder);
	return {
		event: { locals: { supabase: { from }, getUser: vi.fn() } } as never,
		filters,
		from
	};
}

const activeRow = {
	organization_id: 'org-id',
	role: 'office',
	organizations: { id: 'org-id', name: 'Northline Roofing' }
};

describe('getOrganizationContext', () => {
	beforeEach(() => vi.clearAllMocks());

	it('asks only for an active membership', async () => {
		const { event, filters } = eventWith({ data: activeRow, error: null });

		const context = await getOrganizationContext(event, user);

		expect(filters).toEqual({ user_id: userId, status: 'active' });
		expect(context?.organization).toEqual({
			id: 'org-id',
			name: 'Northline Roofing',
			role: 'office'
		});
	});

	// A pending, deactivated or removed member matches no row once status is filtered, so the query comes
	// back empty and there is no organization to be in.
	it('gives no organization when no active membership comes back', async () => {
		const { event } = eventWith({ data: null, error: null });

		expect(await getOrganizationContext(event, user)).toBeNull();
	});

	it('gives no organization when the membership query fails', async () => {
		const { event } = eventWith({ data: null, error: { message: 'nope' } });

		expect(await getOrganizationContext(event, user)).toBeNull();
	});

	it('does not query at all without a signed-in user', async () => {
		const { event, from } = eventWith({ data: activeRow, error: null });
		(event as { locals: { getUser: () => Promise<null> } }).locals.getUser = () =>
			Promise.resolve(null);

		expect(await getOrganizationContext(event)).toBeNull();
		expect(from).not.toHaveBeenCalled();
	});
});
