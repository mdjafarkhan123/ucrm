import { beforeEach, describe, expect, it, vi } from 'vitest';
import { PATCH } from './+server';
import { requireOrganization } from '$lib/server/auth/organization';
import { resolveOrganizationAccess } from '$lib/server/access/effective';

vi.mock('$lib/server/auth/organization', () => ({
	requireOrganization: vi.fn()
}));

// Only the resolver is faked. `hasPermission` stays real, so the route's answer about internal cost is
// the one a live request would get from the same access map.
vi.mock('$lib/server/access/effective', async (importOriginal) => ({
	...(await importOriginal<typeof import('$lib/server/access/effective')>()),
	resolveOrganizationAccess: vi.fn()
}));

const mockedRequire = vi.mocked(requireOrganization);
const mockedAccess = vi.mocked(resolveOrganizationAccess);
const requestId = '00000000-0000-4000-8000-000000000041';
const catalogItemId = '00000000-0000-4000-8000-000000000042';

// Stands in for the catalog read the route makes when it has to fill a cost back in. Resolves on await,
// which is how the route finishes that call.
function catalogTable(rows: Array<{ id: string; unit_cost_minor: number }>) {
	const chain: Record<string, unknown> = {};
	for (const method of ['select', 'eq', 'in']) chain[method] = () => chain;
	chain.then = (...args: unknown[]) =>
		(
			Promise.resolve({ data: rows, error: null }) as unknown as {
				then: (...a: unknown[]) => unknown;
			}
		).then(...args);
	return chain;
}

function event(
	body: unknown,
	rpc = vi.fn(),
	catalogRows: Array<{ id: string; unit_cost_minor: number }> = []
) {
	return {
		params: { id: requestId },
		request: new Request(`http://localhost/api/requests/${requestId}/pricing`, {
			method: 'PATCH',
			headers: { 'content-type': 'application/json' },
			body: typeof body === 'string' ? body : JSON.stringify(body)
		}),
		locals: { supabase: { rpc, from: vi.fn(() => catalogTable(catalogRows)) } }
	} as unknown as Parameters<typeof PATCH>[0];
}

function line(overrides: Record<string, unknown> = {}) {
	return {
		name: 'Gutter clearing',
		category: 'service',
		quantity: 2,
		unit_price_minor: 12500,
		unit_cost_minor: 4000,
		...overrides
	};
}

describe('request pricing API', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		mockedRequire.mockResolvedValue({
			organization: { id: 'org-1' },
			user: { id: 'user-1' }
		} as never);
		mockedAccess.mockResolvedValue({ permissions: {}, features: {} } as never);
	});

	describe('internal cost', () => {
		const priced = { expected_revision: 3 };

		it('fills a price book cost back in for a saver who may not see cost', async () => {
			const rpc = vi.fn().mockResolvedValue({ data: {}, error: null });
			await PATCH(
				event(
					{
						...priced,
						lines: [line({ catalog_item_id: catalogItemId, unit_cost_minor: 0 })]
					},
					rpc,
					[{ id: catalogItemId, unit_cost_minor: 4000 }]
				)
			);

			expect(rpc.mock.calls[0][1].new_lines[0].unit_cost_minor).toBe(4000);
		});

		it('leaves a cost the line already carries alone', async () => {
			const rpc = vi.fn().mockResolvedValue({ data: {}, error: null });
			await PATCH(
				event(
					{ ...priced, lines: [line({ catalog_item_id: catalogItemId, unit_cost_minor: 999 })] },
					rpc,
					[{ id: catalogItemId, unit_cost_minor: 4000 }]
				)
			);

			expect(rpc.mock.calls[0][1].new_lines[0].unit_cost_minor).toBe(999);
		});

		it('never fills a cost in for a saver who may see cost', async () => {
			mockedAccess.mockResolvedValue({
				permissions: { 'quotes.view_cost': true },
				features: { 'core.quotes': true }
			} as never);
			const rpc = vi.fn().mockResolvedValue({ data: {}, error: null });

			await PATCH(
				event(
					{ ...priced, lines: [line({ catalog_item_id: catalogItemId, unit_cost_minor: 0 })] },
					rpc,
					[{ id: catalogItemId, unit_cost_minor: 4000 }]
				)
			);

			expect(rpc.mock.calls[0][1].new_lines[0].unit_cost_minor).toBe(0);
		});

		it('does not work out who the saver is when the saved item costs nothing anyway', async () => {
			const rpc = vi.fn().mockResolvedValue({ data: {}, error: null });

			await PATCH(
				event(
					{ ...priced, lines: [line({ catalog_item_id: catalogItemId, unit_cost_minor: 0 })] },
					rpc,
					[{ id: catalogItemId, unit_cost_minor: 0 }]
				)
			);

			expect(mockedAccess).not.toHaveBeenCalled();
		});

		it('leaves a one-off line with no saved item alone', async () => {
			const rpc = vi.fn().mockResolvedValue({ data: {}, error: null });
			const target = event({ ...priced, lines: [line({ unit_cost_minor: 0 })] }, rpc);

			await PATCH(target);

			expect(target.locals.supabase.from).not.toHaveBeenCalled();
			expect(rpc.mock.calls[0][1].new_lines[0].unit_cost_minor).toBe(0);
		});
	});

	it('refuses a signed-out caller before touching the database', async () => {
		mockedRequire.mockResolvedValue(null as never);
		const rpc = vi.fn();

		const response = await PATCH(event({ expected_revision: 0, lines: [] }, rpc));

		expect(response.status).toBe(401);
		expect(rpc).not.toHaveBeenCalled();
	});

	it('rejects a body that is not valid JSON', async () => {
		const rpc = vi.fn();
		const response = await PATCH(event('not json', rpc));

		expect(response.status).toBe(422);
		expect(rpc).not.toHaveBeenCalled();
	});

	it('rejects a price that is not whole cents', async () => {
		const rpc = vi.fn();
		const response = await PATCH(
			event({ expected_revision: 1, lines: [line({ unit_price_minor: 12.5 })] }, rpc)
		);

		expect(response.status).toBe(422);
		const body = await response.json();
		expect(body.field_errors['lines.0.unit_price_minor']).toBeDefined();
		expect(rpc).not.toHaveBeenCalled();
	});

	it('rejects a quantity finer than a thousandth', async () => {
		const rpc = vi.fn();
		const response = await PATCH(
			event({ expected_revision: 1, lines: [line({ quantity: 1.2345 })] }, rpc)
		);

		expect(response.status).toBe(422);
		expect(rpc).not.toHaveBeenCalled();
	});

	it('rejects a labor line that is not a service', async () => {
		const rpc = vi.fn();
		const response = await PATCH(
			event({ expected_revision: 1, lines: [line({ category: 'product', is_labor: true })] }, rpc)
		);

		expect(response.status).toBe(422);
		const body = await response.json();
		expect(body.field_errors['lines.0.category']).toBeDefined();
		expect(rpc).not.toHaveBeenCalled();
	});

	it('sends an empty list through as an emptied price table', async () => {
		const rpc = vi
			.fn()
			.mockResolvedValue({ data: { revision: 4, line_count: 0, subtotal_minor: 0 }, error: null });

		const response = await PATCH(event({ expected_revision: 3, lines: [] }, rpc));

		expect(rpc).toHaveBeenCalledWith('replace_request_pricing_lines', {
			target_request_id: requestId,
			expected_revision: 3,
			new_lines: []
		});
		expect(response.status).toBe(200);
		expect(await response.json()).toEqual({ revision: 4, line_count: 0, subtotal_minor: 0 });
	});

	it('fills the defaults the database expects and passes the catalog item through', async () => {
		const rpc = vi.fn().mockResolvedValue({
			data: { revision: 2, line_count: 1, subtotal_minor: 25000 },
			error: null
		});

		await PATCH(
			event({ expected_revision: 1, lines: [line({ catalog_item_id: catalogItemId })] }, rpc)
		);

		expect(rpc.mock.calls[0][1].new_lines[0]).toEqual({
			name: 'Gutter clearing',
			category: 'service',
			is_labor: false,
			catalog_item_id: catalogItemId,
			description: null,
			unit_label: null,
			quantity: 2,
			unit_price_minor: 12500,
			unit_cost_minor: 4000,
			is_taxable: true,
			image_attachment_id: null
		});
	});

	it('turns a stale revision into a reload conflict', async () => {
		const rpc = vi.fn().mockResolvedValue({
			data: null,
			error: { code: 'P0409', message: 'Someone else changed this pricing while you were editing.' }
		});

		const response = await PATCH(event({ expected_revision: 1, lines: [line()] }, rpc));

		expect(response.status).toBe(409);
		const body = await response.json();
		expect(body.reason).toBe('stale');
	});

	it('turns a closed request into a field error', async () => {
		const rpc = vi.fn().mockResolvedValue({
			data: null,
			error: { code: '23514', message: 'This request is closed and its pricing cannot be changed.' }
		});

		const response = await PATCH(event({ expected_revision: 1, lines: [line()] }, rpc));

		expect(response.status).toBe(422);
		const body = await response.json();
		expect(body.field_errors.form).toBe(
			'This request is closed and its pricing cannot be changed.'
		);
	});

	it('turns a refusal from the write function into a generic not-found', async () => {
		const rpc = vi.fn().mockResolvedValue({
			data: null,
			error: { code: '42501', message: 'insufficient_privilege' }
		});

		const response = await PATCH(event({ expected_revision: 1, lines: [line()] }, rpc));

		expect(response.status).toBe(404);
	});

	it('turns any other database error into a generic failure', async () => {
		const rpc = vi
			.fn()
			.mockResolvedValue({ data: null, error: { code: '08000', message: 'connection failure' } });

		const response = await PATCH(event({ expected_revision: 1, lines: [line()] }, rpc));

		expect(response.status).toBe(500);
	});
});
