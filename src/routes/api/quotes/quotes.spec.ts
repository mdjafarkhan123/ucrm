import { beforeEach, describe, expect, it, vi } from 'vitest';
import { GET, POST } from './+server';
import { requireOrganizationPermission } from '$lib/server/access/permission';

vi.mock('$lib/server/access/permission', async () => {
	const actual = await vi.importActual<typeof import('$lib/server/access/permission')>(
		'$lib/server/access/permission'
	);
	return { ...actual, requireOrganizationPermission: vi.fn() };
});

const mockedRequire = vi.mocked(requireOrganizationPermission);
const clientId = '00000000-0000-4000-8000-000000000071';
const propertyId = '00000000-0000-4000-8000-000000000072';

// PostgREST's builder is a chain that resolves on await, so the stub records what was asked for and
// answers the same result however the route finishes the call.
function builder(result: unknown) {
	const calls: Array<{ method: string; args: unknown[] }> = [];
	const chain: Record<string | symbol, unknown> = new Proxy(
		{},
		{
			get(_target, property) {
				if (property === '__calls') return calls;
				if (property === 'then')
					return (...args: unknown[]) =>
						(Promise.resolve(result) as unknown as { then: (...a: unknown[]) => unknown }).then(
							...args
						);
				return (...args: unknown[]) => {
					calls.push({ method: String(property), args });
					return chain;
				};
			}
		}
	);
	return chain;
}

const rows = [
	{
		id: 'quote-1',
		quote_number: 2,
		title: 'Panel upgrade',
		status: 'draft',
		currency_code: 'USD',
		created_at: '2026-08-20T10:00:00Z',
		client_id: clientId,
		request_id: null,
		client: { id: clientId, display_name: 'Abbas Uddin', company_name: null },
		property: { id: propertyId, label: 'Home', address_line1: '12 Mill Road', city: 'Savar' },
		draft: { id: 'version-1', total_minor: 45000 },
		published: null
	}
];

function context(permissions: Record<string, boolean>) {
	return {
		auth: { organization: { id: 'org-1' }, user: { id: 'user-1' } },
		access: { permissions, features: { 'core.quotes': true } }
	} as never;
}

function listEvent(url: string, result: unknown = { data: rows, error: null }) {
	const chain = builder(result);
	return {
		url: new URL(`http://localhost/api/quotes${url}`),
		locals: { supabase: { from: vi.fn(() => chain) } },
		__chain: chain as unknown as { __calls: Array<{ method: string; args: unknown[] }> }
	} as unknown as Parameters<typeof GET>[0] & {
		__chain: { __calls: Array<{ method: string; args: unknown[] }> };
	};
}

function calls(event: { __chain: { __calls: Array<{ method: string; args: unknown[] }> } }) {
	return event.__chain.__calls;
}

function createEvent(
	body: unknown,
	rpcResult: unknown = { data: { quote_id: 'q1' }, error: null }
) {
	const rpc = vi.fn(() => Promise.resolve(rpcResult));
	return {
		request: new Request('http://localhost/api/quotes', {
			method: 'POST',
			body: JSON.stringify(body)
		}),
		locals: { supabase: { rpc } },
		__rpc: rpc
	} as unknown as Parameters<typeof POST>[0] & { __rpc: ReturnType<typeof vi.fn> };
}

describe('quote list API', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		mockedRequire.mockResolvedValue(context({ 'quotes.view': true, 'quotes.view_price': true }));
	});

	it('returns the permission check response without reading anything', async () => {
		mockedRequire.mockResolvedValue({ response: new Response(null, { status: 403 }) } as never);
		const target = listEvent('');

		const response = await GET(target);

		expect(response.status).toBe(403);
		expect(target.locals.supabase.from).not.toHaveBeenCalled();
	});

	it('hides archived quotes until somebody asks for them', async () => {
		const target = listEvent('');

		await GET(target);
		const filter = calls(target).find((call) => call.method === 'in');

		expect(filter?.args[1]).not.toContain('archived');
		expect(filter?.args[1]).toContain('draft');
	});

	it('asks for exactly the statuses the filter names', async () => {
		const target = listEvent('?status=approved,archived');

		await GET(target);
		const filter = calls(target).find((call) => call.method === 'in');

		expect(filter?.args[1]).toEqual(['approved', 'archived']);
	});

	it('never asks for the total when the member may not see money', async () => {
		mockedRequire.mockResolvedValue(context({ 'quotes.view': true, 'quotes.view_price': false }));
		const target = listEvent('');

		const body = await (await GET(target)).json();
		const select = calls(target).find((call) => call.method === 'select');

		expect(String(select?.args[0])).not.toContain('total_minor');
		expect(body.quotes[0].total_minor).toBeNull();
	});

	it('shows the published total for a quote with no draft left', async () => {
		const target = listEvent('', {
			data: [
				{
					...rows[0],
					status: 'sent',
					draft: null,
					published: { id: 'version-2', total_minor: 39000 }
				}
			],
			error: null
		});

		const body = await (await GET(target)).json();

		expect(body.quotes[0].total_minor).toBe(39000);
	});

	it('pages by seeking to the cursor instead of counting past it', async () => {
		const target = listEvent('?cursor=2026-08-20T10:00:00Z|quote-1');

		await GET(target);
		const seek = calls(target).find((call) => call.method === 'lte');

		expect(seek?.args[0]).toBe('created_at');
		expect(calls(target).some((call) => call.method === 'range')).toBe(false);
	});

	it('sorts by quote number when asked, and by nothing else', async () => {
		const target = listEvent('?sort=number&dir=asc');

		await GET(target);
		const order = calls(target).find((call) => call.method === 'order');

		expect(order?.args[0]).toBe('quote_number');

		const rejected = await GET(listEvent('?sort=client'));
		expect(rejected.status).toBe(422);
	});

	it('searches a number against the number column and a word against the title', async () => {
		const numeric = listEvent('?search=12');
		await GET(numeric);
		expect(String(calls(numeric).find((call) => call.method === 'or')?.args[0])).toContain(
			'quote_number.eq.12'
		);

		const word = listEvent('?search=panel');
		await GET(word);
		expect(calls(word).find((call) => call.method === 'ilike')?.args[0]).toBe('title');
	});

	it('turns a read failure into a generic failure', async () => {
		const response = await GET(
			listEvent('', { data: null, error: { code: '08000', message: 'connection failure' } })
		);

		expect(response.status).toBe(500);
	});
});

describe('quote create API', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		mockedRequire.mockResolvedValue(context({ 'quotes.create': true }));
	});

	it('refuses a body with no client', async () => {
		const target = createEvent({ title: 'Panel upgrade', property_id: propertyId });

		const response = await POST(target);

		expect(response.status).toBe(422);
		expect(target.__rpc).not.toHaveBeenCalled();
	});

	it('refuses a title of one character before touching the database', async () => {
		const target = createEvent({ client_id: clientId, property_id: propertyId, title: 'x' });

		expect((await POST(target)).status).toBe(422);
		expect(target.__rpc).not.toHaveBeenCalled();
	});

	it('creates through the one command that owns numbering', async () => {
		const target = createEvent({
			client_id: clientId,
			property_id: propertyId,
			title: 'Panel upgrade',
			contract_disclaimer: '  Payment due on completion.  '
		});

		const response = await POST(target);

		expect(response.status).toBe(201);
		expect(target.__rpc).toHaveBeenCalledWith('create_quote', {
			target_client_id: clientId,
			target_property_id: propertyId,
			quote_title: 'Panel upgrade',
			disclaimer: 'Payment due on completion.'
		});
	});

	it('turns a refused client into a not-found rather than a hint', async () => {
		const target = createEvent(
			{ client_id: clientId, property_id: propertyId, title: 'Panel upgrade' },
			{ data: null, error: { code: '42501', message: 'no access' } }
		);

		expect((await POST(target)).status).toBe(404);
	});

	it('turns a rejected property into a field error a person can act on', async () => {
		const target = createEvent(
			{ client_id: clientId, property_id: propertyId, title: 'Panel upgrade' },
			{
				data: null,
				error: { code: '23514', message: 'Choose a live property belonging to this client.' }
			}
		);
		const response = await POST(target);

		expect(response.status).toBe(422);
		expect((await response.json()).field_errors.form).toContain('live property');
	});
});
