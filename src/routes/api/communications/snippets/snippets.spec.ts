import { beforeEach, describe, expect, it, vi } from 'vitest';
import { GET, POST } from './+server';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { checkRateLimit } from '$lib/server/security/rate-limit';

vi.mock('$lib/server/access/permission', async (importOriginal) => ({
	...(await importOriginal<typeof import('$lib/server/access/permission')>()),
	requireOrganizationPermission: vi.fn()
}));

vi.mock('$lib/server/security/rate-limit', async (importOriginal) => ({
	...(await importOriginal<typeof import('$lib/server/security/rate-limit')>()),
	checkRateLimit: vi.fn()
}));

const mockedRequire = vi.mocked(requireOrganizationPermission);
const mockedRateLimit = vi.mocked(checkRateLimit);
const context = {
	auth: { organization: { id: 'org-1' }, user: { id: 'user-1' } },
	access: { permissions: {}, features: {} }
} as never;

// Same recording proxy `catalog-items.spec.ts` uses: records every filter applied and resolves on await
// or on single()/maybeSingle(), the two ways these routes finish a call.
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

function snippet(overrides: Record<string, unknown> = {}) {
	return {
		id: '00000000-0000-4000-8000-000000000091',
		folder: null,
		title: 'Thanks for reaching out',
		body: "Thanks for your message -- we'll get back to you shortly.",
		created_at: '2026-08-27T00:00:00Z',
		updated_at: '2026-08-27T00:00:00Z',
		...overrides
	};
}

function listEvent(query: string, result: unknown) {
	const table = builder(result);
	return {
		url: new URL(`http://localhost/api/communications/snippets${query}`),
		locals: { supabase: { from: vi.fn(() => table) } },
		__table: table
	} as unknown as Parameters<typeof GET>[0] & { __table: { __calls: Array<[string, unknown[]]> } };
}

function createEvent(body: unknown, result: unknown) {
	const table = builder(result);
	return {
		request: new Request('http://localhost/api/communications/snippets', {
			method: 'POST',
			headers: { 'content-type': 'application/json' },
			body: typeof body === 'string' ? body : JSON.stringify(body)
		}),
		locals: { supabase: { from: vi.fn(() => table) } },
		__table: table
	} as unknown as Parameters<typeof POST>[0] & { __table: { __calls: Array<[string, unknown[]]> } };
}

describe('communications snippets API', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		mockedRequire.mockResolvedValue(context);
		mockedRateLimit.mockResolvedValue({ allowed: true, retryAfterSeconds: 0 });
	});

	it('gates the list on conversations.send, not a separate manage key', async () => {
		await GET(listEvent('', { data: [], error: null }));

		expect(mockedRequire).toHaveBeenCalledWith(expect.anything(), 'conversations.send');
	});

	it('returns the permission check response without reading anything', async () => {
		mockedRequire.mockResolvedValue({ response: new Response(null, { status: 403 }) } as never);
		const target = listEvent('', { data: [], error: null });

		const response = await GET(target);

		expect(response.status).toBe(403);
		expect(target.locals.supabase.from).not.toHaveBeenCalled();
	});

	it('filters to one folder when asked', async () => {
		const target = listEvent('?folder=Follow-ups', { data: [], error: null });

		await GET(target);

		expect(target.__table.__calls).toContainEqual(['eq', ['folder', 'Follow-ups']]);
	});

	it('escapes ilike wildcards and searches title and body together', async () => {
		const target = listEvent('?search=50%25 off_x', { data: [], error: null });

		await GET(target);

		expect(target.__table.__calls).toContainEqual([
			'or',
			['title.ilike.%50\\% off\\_x%,body.ilike.%50\\% off\\_x%']
		]);
	});

	it('pages with a keyset cursor rather than an offset', async () => {
		const rows = Array.from({ length: 51 }, (_, index) =>
			snippet({ id: `snippet-${index}`, title: `Snippet ${index}` })
		);
		const target = listEvent('', { data: rows, error: null });

		const body = await (await GET(target)).json();

		expect(body.items).toHaveLength(50);
		expect(body.next_cursor).toBe('Snippet 49|snippet-49');
		expect(target.__table.__calls).toContainEqual(['limit', [51]]);
		expect(target.__table.__calls.some(([name]) => name === 'range')).toBe(false);
	});

	it('rejects a limit above the page ceiling', async () => {
		const response = await GET(listEvent('?limit=500', { data: [], error: null }));

		expect(response.status).toBe(422);
	});

	it('creates a snippet scoped to the caller organization', async () => {
		const target = createEvent(
			{ title: 'Thanks for reaching out', body: "We'll get back to you shortly." },
			{ data: snippet(), error: null }
		);

		const response = await POST(target);

		expect(response.status).toBe(201);
		const insert = target.__table.__calls.find(([name]) => name === 'insert');
		expect(insert?.[1][0]).toMatchObject({
			organization_id: 'org-1',
			created_by: 'user-1',
			title: 'Thanks for reaching out',
			folder: null
		});
	});

	it('rejects an empty title before ever calling the database', async () => {
		const target = createEvent({ title: '  ', body: 'Body text' }, { data: null, error: null });

		const response = await POST(target);

		expect(response.status).toBe(422);
		expect(target.locals.supabase.from).not.toHaveBeenCalled();
	});

	it('rejects a body that is not valid JSON', async () => {
		const response = await POST(createEvent('not json', { data: null, error: null }));

		expect(response.status).toBe(422);
	});

	it('waits its turn when the organization is saving too often', async () => {
		mockedRateLimit.mockResolvedValue({ allowed: false, retryAfterSeconds: 20 });

		const response = await POST(
			createEvent({ title: 'Thanks', body: 'Body text' }, { data: null, error: null })
		);

		expect(response.status).toBe(429);
	});

	it('turns a row level security refusal into a permission answer', async () => {
		const target = createEvent(
			{ title: 'Thanks', body: 'Body text' },
			{ data: null, error: { code: '42501', message: 'new row violates row-level security' } }
		);

		const response = await POST(target);

		expect(response.status).toBe(403);
		expect((await response.json()).reason).toBe('permission_denied');
	});
});
