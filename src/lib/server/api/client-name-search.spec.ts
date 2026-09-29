import { describe, expect, it, vi } from 'vitest';
import { CLIENT_NAME_SEARCH_LIMIT, clientNameSearchBranch } from './client-name-search';

function supabaseReturning(result: { data: Array<{ id: string }> | null; error: unknown }) {
	const chain = {
		select: vi.fn(() => chain),
		eq: vi.fn(() => chain),
		is: vi.fn(() => chain),
		or: vi.fn(() => chain),
		limit: vi.fn(() => Promise.resolve(result))
	};
	return { client: { from: vi.fn(() => chain) } as never, chain };
}

const ids = (count: number) => Array.from({ length: count }, (_, index) => ({ id: `c${index}` }));

describe('clientNameSearchBranch', () => {
	it('asks for one more client than it keeps, so it can tell when the list was cut', async () => {
		const { client, chain } = supabaseReturning({ data: ids(3), error: null });

		const result = await clientNameSearchBranch(client, 'org-1', '"%abbas%"');

		expect(chain.or).toHaveBeenCalledWith(
			'display_name.ilike."%abbas%",company_name.ilike."%abbas%"'
		);
		expect(chain.limit).toHaveBeenCalledWith(CLIENT_NAME_SEARCH_LIMIT + 1);
		expect(result).toEqual({ ok: true, branch: ',client_id.in.(c0,c1,c2)', narrowed: false });
	});

	it('keeps the URL short and says so when too many clients match', async () => {
		const { client } = supabaseReturning({ data: ids(CLIENT_NAME_SEARCH_LIMIT + 1), error: null });

		const result = await clientNameSearchBranch(client, 'org-1', '"%a%"');

		if (!result.ok) throw new Error('expected a result');
		expect(result.narrowed).toBe(true);
		expect(result.branch.split(',').length - 1).toBe(CLIENT_NAME_SEARCH_LIMIT);
	});

	it('adds nothing when no client matches, and reports a failed lookup', async () => {
		expect(
			await clientNameSearchBranch(
				supabaseReturning({ data: [], error: null }).client,
				'o',
				'"%x%"'
			)
		).toEqual({ ok: true, branch: '', narrowed: false });
		expect(
			await clientNameSearchBranch(
				supabaseReturning({ data: null, error: { message: 'boom' } }).client,
				'o',
				'"%x%"'
			)
		).toEqual({ ok: false });
	});
});
