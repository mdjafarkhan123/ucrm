import { beforeEach, describe, expect, it, vi } from 'vitest';
import { DELETE } from './+server';
import { GET } from './delete-impact/+server';
import { requireClientPermission } from '$lib/server/access/clients';

vi.mock('$lib/server/access/clients', () => ({ requireClientPermission: vi.fn() }));

const mockedRequire = vi.mocked(requireClientPermission);
const propertyId = '00000000-0000-4000-8000-000000000051';

function event(rpc: ReturnType<typeof vi.fn>) {
	return {
		params: { id: propertyId },
		locals: { supabase: { rpc } }
	} as never;
}

describe('property delete routes', () => {
	beforeEach(() => {
		mockedRequire.mockResolvedValue({ auth: { organization: { id: 'org' } } } as never);
	});

	it('deletes through the checked database function', async () => {
		const rpc = vi.fn().mockResolvedValue({ data: null, error: null });
		const response = await DELETE(event(rpc));

		expect(response.status).toBe(204);
		expect(rpc).toHaveBeenCalledWith('delete_property', { p_property_id: propertyId });
	});

	it('passes on which record blocks the delete', async () => {
		const message = 'This property cannot be deleted: Job #4 has been invoiced.';
		const rpc = vi.fn().mockResolvedValue({ data: null, error: { code: '23514', message } });
		const response = await DELETE(event(rpc));

		expect(response.status).toBe(409);
		expect(await response.json()).toEqual({ error: message });
	});

	it('refuses a member who cannot delete the work at the address', async () => {
		const message = 'This property has jobs, and you do not have access to delete jobs.';
		const rpc = vi.fn().mockResolvedValue({ data: null, error: { code: '42501', message } });
		const response = await DELETE(event(rpc));

		expect(response.status).toBe(403);
		expect(await response.json()).toEqual({ error: message });
	});

	it('reads a property it cannot reach as missing', async () => {
		const rpc = vi.fn().mockResolvedValue({ data: null, error: { code: 'P0002', message: 'x' } });

		expect((await DELETE(event(rpc))).status).toBe(404);
		expect((await GET(event(rpc))).status).toBe(404);
	});

	it('returns the impact uncached', async () => {
		const impact = { requests: 1, quotes: 2, jobs: 0, visits: 0, blockers: [] };
		const rpc = vi.fn().mockResolvedValue({ data: impact, error: null });
		const response = await GET(event(rpc));

		expect(response.status).toBe(200);
		expect(response.headers.get('cache-control')).toBe('no-store');
		expect(await response.json()).toEqual({ impact });
		expect(rpc).toHaveBeenCalledWith('property_delete_impact', { p_property_id: propertyId });
	});
});
