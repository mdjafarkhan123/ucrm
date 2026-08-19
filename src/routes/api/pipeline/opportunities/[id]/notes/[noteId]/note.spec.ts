import { beforeEach, describe, expect, it, vi } from 'vitest';
import { PATCH, DELETE } from './+server';
import { requireOrganizationPermission } from '$lib/server/access/permission';

vi.mock('$lib/server/access/permission', () => ({
	requireOrganizationPermission: vi.fn()
}));

const mockedRequire = vi.mocked(requireOrganizationPermission);
const opportunityId = '00000000-0000-4000-8000-000000000031';
const noteId = '00000000-0000-4000-8000-000000000001';
const organizationId = '00000000-0000-4000-8000-0000000000aa';

const context = {
	auth: { user: { id: 'user-1' }, organization: { id: organizationId } },
	access: {}
} as never;

function noteRow(overrides: Record<string, unknown> = {}) {
	return {
		id: noteId,
		body: 'Edited body',
		pinned: false,
		created_by: 'user-1',
		edited_by: 'user-1',
		edited_at: '2026-08-19T01:00:00Z',
		created_at: '2026-08-19T00:00:00Z',
		updated_at: '2026-08-19T01:00:00Z',
		entity_type: 'client',
		entity_id: '00000000-0000-4000-8000-000000000042',
		...overrides
	};
}

function patchEvent(body: unknown, rpc = vi.fn()) {
	return {
		params: { id: opportunityId, noteId },
		request: new Request(
			`http://localhost/api/pipeline/opportunities/${opportunityId}/notes/${noteId}`,
			{
				method: 'PATCH',
				headers: { 'content-type': 'application/json' },
				body: typeof body === 'string' ? body : JSON.stringify(body)
			}
		),
		locals: { supabase: { rpc } }
	} as unknown as Parameters<typeof PATCH>[0];
}

function deleteEvent(body: unknown, rpc = vi.fn()) {
	return {
		params: { id: opportunityId, noteId },
		request: new Request(
			`http://localhost/api/pipeline/opportunities/${opportunityId}/notes/${noteId}`,
			{
				method: 'DELETE',
				headers: { 'content-type': 'application/json' },
				body: typeof body === 'string' ? body : JSON.stringify(body)
			}
		),
		locals: { supabase: { rpc } }
	} as unknown as Parameters<typeof DELETE>[0];
}

describe('opportunity note update', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		mockedRequire.mockResolvedValue(context);
	});

	it('needs pipeline.edit', async () => {
		mockedRequire.mockResolvedValue({ response: new Response(null, { status: 403 }) } as never);
		const rpc = vi.fn();

		const response = await PATCH(patchEvent({ body: 'x' }, rpc));

		expect(response.status).toBe(403);
		expect(rpc).not.toHaveBeenCalled();
	});

	it('rejects an empty body before querying the database', async () => {
		const rpc = vi.fn();
		const response = await PATCH(patchEvent({ body: '  ' }, rpc));

		expect(response.status).toBe(422);
		expect(rpc).not.toHaveBeenCalled();
	});

	it('sends the opportunity id, note id, and new body to the write function', async () => {
		const rpc = vi.fn().mockResolvedValue({ data: [noteRow()], error: null });

		const response = await PATCH(patchEvent({ body: 'Edited body' }, rpc));

		expect(rpc).toHaveBeenCalledWith('pipeline_update_opportunity_note', {
			target_note_id: noteId,
			target_opportunity_id: opportunityId,
			new_body: 'Edited body'
		});
		expect(response.status).toBe(200);
	});

	it('refuses a note that does not belong to this opportunity as a plain not-found', async () => {
		const rpc = vi.fn().mockResolvedValue({
			data: null,
			error: { code: '42501', message: 'insufficient_privilege' }
		});

		const response = await PATCH(patchEvent({ body: 'hijack attempt' }, rpc));

		expect(response.status).toBe(404);
	});
});

describe('opportunity note delete', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		mockedRequire.mockResolvedValue(context);
	});

	it('needs pipeline.edit', async () => {
		mockedRequire.mockResolvedValue({ response: new Response(null, { status: 403 }) } as never);
		const rpc = vi.fn();

		const response = await DELETE(deleteEvent({ entity_type: 'client' }, rpc));

		expect(response.status).toBe(403);
		expect(rpc).not.toHaveBeenCalled();
	});

	it('rejects a missing entity_type before querying the database', async () => {
		const rpc = vi.fn();
		const response = await DELETE(deleteEvent({}, rpc));

		expect(response.status).toBe(422);
		expect(rpc).not.toHaveBeenCalled();
	});

	it('sends the opportunity id, note id, and target to the write function', async () => {
		const rpc = vi
			.fn()
			.mockResolvedValue({ data: [{ unlinked: true, note_deleted: true }], error: null });

		const response = await DELETE(deleteEvent({ entity_type: 'client' }, rpc));

		expect(rpc).toHaveBeenCalledWith('pipeline_delete_opportunity_note', {
			target_note_id: noteId,
			target_opportunity_id: opportunityId,
			target_entity_type: 'client'
		});
		expect(response.status).toBe(200);
		expect(await response.json()).toEqual({ unlinked: true, note_deleted: true });
	});

	it('refuses a note that does not belong to this opportunity as a plain not-found', async () => {
		const rpc = vi.fn().mockResolvedValue({
			data: null,
			error: { code: '42501', message: 'insufficient_privilege' }
		});

		const response = await DELETE(deleteEvent({ entity_type: 'client' }, rpc));

		expect(response.status).toBe(404);
	});
});
