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
			pending_setup: 0,
			matching: 0,
			attention: {
				access_overdue: 0,
				expiring_soon: 0,
				administrator_missing: 0,
				administrator_ownership_unclear: 0,
				setup_or_recovery_failed: 0,
				legacy_review: 0
			}
		},
		...overrides
	};
}

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

		const response = await GET(event('http://localhost/api/jafar/organizations?attention_reason=bogus'));

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

		const response = await GET(event('http://localhost/api/jafar/organizations?cursor=not-base64-json'));

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
			attention_reason: undefined,
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
			attention_reason: 'access_overdue',
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
			JSON.stringify({ created_at: '2026-08-01T00:00:00Z', id: '123e4567-e89b-12d3-a456-426614174000' }),
			'utf8'
		).toString('base64url');

		const response = await GET(event(`http://localhost/api/jafar/organizations?cursor=${cursor}`));

		expect(response.status).toBe(200);
		expect(rpc).toHaveBeenCalledWith('owner_organization_directory', {
			search_term: undefined,
			attention_reason: undefined,
			cursor_created_at: '2026-08-01T00:00:00Z',
			cursor_id: '123e4567-e89b-12d3-a456-426614174000',
			page_size: 50
		});
	});

	it('encodes the next cursor from the directory function into an opaque page token', async () => {
		mockedOwnerSession.mockResolvedValue(session());
		const rpc = vi.fn().mockResolvedValue({
			data: directoryResult({
				next_cursor: { created_at: '2026-08-01T00:00:00Z', id: '123e4567-e89b-12d3-a456-426614174000' }
			}),
			error: null
		});
		mockedClient.mockReturnValue({ rpc } as never);

		const response = await GET(event());
		const body = await response.json();

		expect(typeof body.next_cursor).toBe('string');
		const decoded = JSON.parse(Buffer.from(body.next_cursor, 'base64url').toString('utf8'));
		expect(decoded).toEqual({ created_at: '2026-08-01T00:00:00Z', id: '123e4567-e89b-12d3-a456-426614174000' });
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
		const rpc = vi.fn().mockResolvedValue({ data: null, error: { message: 'internal database details' } });
		mockedClient.mockReturnValue({ rpc } as never);

		const response = await GET(event());

		expect(response.status).toBe(500);
		expect(await response.json()).toEqual({ error: 'Organizations could not be loaded.' });
	});
});
