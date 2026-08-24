import { beforeEach, describe, expect, it, vi } from 'vitest';
import { PATCH } from './+server';
import { requireOrganizationPermission } from '$lib/server/access/permission';

// Only the gate is faked. `hasPermission` stays real, so a test that hands over an access map gets the
// same answer about internal cost that a live request would.
vi.mock('$lib/server/access/permission', async (importOriginal) => ({
	...(await importOriginal<typeof import('$lib/server/access/permission')>()),
	requireOrganizationPermission: vi.fn()
}));

const mockedRequire = vi.mocked(requireOrganizationPermission);
const itemId = '00000000-0000-4000-8000-000000000081';
const context = {
	auth: { organization: { id: 'org-1' }, user: { id: 'user-1' } },
	access: { permissions: {}, features: {} }
} as never;

function builder(result: unknown) {
	const calls: Array<[string, unknown[]]> = [];
	const chain: Record<string | symbol, unknown> = new Proxy(
		{},
		{
			get(_target, property) {
				if (property === '__calls') return calls;
				if (property === 'single' || property === 'maybeSingle')
					return () => Promise.resolve(result);
				if (property === 'then')
					return (...args: unknown[]) =>
						(Promise.resolve(result) as unknown as { then: (...a: unknown[]) => unknown }).then(
							...args
						);
				return (...args: unknown[]) => {
					calls.push([String(property), args]);
					return chain;
				};
			}
		}
	);
	return chain;
}

function event(body: unknown, result: unknown) {
	const table = builder(result);
	return {
		params: { id: itemId },
		request: new Request(`http://localhost/api/catalog-items/${itemId}`, {
			method: 'PATCH',
			headers: { 'content-type': 'application/json' },
			body: typeof body === 'string' ? body : JSON.stringify(body)
		}),
		locals: { supabase: { from: vi.fn(() => table) } },
		__table: table
	} as unknown as Parameters<typeof PATCH>[0] & {
		__table: { __calls: Array<[string, unknown[]]> };
	};
}

function changes(target: { __table: { __calls: Array<[string, unknown[]]> } }) {
	return target.__table.__calls.find(([name]) => name === 'update')?.[1][0] as Record<
		string,
		unknown
	>;
}

const stored = { id: itemId, name: 'Gutter clearing', archived_at: null };

describe('catalog item API', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		mockedRequire.mockResolvedValue(context);
	});

	it('returns the permission check response without writing anything', async () => {
		mockedRequire.mockResolvedValue({ response: new Response(null, { status: 403 }) } as never);
		const target = event({ name: 'Renamed' }, { data: stored, error: null });

		const response = await PATCH(target);

		expect(response.status).toBe(403);
		expect(target.locals.supabase.from).not.toHaveBeenCalled();
	});

	it('changes only the fields that were sent', async () => {
		const target = event({ unit_price_minor: 15000 }, { data: stored, error: null });

		await PATCH(target);

		expect(changes(target)).toEqual({ unit_price_minor: 15000 });
	});

	it('clears a description only when null is sent explicitly', async () => {
		const target = event({ description: null }, { data: stored, error: null });

		await PATCH(target);

		expect(changes(target)).toEqual({ description: null });
	});

	it('archives by stamping a time rather than deleting the row', async () => {
		const target = event({ archived: true }, { data: stored, error: null });

		await PATCH(target);

		const applied = changes(target);
		expect(typeof applied.archived_at).toBe('string');
		expect(target.__table.__calls.some(([name]) => name === 'delete')).toBe(false);
	});

	it('restores an archived item by clearing the stamp', async () => {
		const target = event({ archived: false }, { data: stored, error: null });

		await PATCH(target);

		expect(changes(target)).toEqual({ archived_at: null });
	});

	it('rejects an empty change', async () => {
		const target = event({}, { data: stored, error: null });

		const response = await PATCH(target);

		expect(response.status).toBe(422);
		expect(target.locals.supabase.from).not.toHaveBeenCalled();
	});

	it('answers not-found for an item in another organization', async () => {
		const target = event({ name: 'Renamed' }, { data: null, error: null });

		const response = await PATCH(target);

		expect(response.status).toBe(404);
	});

	it('turns any other database error into a generic failure', async () => {
		const target = event(
			{ name: 'Renamed' },
			{ data: null, error: { code: '08000', message: 'connection failure' } }
		);

		const response = await PATCH(target);

		expect(response.status).toBe(500);
	});
});
