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

function noteRow(overrides: Record<string, unknown> = {}) {
	return {
		id: '00000000-0000-4000-8000-000000000001',
		body: 'Called the client back',
		pinned: false,
		created_by: 'user-1',
		edited_by: null,
		edited_at: null,
		created_at: '2026-08-19T00:00:00Z',
		updated_at: '2026-08-19T00:00:00Z',
		entity_type: 'request',
		entity_id: '00000000-0000-4000-8000-000000000041',
		...overrides
	};
}

function readEvent(rpc = vi.fn()) {
	return {
		params: { id: opportunityId },
		locals: { supabase: { rpc } },
		request: new Request(`http://localhost/api/pipeline/opportunities/${opportunityId}/notes`)
	} as unknown as Parameters<typeof GET>[0];
}

function writeEvent(body: unknown, rpc = vi.fn()) {
	return {
		params: { id: opportunityId },
		request: new Request(`http://localhost/api/pipeline/opportunities/${opportunityId}/notes`, {
			method: 'POST',
			headers: { 'content-type': 'application/json' },
			body: typeof body === 'string' ? body : JSON.stringify(body)
		}),
		locals: { supabase: { rpc } }
	} as unknown as Parameters<typeof POST>[0];
}

describe('opportunity notes list', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		mockedRequire.mockResolvedValue(context);
	});

	it('reads with pipeline.view, not pipeline.edit', async () => {
		const rpc = vi.fn().mockResolvedValue({ data: [], error: null });
		await GET(readEvent(rpc));
		expect(mockedRequire).toHaveBeenCalledWith(expect.anything(), 'pipeline.view');
	});

	it('answers with the pooled Request/Client notes the RPC returns', async () => {
		const rpc = vi.fn().mockResolvedValue({
			data: [noteRow(), noteRow({ id: 'note-2', entity_type: 'client' })],
			error: null
		});

		const response = await GET(readEvent(rpc));

		expect(response.status).toBe(200);
		const body = await response.json();
		expect(body.notes).toHaveLength(2);
		expect(rpc).toHaveBeenCalledWith('pipeline_opportunity_notes', {
			target_opportunity_id: opportunityId
		});
	});

	it('returns the permission check response without calling the database', async () => {
		mockedRequire.mockResolvedValue({ response: new Response(null, { status: 403 }) } as never);
		const rpc = vi.fn();

		const response = await GET(readEvent(rpc));

		expect(response.status).toBe(403);
		expect(rpc).not.toHaveBeenCalled();
	});

	it('keeps the answer out of any shared cache', async () => {
		const rpc = vi.fn().mockResolvedValue({ data: [], error: null });
		const response = await GET(readEvent(rpc));
		expect(response.headers.get('cache-control')).toBe('private, no-cache');
	});
});

describe('opportunity note create', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		mockedRequire.mockResolvedValue(context);
	});

	it('needs pipeline.edit', async () => {
		mockedRequire.mockResolvedValue({ response: new Response(null, { status: 403 }) } as never);
		const rpc = vi.fn();

		const response = await POST(writeEvent({ entity_type: 'request', body: 'x' }, rpc));

		expect(response.status).toBe(403);
		expect(mockedRequire).toHaveBeenCalledWith(expect.anything(), 'pipeline.edit');
		expect(rpc).not.toHaveBeenCalled();
	});

	it('rejects a Property target before querying the database', async () => {
		const rpc = vi.fn();
		const response = await POST(writeEvent({ entity_type: 'property', body: 'x' }, rpc));

		expect(response.status).toBe(422);
		expect(rpc).not.toHaveBeenCalled();
	});

	it('rejects an empty body before querying the database', async () => {
		const rpc = vi.fn();
		const response = await POST(writeEvent({ entity_type: 'request', body: '   ' }, rpc));

		expect(response.status).toBe(422);
		expect(rpc).not.toHaveBeenCalled();
	});

	it('sends the entity_type and body to the write function and answers 201', async () => {
		const rpc = vi
			.fn()
			.mockResolvedValue({ data: [noteRow({ entity_type: 'client' })], error: null });

		const response = await POST(
			writeEvent({ entity_type: 'client', body: 'Client-targeted note' }, rpc)
		);

		expect(rpc).toHaveBeenCalledWith('pipeline_create_opportunity_note', {
			target_opportunity_id: opportunityId,
			target_entity_type: 'client',
			new_body: 'Client-targeted note'
		});
		expect(response.status).toBe(201);
		const created = (await response.json()).note;
		expect(created.entity_type).toBe('client');
	});

	it('this route is the only door a pipeline.edit-only member needs for a Client-targeted note: it never checks customers.edit', async () => {
		// The permission gate is the single call above -- pipeline.edit -- and nothing else. A member who
		// has pipeline.edit but not customers.edit reaches this exact same code path.
		const rpc = vi
			.fn()
			.mockResolvedValue({ data: [noteRow({ entity_type: 'client' })], error: null });

		await POST(writeEvent({ entity_type: 'client', body: 'x' }, rpc));

		expect(mockedRequire).toHaveBeenCalledTimes(1);
		expect(mockedRequire).toHaveBeenCalledWith(expect.anything(), 'pipeline.edit');
	});

	it('turns a refusal from the write function into a plain not-found', async () => {
		const rpc = vi.fn().mockResolvedValue({
			data: null,
			error: { code: '42501', message: 'insufficient_privilege' }
		});

		const response = await POST(writeEvent({ entity_type: 'request', body: 'x' }, rpc));

		expect(response.status).toBe(404);
	});

	it('turns the entity-type guard from the function into a field error', async () => {
		const rpc = vi.fn().mockResolvedValue({
			data: null,
			error: { code: '23514', message: 'A Brief Note can only target the Request or the Client.' }
		});

		const response = await POST(writeEvent({ entity_type: 'request', body: 'x' }, rpc));

		expect(response.status).toBe(422);
		expect((await response.json()).field_errors.entity_type).toContain('Request or the Client');
	});

	it('turns any other database error into a generic failure', async () => {
		const rpc = vi.fn().mockResolvedValue({ data: null, error: { code: '08000' } });
		const response = await POST(writeEvent({ entity_type: 'request', body: 'x' }, rpc));
		expect(response.status).toBe(500);
	});
});
