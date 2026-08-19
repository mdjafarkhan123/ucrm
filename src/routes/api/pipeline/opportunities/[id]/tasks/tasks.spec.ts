import { beforeEach, describe, expect, it, vi } from 'vitest';
import { GET, POST } from './+server';
import { requireOrganizationPermission } from '$lib/server/access/permission';

vi.mock('$lib/server/access/permission', () => ({
	requireOrganizationPermission: vi.fn()
}));

const mockedRequire = vi.mocked(requireOrganizationPermission);
const opportunityId = '00000000-0000-4000-8000-000000000031';
const organizationId = '00000000-0000-4000-8000-0000000000aa';

const context = {
	auth: { user: { id: 'user-1' }, organization: { id: organizationId } },
	access: {}
} as never;

function taskRow(overrides: Record<string, unknown> = {}) {
	return {
		id: '00000000-0000-4000-8000-000000000001',
		opportunity_id: opportunityId,
		title: 'Call Colin',
		instructions: null,
		assignee_user_id: null,
		due_on: '2026-09-05',
		status: 'open',
		completed_at: null,
		completed_by: null,
		created_at: '2026-08-19T00:00:00Z',
		...overrides
	};
}

// A stand-in for the query builder: every filter returns itself, and the promise resolves with whatever
// this group was told to answer.
function selectBuilder(result: { data: unknown; error: unknown }) {
	const builder: Record<string, unknown> = {};
	for (const method of ['select', 'eq', 'order', 'limit']) {
		builder[method] = vi.fn(() => builder);
	}
	builder.then = (resolve: (value: unknown) => unknown) => Promise.resolve(result).then(resolve);
	return builder;
}

function readEvent(open: unknown[], completed: unknown[]) {
	const builders = [
		selectBuilder({ data: open, error: null }),
		selectBuilder({ data: completed, error: null })
	];
	const from = vi.fn(() => builders.shift());
	return {
		params: { id: opportunityId },
		url: new URL(`http://localhost/api/pipeline/opportunities/${opportunityId}/tasks`),
		locals: { supabase: { from } },
		request: new Request(`http://localhost/api/pipeline/opportunities/${opportunityId}/tasks`)
	} as unknown as Parameters<typeof GET>[0];
}

function writeEvent(body: unknown, rpc = vi.fn()) {
	return {
		params: { id: opportunityId },
		request: new Request(`http://localhost/api/pipeline/opportunities/${opportunityId}/tasks`, {
			method: 'POST',
			headers: { 'content-type': 'application/json' },
			body: typeof body === 'string' ? body : JSON.stringify(body)
		}),
		locals: { supabase: { rpc } }
	} as unknown as Parameters<typeof POST>[0];
}

describe('opportunity tasks list', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		mockedRequire.mockResolvedValue(context);
	});

	it('answers with the two groups the Brief shows', async () => {
		const response = await GET(
			readEvent([taskRow()], [taskRow({ id: 'done-1', status: 'completed', completed_at: 'x' })])
		);

		expect(response.status).toBe(200);
		const body = await response.json();
		expect(body.open).toHaveLength(1);
		expect(body.completed).toHaveLength(1);
		expect(body.open[0].title).toBe('Call Colin');
	});

	it('reads with pipeline.view, not pipeline.edit', async () => {
		await GET(readEvent([], []));
		expect(mockedRequire).toHaveBeenCalledWith(expect.anything(), 'pipeline.view');
	});

	it('returns the permission check response without touching the database', async () => {
		mockedRequire.mockResolvedValue({ response: new Response(null, { status: 403 }) } as never);
		const event = readEvent([], []);

		const response = await GET(event);

		expect(response.status).toBe(403);
		expect(event.locals.supabase.from).not.toHaveBeenCalled();
	});

	it('keeps the answer out of any shared cache', async () => {
		const response = await GET(readEvent([], []));
		expect(response.headers.get('cache-control')).toBe('private, no-cache');
	});
});

describe('opportunity task create', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		mockedRequire.mockResolvedValue(context);
	});

	it('needs pipeline.edit', async () => {
		mockedRequire.mockResolvedValue({ response: new Response(null, { status: 403 }) } as never);
		const rpc = vi.fn();

		const response = await POST(writeEvent({ title: 'Call Colin' }, rpc));

		expect(response.status).toBe(403);
		expect(mockedRequire).toHaveBeenCalledWith(expect.anything(), 'pipeline.edit');
		expect(rpc).not.toHaveBeenCalled();
	});

	it('rejects a task with no title before querying the database', async () => {
		const rpc = vi.fn();
		const response = await POST(writeEvent({ instructions: 'no title here' }, rpc));

		expect(response.status).toBe(422);
		expect((await response.json()).field_errors.title).toBeDefined();
		expect(rpc).not.toHaveBeenCalled();
	});

	it('rejects a body that is not valid JSON', async () => {
		const rpc = vi.fn();
		const response = await POST(writeEvent('not json', rpc));

		expect(response.status).toBe(422);
		expect(rpc).not.toHaveBeenCalled();
	});

	it('sends all four fields to the one write path and answers 201', async () => {
		const rpc = vi.fn().mockResolvedValue({ data: [taskRow()], error: null });

		const response = await POST(
			writeEvent(
				{
					title: 'Call Colin',
					instructions: '  ',
					assignee_user_id: null,
					due_on: '2026-09-05'
				},
				rpc
			)
		);

		expect(rpc).toHaveBeenCalledWith('pipeline_create_opportunity_task', {
			target_opportunity_id: opportunityId,
			new_title: 'Call Colin',
			new_instructions: null,
			new_assignee_user_id: null,
			new_due_on: '2026-09-05'
		});
		expect(response.status).toBe(201);
		expect((await response.json()).id).toBe('00000000-0000-4000-8000-000000000001');
	});

	it('passes the five-task limit through as something a person can act on', async () => {
		const rpc = vi.fn().mockResolvedValue({
			data: null,
			error: {
				code: '54000',
				message: 'This opportunity already has five open tasks. Finish one first.'
			}
		});

		const response = await POST(writeEvent({ title: 'One too many' }, rpc));

		expect(response.status).toBe(422);
		expect((await response.json()).field_errors.form).toContain('five open tasks');
	});

	it('turns an invalid assignee into a field error', async () => {
		const rpc = vi.fn().mockResolvedValue({
			data: null,
			error: { code: '23514', message: 'That person cannot be given work on the sales pipeline.' }
		});

		const response = await POST(
			writeEvent(
				{ title: 'Call Colin', assignee_user_id: '00000000-0000-4000-8000-000000000009' },
				rpc
			)
		);

		expect(response.status).toBe(422);
		expect((await response.json()).field_errors.assignee_user_id).toContain('sales pipeline');
	});

	it('turns a refusal from the write function into a plain not-found', async () => {
		const rpc = vi.fn().mockResolvedValue({
			data: null,
			error: { code: '42501', message: 'insufficient_privilege' }
		});

		const response = await POST(writeEvent({ title: 'Not yours' }, rpc));

		expect(response.status).toBe(404);
	});

	it('turns any other database error into a generic failure', async () => {
		const rpc = vi.fn().mockResolvedValue({
			data: null,
			error: { code: '08000', message: 'connection failure' }
		});

		const response = await POST(writeEvent({ title: 'Call Colin' }, rpc));

		expect(response.status).toBe(500);
	});

	it('returns not-found when the function answers with no row', async () => {
		const rpc = vi.fn().mockResolvedValue({ data: [], error: null });

		const response = await POST(writeEvent({ title: 'Call Colin' }, rpc));

		expect(response.status).toBe(404);
	});
});
