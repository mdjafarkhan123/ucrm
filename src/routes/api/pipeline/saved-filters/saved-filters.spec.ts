import { beforeEach, describe, expect, it, vi } from 'vitest';
import { GET, POST } from './+server';
import { PATCH, DELETE } from './[id=uuid]/+server';
import { requireOrganizationPermission } from '$lib/server/access/permission';

vi.mock('$lib/server/access/permission', () => ({ requireOrganizationPermission: vi.fn() }));

const organizationId = '00000000-0000-4000-8000-0000000000aa';
const userId = '00000000-0000-4000-8000-0000000000bb';
const filterId = '00000000-0000-4000-8000-0000000000cc';

// A stand-in for the Supabase table builder: every chained call returns itself, and awaiting it — or
// calling `single()` — gives back `result`. Records what was inserted or updated.
function tableStub(result: { data: unknown; error: unknown }) {
	const calls: Record<string, unknown[]> = {};
	const builder: Record<string, unknown> = {};
	for (const name of ['select', 'eq', 'order', 'insert', 'update', 'delete']) {
		builder[name] = vi.fn((...args: unknown[]) => {
			calls[name] = args;
			return builder;
		});
	}
	builder.single = vi.fn(() => Promise.resolve(result));
	builder.then = (resolve: (value: unknown) => unknown) => Promise.resolve(result).then(resolve);
	return { from: vi.fn(() => builder), calls };
}

function event(
	supabase: ReturnType<typeof tableStub>,
	options: { method?: string; body?: unknown; id?: string } = {}
) {
	return {
		url: new URL('http://localhost/api/pipeline/saved-filters'),
		params: { id: options.id ?? filterId },
		request: new Request('http://localhost/api/pipeline/saved-filters', {
			method: options.method ?? 'GET',
			...(options.body !== undefined ? { body: JSON.stringify(options.body) } : {})
		}),
		locals: { supabase }
	} as never;
}

function signedInAs(role: string) {
	vi.mocked(requireOrganizationPermission).mockResolvedValue({
		auth: { organization: { id: organizationId, role }, user: { id: userId } }
	} as never);
}

describe('listing saved filters', () => {
	beforeEach(() => signedInAs('sales'));

	it('labels shared filters as the team’s, changeable only by an administrator', async () => {
		const supabase = tableStub({
			data: [
				{ id: 'a', name: 'Mine', query: 'source=Google', user_id: userId },
				{ id: 'b', name: 'Team', query: 'owner=unassigned', user_id: null }
			],
			error: null
		});
		const body = await (await GET(event(supabase))).json();
		expect(body.can_share).toBe(false);
		expect(body.filters).toEqual([
			{ id: 'a', name: 'Mine', query: 'source=Google', shared: false, can_edit: true },
			{ id: 'b', name: 'Team', query: 'owner=unassigned', shared: true, can_edit: false }
		]);
		expect(supabase.calls.eq).toEqual(['organization_id', organizationId]);
	});

	it('lets an administrator change the shared ones', async () => {
		signedInAs('admin');
		const supabase = tableStub({
			data: [{ id: 'b', name: 'Team', query: 'owner=unassigned', user_id: null }],
			error: null
		});
		const body = await (await GET(event(supabase))).json();
		expect(body.can_share).toBe(true);
		expect(body.filters[0].can_edit).toBe(true);
	});
});

describe('saving a filter', () => {
	beforeEach(() => signedInAs('sales'));

	it('saves the controls as the board’s address, for the caller alone, without the search box', async () => {
		const supabase = tableStub({
			data: { id: filterId, name: 'Google leads', query: 'source=Google', user_id: userId },
			error: null
		});
		const response = await POST(
			event(supabase, {
				method: 'POST',
				body: { name: '  Google   leads ', filters: { source: 'Google', q: 'Ada' } }
			})
		);
		expect(response.status).toBe(201);
		expect(supabase.calls.insert).toEqual([
			{
				organization_id: organizationId,
				user_id: userId,
				name: 'Google leads',
				query: 'source=Google'
			}
		]);
	});

	it('refuses to share for someone who is not an owner or administrator', async () => {
		const supabase = tableStub({ data: null, error: null });
		const response = await POST(
			event(supabase, {
				method: 'POST',
				body: { name: 'Team', shared: true, filters: { source: 'Google' } }
			})
		);
		expect(response.status).toBe(403);
		expect(supabase.from).not.toHaveBeenCalled();
	});

	it('saves a shared filter with no owner when an administrator asks', async () => {
		signedInAs('owner');
		const supabase = tableStub({
			data: { id: filterId, name: 'Team', query: 'source=Google', user_id: null },
			error: null
		});
		const response = await POST(
			event(supabase, {
				method: 'POST',
				body: { name: 'Team', shared: true, filters: { source: 'Google' } }
			})
		);
		expect(response.status).toBe(201);
		expect((supabase.calls.insert[0] as { user_id: unknown }).user_id).toBeNull();
	});

	it('refuses an untouched board, which has nothing to remember', async () => {
		const supabase = tableStub({ data: null, error: null });
		const response = await POST(
			event(supabase, { method: 'POST', body: { name: 'Nothing', filters: {} } })
		);
		expect(response.status).toBe(422);
		expect(supabase.from).not.toHaveBeenCalled();
	});

	it('names a duplicate as the name’s problem', async () => {
		const supabase = tableStub({ data: null, error: { code: '23505', message: 'duplicate' } });
		const response = await POST(
			event(supabase, { method: 'POST', body: { name: 'Mine', filters: { source: 'Google' } } })
		);
		expect(response.status).toBe(409);
		expect((await response.json()).field_errors.name).toMatch(/already have/);
	});
});

describe('changing and deleting a filter', () => {
	beforeEach(() => signedInAs('sales'));

	it('reads a filter the caller may not reach as not found', async () => {
		const supabase = tableStub({ data: [], error: null });
		const response = await PATCH(
			event(supabase, { method: 'PATCH', body: { name: 'Taken over' } })
		);
		expect(response.status).toBe(404);
	});

	it('updates what a filter shows from the board’s current controls', async () => {
		const supabase = tableStub({
			data: [{ id: filterId, name: 'Mine', query: 'sort=value', user_id: userId }],
			error: null
		});
		const response = await PATCH(
			event(supabase, { method: 'PATCH', body: { filters: { sort: 'value' } } })
		);
		expect(response.status).toBe(200);
		expect(supabase.calls.update).toEqual([{ query: 'sort=value' }]);
	});

	it('deletes, and reports a filter that was not there', async () => {
		expect(
			(
				await DELETE(
					event(tableStub({ data: [{ id: filterId }], error: null }), { method: 'DELETE' })
				)
			).status
		).toBe(204);
		expect(
			(await DELETE(event(tableStub({ data: [], error: null }), { method: 'DELETE' }))).status
		).toBe(404);
	});
});
