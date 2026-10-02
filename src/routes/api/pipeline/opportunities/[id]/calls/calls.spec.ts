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

function callRow(overrides: Record<string, unknown> = {}) {
	return {
		id: '00000000-0000-4000-8000-000000000001',
		opportunity_id: opportunityId,
		outcome: 'connected',
		note: 'Booked a visit',
		logged_by: 'user-1',
		created_at: '2026-10-02T10:00:00Z',
		...overrides
	};
}

function readEvent(result: { data: unknown; error: unknown }) {
	const builder: Record<string, unknown> = {};
	for (const method of ['select', 'eq', 'order', 'limit']) {
		builder[method] = vi.fn(() => builder);
	}
	builder.then = (resolve: (value: unknown) => unknown) => Promise.resolve(result).then(resolve);
	return {
		params: { id: opportunityId },
		locals: { supabase: { from: vi.fn(() => builder) } }
	} as unknown as Parameters<typeof GET>[0];
}

function writeEvent(body: unknown, rpc = vi.fn()) {
	return {
		params: { id: opportunityId },
		request: new Request(`http://localhost/api/pipeline/opportunities/${opportunityId}/calls`, {
			method: 'POST',
			headers: { 'content-type': 'application/json' },
			body: typeof body === 'string' ? body : JSON.stringify(body)
		}),
		locals: { supabase: { rpc } }
	} as unknown as Parameters<typeof POST>[0];
}

describe('opportunity calls list', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		mockedRequire.mockResolvedValue(context);
	});

	it('answers with the logged calls', async () => {
		const response = await GET(readEvent({ data: [callRow()], error: null }));

		expect(response.status).toBe(200);
		const body = await response.json();
		expect(body.calls).toHaveLength(1);
		expect(body.calls[0].outcome).toBe('connected');
	});

	it('reads with pipeline.view', async () => {
		await GET(readEvent({ data: [], error: null }));
		expect(mockedRequire).toHaveBeenCalledWith(expect.anything(), 'pipeline.view');
	});

	it('answers with a database error when the read fails', async () => {
		const response = await GET(readEvent({ data: null, error: { code: 'XX000' } }));
		expect(response.status).toBe(500);
	});
});

describe('logging a call', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		mockedRequire.mockResolvedValue(context);
	});

	it('writes with pipeline.edit', async () => {
		const rpc = vi.fn().mockResolvedValue({ data: [{ ...callRow(), restarted_progress: true }] });
		await POST(writeEvent({ outcome: 'connected' }, rpc));
		expect(mockedRequire).toHaveBeenCalledWith(expect.anything(), 'pipeline.edit');
	});

	it('saves the outcome and note, and says whether the clock restarted', async () => {
		const rpc = vi.fn().mockResolvedValue({ data: [{ ...callRow(), restarted_progress: true }] });

		const response = await POST(
			writeEvent({ outcome: 'connected', note: '  Booked a visit  ' }, rpc)
		);

		expect(response.status).toBe(201);
		expect(rpc).toHaveBeenCalledWith('pipeline_log_opportunity_call', {
			target_opportunity_id: opportunityId,
			new_outcome: 'connected',
			new_note: 'Booked a visit'
		});
		expect((await response.json()).restarted_progress).toBe(true);
	});

	it('sends an empty note as no note', async () => {
		const rpc = vi.fn().mockResolvedValue({
			data: [{ ...callRow({ outcome: 'no_answer', note: null }), restarted_progress: false }]
		});

		await POST(writeEvent({ outcome: 'no_answer', note: '   ' }, rpc));

		expect(rpc.mock.calls[0][1].new_note).toBeNull();
	});

	it.each([[{}], [{ outcome: 'answered' }], [{ outcome: null }]])(
		'refuses %j without choosing an outcome for the person',
		async (body) => {
			const rpc = vi.fn();
			const response = await POST(writeEvent(body, rpc));

			expect(response.status).toBe(422);
			expect(rpc).not.toHaveBeenCalled();
		}
	);

	it('refuses a note that is too long', async () => {
		const rpc = vi.fn();
		const response = await POST(writeEvent({ outcome: 'busy', note: 'x'.repeat(2001) }, rpc));

		expect(response.status).toBe(422);
		expect(rpc).not.toHaveBeenCalled();
	});

	it('refuses a body that is not JSON', async () => {
		const response = await POST(writeEvent('not json'));
		expect(response.status).toBe(422);
	});

	it('answers a card that is not theirs the same as a card that does not exist', async () => {
		const rpc = vi.fn().mockResolvedValue({ data: null, error: { code: '42501' } });
		const response = await POST(writeEvent({ outcome: 'connected' }, rpc));

		expect(response.status).toBe(404);
	});
});
