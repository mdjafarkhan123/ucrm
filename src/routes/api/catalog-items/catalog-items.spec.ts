import { beforeEach, describe, expect, it, vi } from 'vitest';
import { GET, POST } from './+server';
import { requireOrganizationPermission } from '$lib/server/access/permission';

// Only the gate is faked. `hasPermission` stays real, so a test that hands over an access map gets the
// same answer about internal cost that a live request would.
vi.mock('$lib/server/access/permission', async (importOriginal) => ({
	...(await importOriginal<typeof import('$lib/server/access/permission')>()),
	requireOrganizationPermission: vi.fn()
}));

const mockedRequire = vi.mocked(requireOrganizationPermission);
const context = {
	auth: { organization: { id: 'org-1' }, user: { id: 'user-1' } },
	access: { permissions: {}, features: {} }
} as never;

// The builder records every filter the route applied so a test can assert on the query, and resolves on
// await or on single(), the two ways the routes finish a call.
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

function item(overrides: Record<string, unknown> = {}) {
	return {
		id: '00000000-0000-4000-8000-000000000071',
		category: 'service',
		name: 'Gutter clearing',
		unit_price_minor: 12500,
		unit_cost_minor: 4000,
		is_taxable: true,
		is_labor: false,
		archived_at: null,
		...overrides
	};
}

function listEvent(query: string, result: unknown) {
	const table = builder(result);
	return {
		url: new URL(`http://localhost/api/catalog-items${query}`),
		locals: { supabase: { from: vi.fn(() => table) } },
		__table: table
	} as unknown as Parameters<typeof GET>[0] & { __table: { __calls: Array<[string, unknown[]]> } };
}

function createEvent(body: unknown, result: unknown) {
	const table = builder(result);
	return {
		request: new Request('http://localhost/api/catalog-items', {
			method: 'POST',
			headers: { 'content-type': 'application/json' },
			body: typeof body === 'string' ? body : JSON.stringify(body)
		}),
		locals: { supabase: { from: vi.fn(() => table) } },
		__table: table
	} as unknown as Parameters<typeof POST>[0] & { __table: { __calls: Array<[string, unknown[]]> } };
}

describe('catalog items API', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		mockedRequire.mockResolvedValue(context);
	});

	it('returns the permission check response without reading anything', async () => {
		mockedRequire.mockResolvedValue({ response: new Response(null, { status: 403 }) } as never);
		const target = listEvent('', { data: [], error: null });

		const response = await GET(target);

		expect(response.status).toBe(403);
		expect(target.locals.supabase.from).not.toHaveBeenCalled();
	});

	it('hides archived items unless they are asked for', async () => {
		const target = listEvent('', { data: [item()], error: null });

		await GET(target);

		expect(target.__table.__calls).toContainEqual(['is', ['archived_at', null]]);
	});

	it('includes archived items when asked', async () => {
		const target = listEvent('?include_archived=true', { data: [item()], error: null });

		await GET(target);

		expect(target.__table.__calls.some(([name]) => name === 'is')).toBe(false);
	});

	it('escapes ilike wildcards and searches name and description together', async () => {
		const target = listEvent('?search=50%25 off_x', { data: [], error: null });

		await GET(target);

		expect(target.__table.__calls).toContainEqual([
			'or',
			['name.ilike.%50\\% off\\_x%,description.ilike.%50\\% off\\_x%']
		]);
	});

	it('sorts by selling price using its own index column', async () => {
		const target = listEvent('?sort=price&dir=desc', { data: [item()], error: null });

		await GET(target);

		expect(target.__table.__calls).toContainEqual([
			'order',
			['unit_price_minor', { ascending: false }]
		]);
		expect(target.__table.__calls).toContainEqual(['order', ['id', { ascending: false }]]);
	});

	it('sorts by most recently updated', async () => {
		const target = listEvent('?sort=updated', { data: [item()], error: null });

		await GET(target);

		expect(target.__table.__calls).toContainEqual(['order', ['updated_at', { ascending: true }]]);
	});

	it('filters to only taxable or only exempt items', async () => {
		const onlyTaxable = listEvent('?taxable=only', { data: [], error: null });
		await GET(onlyTaxable);
		expect(onlyTaxable.__table.__calls).toContainEqual(['eq', ['is_taxable', true]]);

		const onlyExempt = listEvent('?taxable=exclude', { data: [], error: null });
		await GET(onlyExempt);
		expect(onlyExempt.__table.__calls).toContainEqual(['eq', ['is_taxable', false]]);
	});

	it('pages with a keyset cursor rather than an offset', async () => {
		const rows = Array.from({ length: 26 }, (_, index) =>
			item({ id: `item-${index}`, name: `Item ${index}` })
		);
		const target = listEvent('?limit=25', { data: rows, error: null });

		const body = await (await GET(target)).json();

		expect(body.items).toHaveLength(25);
		expect(body.next_cursor).toBe('Item 24|item-24');
		expect(target.__table.__calls).toContainEqual(['limit', [26]]);
		expect(target.__table.__calls.some(([name]) => name === 'range')).toBe(false);
	});

	it('rejects a limit above the page ceiling', async () => {
		const response = await GET(listEvent('?limit=500', { data: [], error: null }));

		expect(response.status).toBe(422);
	});

	it('never selects internal cost for someone who may not see it', async () => {
		const target = listEvent('', { data: [item()], error: null });

		const body = await (await GET(target)).json();

		const select = target.__table.__calls.find(([name]) => name === 'select');
		expect(String(select?.[1][0])).not.toContain('unit_cost_minor');
		expect(body.can_view_cost).toBe(false);
	});

	it('selects internal cost for someone who may see it', async () => {
		mockedRequire.mockResolvedValue({
			auth: { organization: { id: 'org-1' }, user: { id: 'user-1' } },
			access: { permissions: { 'quotes.view_cost': true }, features: { 'core.quotes': true } }
		} as never);
		const target = listEvent('', { data: [item()], error: null });

		const body = await (await GET(target)).json();

		const select = target.__table.__calls.find(([name]) => name === 'select');
		expect(String(select?.[1][0])).toContain('unit_cost_minor');
		expect(body.can_view_cost).toBe(true);
	});

	it('narrows the price book to one category when the drawer asks', async () => {
		const target = listEvent('?category=product', { data: [], error: null });

		await GET(target);

		expect(target.__table.__calls).toContainEqual(['eq', ['category', 'product']]);
	});

	it('creates an item scoped to the caller organization', async () => {
		const target = createEvent(
			{ category: 'service', name: 'Gutter clearing', unit_price_minor: 12500 },
			{ data: item(), error: null }
		);

		const response = await POST(target);

		expect(response.status).toBe(201);
		const insert = target.__table.__calls.find(([name]) => name === 'insert');
		expect(insert?.[1][0]).toMatchObject({
			organization_id: 'org-1',
			created_by: 'user-1',
			name: 'Gutter clearing',
			unit_price_minor: 12500,
			unit_cost_minor: 0,
			is_taxable: true
		});
	});

	it('rejects a labor item that is not a service', async () => {
		const target = createEvent(
			{ category: 'product', name: 'Crew hour', is_labor: true },
			{ data: null, error: null }
		);

		const response = await POST(target);

		expect(response.status).toBe(422);
		expect((await response.json()).field_errors.category).toBeDefined();
		expect(target.locals.supabase.from).not.toHaveBeenCalled();
	});

	it('rejects a body that is not valid JSON', async () => {
		const response = await POST(createEvent('not json', { data: null, error: null }));

		expect(response.status).toBe(422);
	});

	it('turns a row level security refusal into a permission answer', async () => {
		const target = createEvent(
			{ category: 'service', name: 'Gutter clearing' },
			{ data: null, error: { code: '42501', message: 'new row violates row-level security' } }
		);

		const response = await POST(target);

		expect(response.status).toBe(403);
		expect((await response.json()).reason).toBe('permission_denied');
	});
});
