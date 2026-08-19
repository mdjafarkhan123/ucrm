import { beforeEach, describe, expect, it, vi } from 'vitest';
import { DELETE, PATCH } from './+server';
import { PATCH as PATCH_COMPLETION } from './completion/+server';
import { requireOrganizationPermission } from '$lib/server/access/permission';

vi.mock('$lib/server/access/permission', () => ({
	requireOrganizationPermission: vi.fn()
}));

const mockedRequire = vi.mocked(requireOrganizationPermission);
const taskId = '00000000-0000-4000-8000-000000000001';
const opportunityId = '00000000-0000-4000-8000-000000000031';

const context = {
	auth: { user: { id: 'user-1' }, organization: { id: 'org-1' } },
	access: {}
} as never;

function taskRow(overrides: Record<string, unknown> = {}) {
	return {
		id: taskId,
		opportunity_id: opportunityId,
		title: 'Call Colin',
		instructions: null,
		assignee_user_id: null,
		due_on: null,
		status: 'open',
		completed_at: null,
		completed_by: null,
		created_at: '2026-08-19T00:00:00Z',
		...overrides
	};
}

function event(method: string, path: string, body: unknown, rpc = vi.fn()) {
	return {
		params: { taskId },
		request: new Request(`http://localhost/api/pipeline/tasks/${taskId}${path}`, {
			method,
			...(body === undefined
				? {}
				: {
						headers: { 'content-type': 'application/json' },
						body: typeof body === 'string' ? body : JSON.stringify(body)
					})
		}),
		locals: { supabase: { rpc } }
	} as unknown as Parameters<typeof PATCH>[0];
}

// The completion handler belongs to its own route, so its event carries that route's id.
function completionEvent(body: unknown, rpc = vi.fn()) {
	return event('PATCH', '/completion', body, rpc) as unknown as Parameters<
		typeof PATCH_COMPLETION
	>[0];
}

describe('task edit', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		mockedRequire.mockResolvedValue(context);
	});

	it('needs pipeline.edit', async () => {
		mockedRequire.mockResolvedValue({ response: new Response(null, { status: 403 }) } as never);
		const rpc = vi.fn();

		const response = await PATCH(event('PATCH', '', { title: 'Call Colin' }, rpc));

		expect(response.status).toBe(403);
		expect(mockedRequire).toHaveBeenCalledWith(expect.anything(), 'pipeline.edit');
		expect(rpc).not.toHaveBeenCalled();
	});

	it('replaces all four fields, clearing the ones left out', async () => {
		const rpc = vi
			.fn()
			.mockResolvedValue({ data: [taskRow({ title: 'Call Colin back' })], error: null });

		const response = await PATCH(event('PATCH', '', { title: 'Call Colin back' }, rpc));

		expect(rpc).toHaveBeenCalledWith('pipeline_update_opportunity_task', {
			target_task_id: taskId,
			new_title: 'Call Colin back',
			new_instructions: null,
			new_assignee_user_id: null,
			new_due_on: null
		});
		expect(response.status).toBe(200);
		expect((await response.json()).title).toBe('Call Colin back');
	});

	it('rejects an empty title before querying the database', async () => {
		const rpc = vi.fn();
		const response = await PATCH(event('PATCH', '', { title: '' }, rpc));

		expect(response.status).toBe(422);
		expect(rpc).not.toHaveBeenCalled();
	});

	it('answers a refusal with a plain not-found', async () => {
		const rpc = vi
			.fn()
			.mockResolvedValue({ data: null, error: { code: '42501', message: 'nope' } });

		const response = await PATCH(event('PATCH', '', { title: 'Not yours' }, rpc));

		expect(response.status).toBe(404);
	});

	it('never stores a mutation response', async () => {
		const rpc = vi.fn().mockResolvedValue({ data: [taskRow()], error: null });
		const response = await PATCH(event('PATCH', '', { title: 'Call Colin' }, rpc));
		expect(response.headers.get('cache-control')).toBe('no-store');
	});
});

describe('task delete', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		mockedRequire.mockResolvedValue(context);
	});

	it('needs pipeline.edit', async () => {
		mockedRequire.mockResolvedValue({ response: new Response(null, { status: 403 }) } as never);
		const rpc = vi.fn();

		const response = await DELETE(event('DELETE', '', undefined, rpc));

		expect(response.status).toBe(403);
		expect(rpc).not.toHaveBeenCalled();
	});

	it('answers with the task and the card it came off', async () => {
		const rpc = vi
			.fn()
			.mockResolvedValue({ data: [{ id: taskId, opportunity_id: opportunityId }], error: null });

		const response = await DELETE(event('DELETE', '', undefined, rpc));

		expect(rpc).toHaveBeenCalledWith('pipeline_delete_task', { target_task_id: taskId });
		expect(response.status).toBe(200);
		expect(await response.json()).toEqual({ id: taskId, opportunity_id: opportunityId });
	});

	it('answers not-found when nothing was deleted', async () => {
		const rpc = vi.fn().mockResolvedValue({ data: [], error: null });

		const response = await DELETE(event('DELETE', '', undefined, rpc));

		expect(response.status).toBe(404);
	});
});

describe('task completion', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		mockedRequire.mockResolvedValue(context);
	});

	it('completes and reopens through the same call', async () => {
		const rpc = vi.fn().mockResolvedValue({
			data: [taskRow({ status: 'completed', completed_at: 'now' })],
			error: null
		});

		const done = await PATCH_COMPLETION(completionEvent({ completed: true }, rpc));
		expect(rpc).toHaveBeenCalledWith('pipeline_set_task_completed', {
			target_task_id: taskId,
			is_completed: true
		});
		expect((await done.json()).status).toBe('completed');

		rpc.mockResolvedValue({ data: [taskRow()], error: null });
		const reopened = await PATCH_COMPLETION(completionEvent({ completed: false }, rpc));
		expect((await reopened.json()).status).toBe('open');
	});

	it('rejects anything that is not a plain true or false', async () => {
		const rpc = vi.fn();
		const response = await PATCH_COMPLETION(completionEvent({ completed: 'yes' }, rpc));

		expect(response.status).toBe(422);
		expect(rpc).not.toHaveBeenCalled();
	});

	it('passes the completed-task limit through as a message', async () => {
		const rpc = vi.fn().mockResolvedValue({
			data: null,
			error: {
				code: '54000',
				message: 'This opportunity already has five completed tasks. Delete one first.'
			}
		});

		const response = await PATCH_COMPLETION(completionEvent({ completed: true }, rpc));

		expect(response.status).toBe(422);
		expect((await response.json()).field_errors.form).toContain('five completed tasks');
	});

	it('needs pipeline.edit even though completing is not really an edit', async () => {
		mockedRequire.mockResolvedValue({ response: new Response(null, { status: 403 }) } as never);
		const rpc = vi.fn();

		const response = await PATCH_COMPLETION(completionEvent({ completed: true }, rpc));

		expect(response.status).toBe(403);
		expect(mockedRequire).toHaveBeenCalledWith(expect.anything(), 'pipeline.edit');
		expect(rpc).not.toHaveBeenCalled();
	});
});
