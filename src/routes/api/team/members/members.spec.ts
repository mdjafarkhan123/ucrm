import { beforeEach, describe, expect, it, vi } from 'vitest';
import { GET } from './+server';
import { requireContractorTeamAdmin } from '$lib/server/access/contractor';

vi.mock('$lib/server/access/contractor', () => ({ requireContractorTeamAdmin: vi.fn() }));

const organizationId = '00000000-0000-4000-8000-000000000011';
const managerId = '00000000-0000-4000-8000-000000000012';
const memberId = '00000000-0000-4000-8000-000000000013';
const rpc = vi.fn();

function event(query = '') {
	return {
		request: new Request(`https://app.example.com/api/team/members${query}`),
		url: new URL(`https://app.example.com/api/team/members${query}`),
		locals: { supabase: { rpc } }
	} as unknown as Parameters<typeof GET>[0];
}
function directory(nextCursor: Record<string, unknown> | null = null) {
	return {
		data: {
			members: [{ user_id: memberId, display_name: 'Fern Field', status: 'active' }],
			next_cursor: nextCursor,
			seats_used: 4
		},
		error: null
	};
}

describe('Team directory API', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(requireContractorTeamAdmin).mockResolvedValue({
			context: {
				auth: {
					user: { id: managerId },
					organization: { id: organizationId, name: 'Ridgeway', role: 'admin' }
				},
				access: {
					features: { 'core.team': true },
					permissions: { 'team.manage': true },
					limits: { employee_seats: { value: 12, is_unlimited: false } }
				}
			} as never
		});
		rpc.mockResolvedValue(directory());
	});

	it('returns the authorization response without querying the directory', async () => {
		vi.mocked(requireContractorTeamAdmin).mockResolvedValueOnce({
			response: new Response(JSON.stringify({ error: 'Forbidden' }), { status: 403 })
		});
		const response = await GET(event());
		expect(response.status).toBe(403);
		expect(rpc).not.toHaveBeenCalled();
	});

	it('validates filters before the database call', async () => {
		const response = await GET(event('?status=removed&limit=500'));
		expect(response.status).toBe(422);
		expect(response.headers.get('cache-control')).toBe('private, no-cache');
		expect(rpc).not.toHaveBeenCalled();
	});

	it('rejects a malformed cursor before the database call', async () => {
		const response = await GET(event('?cursor=not-a-cursor'));
		expect(response.status).toBe(422);
		expect(await response.json()).toMatchObject({
			field_errors: { cursor: 'That page link is invalid.' }
		});
		expect(rpc).not.toHaveBeenCalled();
	});

	it('passes normalized filters and the bounded default page to the RPC', async () => {
		const response = await GET(event('?status=pending&search=%20FERN%20'));
		expect(rpc).toHaveBeenCalledWith('list_team_directory', {
			target_organization_id: organizationId,
			requested_status: 'pending',
			search_term: 'FERN',
			page_limit: 25,
			cursor_status_order: null,
			cursor_created_at: null,
			cursor_user_id: null
		});
		expect(response.headers.get('cache-control')).toBe('private, no-cache');
		expect(await response.json()).toMatchObject({
			seats: { used: 4, limit: 12, is_unlimited: false }
		});
	});

	it('round-trips an opaque cursor into the next database call', async () => {
		const databaseCursor = {
			status_order: 2,
			created_at: '2026-08-23T08:30:00+00:00',
			user_id: memberId
		};
		rpc.mockResolvedValueOnce(directory(databaseCursor));
		const first = await GET(event('?limit=10'));
		const opaqueCursor = (await first.json()).next_cursor as string;
		expect(opaqueCursor).not.toContain(memberId);

		await GET(event(`?limit=10&cursor=${encodeURIComponent(opaqueCursor)}`));
		expect(rpc).toHaveBeenLastCalledWith(
			'list_team_directory',
			expect.objectContaining({
				page_limit: 10,
				cursor_status_order: 2,
				cursor_created_at: databaseCursor.created_at,
				cursor_user_id: memberId
			})
		);
	});

	it('returns a stable private error when the database fails', async () => {
		const consoleError = vi.spyOn(console, 'error').mockImplementation(() => {});
		rpc.mockResolvedValueOnce({ data: null, error: { code: 'XX000', message: 'private detail' } });
		const response = await GET(event());
		expect(response.status).toBe(500);
		expect(response.headers.get('cache-control')).toBe('private, no-cache');
		expect(await response.json()).toEqual({ error: 'Team members could not be loaded.' });
		consoleError.mockRestore();
	});

	it('refuses an unexpected database response instead of leaking it', async () => {
		const consoleError = vi.spyOn(console, 'error').mockImplementation(() => {});
		rpc.mockResolvedValueOnce({ data: { private: 'wrong shape' }, error: null });
		const response = await GET(event());
		expect(response.status).toBe(500);
		expect(await response.json()).toEqual({ error: 'Team members could not be loaded.' });
		consoleError.mockRestore();
	});
});
