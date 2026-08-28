import { beforeEach, describe, expect, it, vi } from 'vitest';
import { GET } from './+server';
import { requireOrganizationPermission } from '$lib/server/access/permission';

vi.mock('$lib/server/access/permission', async () => {
	const actual = await vi.importActual<typeof import('$lib/server/access/permission')>(
		'$lib/server/access/permission'
	);
	return { ...actual, requireOrganizationPermission: vi.fn() };
});

const mockedRequire = vi.mocked(requireOrganizationPermission);
const clientId = '00000000-0000-4000-8000-000000000001';

// One global queue: each `.from(table)` call pops the next result in the order the route issues them
// (clients, client_contact_methods, properties, requests, quotes, opportunities) -- matching the
// `email-history` spec's own convention for a route that fires several reads in one `Promise.all`.
function chain(result: { data?: unknown; error?: unknown }) {
	const obj: Record<string, unknown> = {};
	for (const method of ['select', 'eq', 'is', 'order', 'limit']) obj[method] = vi.fn(() => obj);
	obj.maybeSingle = vi.fn(() => Promise.resolve(result));
	(obj as { then: unknown }).then = (...args: unknown[]) =>
		(Promise.resolve(result) as unknown as { then: (...a: unknown[]) => unknown }).then(...args);
	return obj;
}

function fromQueue(results: Array<{ data?: unknown; error?: unknown }>) {
	const queue = [...results];
	const chains: Array<Record<string, unknown>> = [];
	const from = vi.fn(() => {
		const built = chain(queue.shift() ?? { data: null, error: null });
		chains.push(built);
		return built;
	});
	return Object.assign(from, { chains });
}

function event() {
	return {
		params: { clientId },
		locals: { supabase: {} }
	} as unknown as Parameters<typeof GET>[0];
}

describe('reading conversation work context', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		mockedRequire.mockResolvedValue({
			auth: { organization: { id: 'org-1' }, user: { id: 'user-1' } },
			access: { permissions: { 'customers.view': true }, features: {} }
		} as never);
	});

	it('requires customers.view', async () => {
		const from = fromQueue([
			{ data: { id: clientId, display_name: 'Acme', company_name: null, client_type: 'company' } },
			{ data: [] },
			{ data: [] },
			{ data: [] },
			{ data: [] },
			{ data: [] }
		]);
		const supabaseEvent = event();
		(supabaseEvent.locals as { supabase: unknown }).supabase = { from };
		await GET(supabaseEvent);
		expect(mockedRequire).toHaveBeenCalledWith(expect.anything(), 'customers.view');
	});

	it('404s when the client is not in this organization (or is deleted)', async () => {
		const from = fromQueue([
			{ data: null },
			{ data: [] },
			{ data: [] },
			{ data: [] },
			{ data: [] },
			{ data: [] }
		]);
		const supabaseEvent = event();
		(supabaseEvent.locals as { supabase: unknown }).supabase = { from };
		const response = await GET(supabaseEvent);
		expect(response.status).toBe(404);
	});

	it("folds primary contact methods onto the client and returns each category's small recent set", async () => {
		const from = fromQueue([
			{
				data: {
					id: clientId,
					display_name: 'Acme',
					company_name: 'Acme Co',
					client_type: 'company'
				}
			},
			{
				data: [
					{ kind: 'email', value: 'a@example.test' },
					{ kind: 'phone', value: '555-0100' }
				]
			},
			{
				data: [
					{
						id: 'prop-1',
						label: 'Main',
						address_line1: '1 Main St',
						city: 'Metropolis',
						state_region: 'NY',
						postal_code: '10001'
					}
				]
			},
			{
				data: [
					{ id: 'req-1', title: 'Fix roof', status: 'new', created_at: '2026-08-20T00:00:00Z' }
				]
			},
			{
				data: [
					{
						id: 'quote-1',
						quote_number: 42,
						title: 'Roof repair',
						status: 'draft',
						created_at: '2026-08-21T00:00:00Z'
					}
				]
			},
			{ data: [] } // opportunities: empty, e.g. denied by RLS (no pipeline.view) or genuinely none
		]);
		const supabaseEvent = event();
		(supabaseEvent.locals as { supabase: unknown }).supabase = { from };

		const response = await GET(supabaseEvent);
		expect(response.status).toBe(200);
		const body = await response.json();
		expect(body.client).toEqual({
			id: clientId,
			display_name: 'Acme',
			company_name: 'Acme Co',
			client_type: 'company',
			email: 'a@example.test',
			phone: '555-0100'
		});
		expect(body.properties).toHaveLength(1);
		expect(body.requests).toHaveLength(1);
		expect(body.quotes).toHaveLength(1);
		// RLS is the only gate on quotes/opportunities visibility -- an empty array here is
		// indistinguishable from "denied", which is exactly the "no disclosure" behavior the approved
		// plan asks for. The route itself adds no extra permission check on top.
		expect(body.opportunities).toEqual([]);
	});

	it('500s if any of the parallel reads fail', async () => {
		const from = fromQueue([
			{ data: { id: clientId, display_name: 'Acme', company_name: null, client_type: 'person' } },
			{ data: [] },
			{ data: [] },
			{ error: { message: 'boom' } },
			{ data: [] },
			{ data: [] }
		]);
		const supabaseEvent = event();
		(supabaseEvent.locals as { supabase: unknown }).supabase = { from };
		const response = await GET(supabaseEvent);
		expect(response.status).toBe(500);
	});
});
