import { beforeEach, describe, expect, it, vi } from 'vitest';
import { GET } from './+server';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';

vi.mock('$lib/server/auth/owner', () => ({ getOwnerSession: vi.fn() }));
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));

const mockedOwnerSession = vi.mocked(getOwnerSession);
const mockedClient = vi.mocked(getOwnerSupabaseClient);

function session() {
	return { email: 'owner@example.com', sessionId: 'session-id' };
}

function event(url = 'http://localhost/api/jafar/organizations') {
	return { url: new URL(url), params: {}, cookies: {} } as Parameters<typeof GET>[0];
}

function directoryResult(overrides: Partial<Record<string, unknown>> = {}) {
	return {
		organizations: [],
		next_cursor: null,
		totals: {
			all: 0,
			active: 0,
			suspended: 0,
			matching: 0,
			attention: {
				access_overdue: 0,
				payment_overdue: 0,
				renewal_due: 0,
				expiring_soon: 0,
				administrator_missing: 0,
				administrator_ownership_unclear: 0,
				setup_or_recovery_failed: 0,
				email_setup_requested: 0
			}
		},
		...overrides
	};
}

// What the directory function is asked when no filter is set: every filter absent, none half-applied.
const noFilters = {
	attention_filter: undefined,
	lifecycle_filter: undefined,
	package_filter: undefined,
	no_package_filter: false,
	billing_filter: undefined,
	renews_filter: undefined,
	joined_from_filter: undefined,
	joined_before_filter: undefined,
	team_size_filter: undefined
};

describe('platform owner organization directory GET boundary', () => {
	beforeEach(() => {
		vi.clearAllMocks();
	});

	it('rejects callers without the separate owner session', async () => {
		mockedOwnerSession.mockResolvedValue(null);

		const response = await GET(event());

		expect(response.status).toBe(401);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('rejects an invalid attention reason filter', async () => {
		mockedOwnerSession.mockResolvedValue(session());

		const response = await GET(
			event('http://localhost/api/jafar/organizations?attention_reason=bogus')
		);

		expect(response.status).toBe(422);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('rejects an out-of-range page limit', async () => {
		mockedOwnerSession.mockResolvedValue(session());

		const response = await GET(event('http://localhost/api/jafar/organizations?limit=500'));

		expect(response.status).toBe(422);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('rejects a malformed page cursor', async () => {
		mockedOwnerSession.mockResolvedValue(session());

		const response = await GET(
			event('http://localhost/api/jafar/organizations?cursor=not-base64-json')
		);

		expect(response.status).toBe(422);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('calls the directory function with no filters on a bare request', async () => {
		mockedOwnerSession.mockResolvedValue(session());
		const rpc = vi.fn().mockResolvedValue({ data: directoryResult(), error: null });
		mockedClient.mockReturnValue({ rpc } as never);

		const response = await GET(event());

		expect(response.status).toBe(200);
		expect(rpc).toHaveBeenCalledWith('owner_organization_directory', {
			search_term: undefined,
			...noFilters,
			cursor_created_at: undefined,
			cursor_id: undefined,
			page_size: 50
		});
	});

	it('passes search, attention reason, and limit through to the directory function', async () => {
		mockedOwnerSession.mockResolvedValue(session());
		const rpc = vi.fn().mockResolvedValue({ data: directoryResult(), error: null });
		mockedClient.mockReturnValue({ rpc } as never);

		const response = await GET(
			event(
				'http://localhost/api/jafar/organizations?search=raad&attention_reason=access_overdue&limit=10'
			)
		);

		expect(response.status).toBe(200);
		expect(rpc).toHaveBeenCalledWith('owner_organization_directory', {
			search_term: 'raad',
			...noFilters,
			attention_filter: ['access_overdue'],
			cursor_created_at: undefined,
			cursor_id: undefined,
			page_size: 10
		});
	});

	it('decodes a page cursor from the previous response into created_at and id', async () => {
		mockedOwnerSession.mockResolvedValue(session());
		const rpc = vi.fn().mockResolvedValue({ data: directoryResult(), error: null });
		mockedClient.mockReturnValue({ rpc } as never);

		const cursor = Buffer.from(
			JSON.stringify({
				created_at: '2026-08-01T00:00:00Z',
				id: '123e4567-e89b-12d3-a456-426614174000'
			}),
			'utf8'
		).toString('base64url');

		const response = await GET(event(`http://localhost/api/jafar/organizations?cursor=${cursor}`));

		expect(response.status).toBe(200);
		expect(rpc).toHaveBeenCalledWith('owner_organization_directory', {
			search_term: undefined,
			...noFilters,
			cursor_created_at: '2026-08-01T00:00:00Z',
			cursor_id: '123e4567-e89b-12d3-a456-426614174000',
			page_size: 50
		});
	});

	it('encodes the next cursor from the directory function into an opaque page token', async () => {
		mockedOwnerSession.mockResolvedValue(session());
		const rpc = vi.fn().mockResolvedValue({
			data: directoryResult({
				next_cursor: {
					created_at: '2026-08-01T00:00:00Z',
					id: '123e4567-e89b-12d3-a456-426614174000'
				}
			}),
			error: null
		});
		mockedClient.mockReturnValue({ rpc } as never);

		const response = await GET(event());
		const body = await response.json();

		expect(typeof body.next_cursor).toBe('string');
		const decoded = JSON.parse(Buffer.from(body.next_cursor, 'base64url').toString('utf8'));
		expect(decoded).toEqual({
			created_at: '2026-08-01T00:00:00Z',
			id: '123e4567-e89b-12d3-a456-426614174000'
		});
	});

	it('returns organizations and totals from the directory function', async () => {
		mockedOwnerSession.mockResolvedValue(session());
		const result = directoryResult({
			organizations: [
				{
					id: '123e4567-e89b-12d3-a456-426614174000',
					name: 'Raad',
					slug: 'raad',
					lifecycle_status: 'active',
					created_at: '2026-08-01T00:00:00Z',
					updated_at: '2026-08-01T00:00:00Z',
					member_count: 1,
					attention_reasons: []
				}
			],
			totals: { ...directoryResult().totals, all: 1, active: 1, matching: 1 }
		});
		const rpc = vi.fn().mockResolvedValue({ data: result, error: null });
		mockedClient.mockReturnValue({ rpc } as never);

		const response = await GET(event());
		const body = await response.json();

		expect(response.status).toBe(200);
		expect(body.organizations).toEqual(result.organizations);
		expect(body.totals).toEqual(result.totals);
		expect(body.next_cursor).toBeNull();
	});

	it('returns a safe server error when the directory function fails', async () => {
		mockedOwnerSession.mockResolvedValue(session());
		const rpc = vi
			.fn()
			.mockResolvedValue({ data: null, error: { message: 'internal database details' } });
		mockedClient.mockReturnValue({ rpc } as never);

		const response = await GET(event());

		expect(response.status).toBe(500);
		expect(await response.json()).toEqual({ error: 'Organizations could not be loaded.' });
	});
	it.each([
		['an unknown lifecycle', 'lifecycle=active,gone'],
		['an unknown billing interval', 'billing=weekly'],
		['an unknown renewal window', 'renews=90'],
		['an unknown team size', 'team=huge'],
		['a package that is not an id', 'package=starter'],
		['a range without the custom option', 'from=2026-01-01'],
		['a custom range with no dates', 'joined=custom'],
		['a range that ends before it starts', 'joined=custom&from=2026-02-01&to=2026-01-01'],
		['a malformed date', 'joined=custom&from=01-02-2026']
	])('rejects %s', async (_name, query) => {
		mockedOwnerSession.mockResolvedValue(session());

		const response = await GET(event(`http://localhost/api/jafar/organizations?${query}`));

		expect(response.status).toBe(422);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('passes every filter through, splitting packages from the no-package choice', async () => {
		mockedOwnerSession.mockResolvedValue(session());
		const rpc = vi.fn().mockResolvedValue({ data: directoryResult(), error: null });
		mockedClient.mockReturnValue({ rpc } as never);
		const packageId = '123e4567-e89b-12d3-a456-426614174000';

		const response = await GET(
			event(
				`http://localhost/api/jafar/organizations?attention_reason=renewal_due,payment_overdue&lifecycle=active,suspended&package=${packageId},none&billing=year&renews=14&team=small`
			)
		);

		expect(response.status).toBe(200);
		expect(rpc).toHaveBeenCalledWith(
			'owner_organization_directory',
			expect.objectContaining({
				attention_filter: ['renewal_due', 'payment_overdue'],
				lifecycle_filter: ['active', 'suspended'],
				package_filter: [packageId],
				no_package_filter: true,
				billing_filter: 'year',
				renews_filter: '14',
				team_size_filter: 'small'
			})
		);
	});

	it('turns a custom joined range into whole days with both ends included', async () => {
		mockedOwnerSession.mockResolvedValue(session());
		const rpc = vi.fn().mockResolvedValue({ data: directoryResult(), error: null });
		mockedClient.mockReturnValue({ rpc } as never);

		await GET(
			event('http://localhost/api/jafar/organizations?joined=custom&from=2026-01-05&to=2026-01-31')
		);

		expect(rpc).toHaveBeenCalledWith(
			'owner_organization_directory',
			expect.objectContaining({
				joined_from_filter: '2026-01-05T00:00:00Z',
				joined_before_filter: '2026-02-01T00:00:00.000Z'
			})
		);
	});

	it('counts a joined preset back from now', async () => {
		mockedOwnerSession.mockResolvedValue(session());
		const rpc = vi.fn().mockResolvedValue({ data: directoryResult(), error: null });
		mockedClient.mockReturnValue({ rpc } as never);
		const before = Date.now();

		await GET(event('http://localhost/api/jafar/organizations?joined=30'));

		const args = rpc.mock.calls[0][1] as {
			joined_from_filter: string;
			joined_before_filter?: string;
		};
		const expected = before - 30 * 24 * 60 * 60 * 1000;
		expect(Math.abs(Date.parse(args.joined_from_filter) - expected)).toBeLessThan(5000);
		expect(args.joined_before_filter).toBeUndefined();
	});
});
