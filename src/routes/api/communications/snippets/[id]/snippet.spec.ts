import { beforeEach, describe, expect, it, vi } from 'vitest';
import { DELETE as deleteSnippet, PATCH as updateSnippet } from './+server';
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

function builder(result: unknown) {
	const calls: Array<[string, unknown[]]> = [];
	const chain: Record<string | symbol, unknown> = new Proxy(
		{},
		{
			get(_target, property) {
				if (property === '__calls') return calls;
				if (property === 'maybeSingle') return () => Promise.resolve(result);
				return (...args: unknown[]) => {
					calls.push([String(property), args]);
					return chain;
				};
			}
		}
	);
	return chain;
}

function writeEvent(body: unknown, result: unknown, id = 'snippet-1') {
	const table = builder(result);
	return {
		request: new Request(`http://localhost/api/communications/snippets/${id}`, {
			method: 'PATCH',
			headers: { 'content-type': 'application/json' },
			body: typeof body === 'string' ? body : JSON.stringify(body)
		}),
		params: { id },
		locals: { supabase: { from: vi.fn(() => table) } },
		__table: table
	} as unknown as Parameters<typeof updateSnippet>[0] & {
		__table: { __calls: Array<[string, unknown[]]> };
	};
}

function deleteEvent(result: unknown, id = 'snippet-1') {
	const table = builder(result);
	return {
		params: { id },
		locals: { supabase: { from: vi.fn(() => table) } },
		__table: table
	} as unknown as Parameters<typeof deleteSnippet>[0] & {
		__table: { __calls: Array<[string, unknown[]]> };
	};
}

const saved = {
	id: 'snippet-1',
	folder: null,
	title: 'Thanks for reaching out',
	body: "We'll get back to you shortly.",
	created_at: '2026-08-27T00:00:00Z',
	updated_at: '2026-08-27T00:00:00Z'
};

beforeEach(() => {
	vi.clearAllMocks();
	mockedRequire.mockResolvedValue(context);
	mockedRateLimit.mockResolvedValue({ allowed: true, retryAfterSeconds: 0 });
});

describe('editing a snippet', () => {
	it('sends only the fields that changed, leaving folder untouched when omitted', async () => {
		const event = writeEvent({ title: 'Updated title' }, { data: saved, error: null });

		await updateSnippet(event);

		const update = event.__table.__calls.find(([name]) => name === 'update');
		expect(update?.[1][0]).toEqual({ title: 'Updated title' });
	});

	it('clears the folder on an explicit null, distinct from leaving it out', async () => {
		const event = writeEvent({ folder: null }, { data: saved, error: null });

		await updateSnippet(event);

		const update = event.__table.__calls.find(([name]) => name === 'update');
		expect(update?.[1][0]).toEqual({ folder: null });
	});

	it('rejects a body with nothing to change', async () => {
		const response = await updateSnippet(writeEvent({}, { data: null, error: null }));

		expect(response.status).toBe(422);
	});

	it('answers not found when the row is missing or belongs to another organization', async () => {
		const response = await updateSnippet(writeEvent({ title: 'x' }, { data: null, error: null }));

		expect(response.status).toBe(404);
	});

	it('refuses without conversations.send', async () => {
		mockedRequire.mockResolvedValue({ response: new Response(null, { status: 403 }) } as never);

		const response = await updateSnippet(writeEvent({ title: 'x' }, { data: saved, error: null }));

		expect(response.status).toBe(403);
	});

	it('waits its turn when the organization is saving too often', async () => {
		mockedRateLimit.mockResolvedValue({ allowed: false, retryAfterSeconds: 20 });

		const response = await updateSnippet(writeEvent({ title: 'x' }, { data: saved, error: null }));

		expect(response.status).toBe(429);
	});
});

describe('deleting a snippet', () => {
	it('deletes permanently rather than archiving', async () => {
		const event = deleteEvent({ data: { id: 'snippet-1' }, error: null });

		const response = await deleteSnippet(event);
		const body = await response.json();

		expect(body).toEqual({ status: 'deleted', id: 'snippet-1' });
		expect(event.__table.__calls.some(([name]) => name === 'delete')).toBe(true);
	});

	it('answers not found when the row is missing or belongs to another organization', async () => {
		const response = await deleteSnippet(deleteEvent({ data: null, error: null }));

		expect(response.status).toBe(404);
	});

	it('refuses without conversations.send', async () => {
		mockedRequire.mockResolvedValue({ response: new Response(null, { status: 403 }) } as never);

		const response = await deleteSnippet(deleteEvent({ data: { id: 'snippet-1' }, error: null }));

		expect(response.status).toBe(403);
	});
});
