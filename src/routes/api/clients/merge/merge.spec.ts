import { beforeEach, describe, expect, it, vi } from 'vitest';
import { GET, POST } from './+server';
import { requireClientPermission } from '$lib/server/access/clients';

vi.mock('$lib/server/access/clients', () => ({ requireClientPermission: vi.fn() }));

const mockedRequire = vi.mocked(requireClientPermission);
const keepId = '00000000-0000-4000-8000-000000000061';
const mergeInId = '00000000-0000-4000-8000-000000000062';

function postEvent(rpc: ReturnType<typeof vi.fn>, body: unknown) {
	return {
		request: new Request('http://localhost/api/clients/merge', {
			method: 'POST',
			body: JSON.stringify(body)
		}),
		locals: { supabase: { rpc } }
	} as never;
}

function getEvent(rpc: ReturnType<typeof vi.fn>, primary: string, secondary: string) {
	return {
		url: new URL(`http://localhost/api/clients/merge?primary=${primary}&secondary=${secondary}`),
		locals: { supabase: { rpc } }
	} as never;
}

describe('client merge routes', () => {
	beforeEach(() => {
		mockedRequire.mockResolvedValue({ auth: { organization: { id: 'org' } } } as never);
	});

	it('checks the merge permission', async () => {
		const rpc = vi.fn();
		mockedRequire.mockResolvedValue({ response: new Response(null, { status: 403 }) } as never);

		expect((await POST(postEvent(rpc, {}))).status).toBe(403);
		expect(mockedRequire).toHaveBeenCalledWith(expect.anything(), 'customers.merge');
		expect(rpc).not.toHaveBeenCalled();
	});

	it('merges through the checked database function', async () => {
		const result = { merge_id: 'm', surviving_client_id: keepId };
		const rpc = vi.fn().mockResolvedValue({ data: result, error: null });
		const response = await POST(
			postEvent(rpc, { primary_client_id: keepId, secondary_client_id: mergeInId })
		);

		expect(response.status).toBe(200);
		expect(await response.json()).toEqual(result);
		expect(rpc).toHaveBeenCalledWith('merge_clients', {
			p_primary_client_id: keepId,
			p_secondary_client_id: mergeInId
		});
	});

	it('refuses the same client twice before touching the database', async () => {
		const rpc = vi.fn();
		const response = await POST(
			postEvent(rpc, { primary_client_id: keepId, secondary_client_id: keepId })
		);

		expect(response.status).toBe(422);
		expect(rpc).not.toHaveBeenCalled();
	});

	it('passes on what blocks the merge', async () => {
		const message = 'These clients cannot be merged: A card payment is still being processed.';
		const rpc = vi.fn().mockResolvedValue({ data: null, error: { code: '23514', message } });
		const response = await POST(
			postEvent(rpc, { primary_client_id: keepId, secondary_client_id: mergeInId })
		);

		expect(response.status).toBe(409);
		expect(await response.json()).toEqual({ error: message });
	});

	it('reads a client it cannot reach as missing', async () => {
		const rpc = vi.fn().mockResolvedValue({ data: null, error: { code: 'P0002', message: 'x' } });

		expect(
			(await POST(postEvent(rpc, { primary_client_id: keepId, secondary_client_id: mergeInId })))
				.status
		).toBe(404);
		expect((await GET(getEvent(rpc, keepId, mergeInId))).status).toBe(404);
	});

	it('returns the preview uncached', async () => {
		const preview = { moves: { jobs: 2 }, warnings: [], blockers: [] };
		const rpc = vi.fn().mockResolvedValue({ data: preview, error: null });
		const response = await GET(getEvent(rpc, keepId, mergeInId));

		expect(response.status).toBe(200);
		expect(response.headers.get('cache-control')).toBe('no-store');
		expect(await response.json()).toEqual({ preview });
		expect(rpc).toHaveBeenCalledWith('client_merge_preview', {
			p_primary_client_id: keepId,
			p_secondary_client_id: mergeInId
		});
	});
});
