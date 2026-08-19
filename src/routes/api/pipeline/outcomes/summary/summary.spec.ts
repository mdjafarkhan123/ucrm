import { beforeEach, describe, expect, it, vi } from 'vitest';
import { GET } from './+server';
import { hasPermission, requireOrganizationPermission } from '$lib/server/access/permission';
import { organizationFormatting } from '$lib/server/requests/timezone';

vi.mock('$lib/server/access/permission', () => ({
	requireOrganizationPermission: vi.fn(),
	hasPermission: vi.fn()
}));
vi.mock('$lib/server/requests/timezone', () => ({
	organizationFormatting: vi.fn()
}));

const mockedRequire = vi.mocked(requireOrganizationPermission);
const mockedHasPermission = vi.mocked(hasPermission);
const mockedFormatting = vi.mocked(organizationFormatting);

const organizationId = '00000000-0000-4000-8000-0000000000aa';
const context = {
	auth: { user: { id: 'user-1' }, organization: { id: organizationId } },
	access: {}
} as never;

function event(rpc = vi.fn()) {
	return { locals: { supabase: { rpc } } } as unknown as Parameters<typeof GET>[0];
}

describe('outcome tiles', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		mockedRequire.mockResolvedValue(context);
		mockedFormatting.mockResolvedValue({
			ok: true,
			formatting: { timezone: 'America/Toronto', currency_code: 'CAD', locale: 'en-CA' }
		});
	});

	it('needs pipeline.view', async () => {
		mockedRequire.mockResolvedValue({ response: new Response(null, { status: 403 }) } as never);
		const rpc = vi.fn();

		const response = await GET(event(rpc));

		expect(response.status).toBe(403);
		expect(mockedRequire).toHaveBeenCalledWith(expect.anything(), 'pipeline.view');
		expect(rpc).not.toHaveBeenCalled();
	});

	it('zero-fills a type with nothing in the window', async () => {
		mockedHasPermission.mockReturnValue(true);
		const rpc = vi.fn().mockResolvedValue({
			data: [{ outcome_key: 'lost', closed_count: 4, value_total: 1200 }],
			error: null
		});

		const response = await GET(event(rpc));
		const body = await response.json();

		expect(body.won).toEqual({ count: 0, value_total: null });
		expect(body.lost).toEqual({ count: 4, value_total: 1200 });
	});

	it('omits value totals entirely without pipeline.view_value', async () => {
		mockedHasPermission.mockReturnValue(false);
		const rpc = vi
			.fn()
			.mockResolvedValue({ data: [{ outcome_key: 'lost', closed_count: 4, value_total: 1200 }], error: null });

		const response = await GET(event(rpc));
		const body = await response.json();

		expect(body.lost).toEqual({ count: 4 });
		expect(body.lost.value_total).toBeUndefined();
		expect(body.can_view_value).toBe(false);
	});

	it('resolves a rolling 30-day window in the organization timezone', async () => {
		mockedHasPermission.mockReturnValue(true);
		const rpc = vi.fn().mockResolvedValue({ data: [], error: null });

		await GET(event(rpc));

		expect(rpc).toHaveBeenCalledWith(
			'pipeline_outcome_tiles',
			expect.objectContaining({ target_organization_id: organizationId })
		);
		const call = rpc.mock.calls[0][1] as { tile_from: string; tile_to: string };
		expect(new Date(call.tile_from).getTime()).toBeLessThan(new Date(call.tile_to).getTime());
	});

	it('turns a database error into a generic failure', async () => {
		mockedHasPermission.mockReturnValue(true);
		const rpc = vi.fn().mockResolvedValue({ data: null, error: { code: '08000' } });

		const response = await GET(event(rpc));
		expect(response.status).toBe(500);
	});

	it('keeps the response out of any shared cache', async () => {
		mockedHasPermission.mockReturnValue(true);
		const rpc = vi.fn().mockResolvedValue({ data: [], error: null });

		const response = await GET(event(rpc));
		expect(response.headers.get('cache-control')).not.toBe('public');
	});
});
