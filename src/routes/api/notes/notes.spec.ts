import { beforeEach, describe, expect, it, vi } from 'vitest';
import { POST } from './+server';
import {
	requireLinkedEntityAccess,
	linkedEntityBelongsToOrganization
} from '$lib/server/access/collaboration';

vi.mock('$lib/server/access/collaboration', async () => {
	const actual = await vi.importActual<typeof import('$lib/server/access/collaboration')>(
		'$lib/server/access/collaboration'
	);
	return {
		...actual,
		requireLinkedEntityAccess: vi.fn(),
		linkedEntityBelongsToOrganization: vi.fn()
	};
});

const mockedRequire = vi.mocked(requireLinkedEntityAccess);
const mockedBelongs = vi.mocked(linkedEntityBelongsToOrganization);
const organizationId = '00000000-0000-4000-8000-0000000000aa';
const entityId = '00000000-0000-4000-8000-000000000041';

const context = {
	auth: { user: { id: 'user-1' }, organization: { id: organizationId } }
} as never;

function noteWithLinkRow(overrides: Record<string, unknown> = {}) {
	return {
		id: '00000000-0000-4000-8000-000000000001',
		organization_id: organizationId,
		body: 'A note',
		pinned: false,
		created_by: 'user-1',
		edited_by: null,
		edited_at: null,
		created_at: '2026-08-19T00:00:00Z',
		updated_at: '2026-08-19T00:00:00Z',
		link_id: '00000000-0000-4000-8000-000000000051',
		entity_type: 'request',
		entity_id: entityId,
		link_created_at: '2026-08-19T00:00:00Z',
		...overrides
	};
}

function postEvent(body: unknown, rpc = vi.fn()) {
	return {
		request: new Request('http://localhost/api/notes', {
			method: 'POST',
			headers: { 'content-type': 'application/json' },
			body: typeof body === 'string' ? body : JSON.stringify(body)
		}),
		locals: { supabase: { rpc } }
	} as unknown as Parameters<typeof POST>[0];
}

describe('note create', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		mockedRequire.mockResolvedValue(context);
		mockedBelongs.mockResolvedValue(true);
	});

	it('writes the note and its link in one call, not two sequential inserts', async () => {
		const rpc = vi.fn().mockResolvedValue({ data: [noteWithLinkRow()], error: null });

		const response = await POST(
			postEvent({ entity_type: 'request', entity_id: entityId, body: 'A note' }, rpc)
		);

		expect(rpc).toHaveBeenCalledWith('create_note', {
			target_organization_id: organizationId,
			target_entity_type: 'request',
			target_entity_id: entityId,
			new_body: 'A note',
			new_pinned: false
		});
		expect(response.status).toBe(201);
		const body = await response.json();
		expect(body.note.links).toHaveLength(1);
		expect(body.note.links[0].entity_type).toBe('request');
	});

	it('answers 500 without a partially-created note when the RPC fails', async () => {
		const rpc = vi.fn().mockResolvedValue({ data: null, error: { code: '42501' } });

		const response = await POST(
			postEvent({ entity_type: 'request', entity_id: entityId, body: 'A note' }, rpc)
		);

		expect(response.status).toBe(500);
		expect(rpc).toHaveBeenCalledTimes(1);
	});

	it('never reaches the database for an entity outside the organization', async () => {
		mockedBelongs.mockResolvedValue(false);
		const rpc = vi.fn();

		const response = await POST(
			postEvent({ entity_type: 'request', entity_id: entityId, body: 'A note' }, rpc)
		);

		expect(response.status).toBe(422);
		expect(rpc).not.toHaveBeenCalled();
	});
});
