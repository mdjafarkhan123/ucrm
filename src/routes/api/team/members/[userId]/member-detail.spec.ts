import { beforeEach, describe, expect, it, vi } from 'vitest';
import { GET } from './+server';
import { requireContractorTeamAdmin } from '$lib/server/access/contractor';

vi.mock('$lib/server/access/contractor', () => ({ requireContractorTeamAdmin: vi.fn() }));

const organizationId = '00000000-0000-4000-8000-000000000011';
const managerId = '00000000-0000-4000-8000-000000000012';
const memberId = '00000000-0000-4000-8000-000000000013';
const rpc = vi.fn();

function event(userId = memberId) {
	return {
		params: { userId },
		locals: { supabase: { rpc } }
	} as unknown as Parameters<typeof GET>[0];
}

const detail = {
	user_id: memberId,
	display_name: 'Fern Field',
	avatar_url: null,
	role: 'field',
	status: 'active',
	access_revision: 2,
	profile_revision: 3,
	work_phone: '0400 123 456',
	job_title: 'Crew lead',
	schedule_color: '#4F7C1D',
	created_at: '2026-08-23T00:00:00+00:00',
	deactivated_at: null,
	invitation: null
};

describe('team member detail API', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(requireContractorTeamAdmin).mockResolvedValue({
			context: {
				auth: { user: { id: managerId }, organization: { id: organizationId, role: 'admin' } },
				access: { features: { 'core.team': true }, permissions: { 'team.manage': true } }
			} as never
		});
		rpc.mockResolvedValue({ data: detail, error: null });
	});

	it('requires Team access before querying a member', async () => {
		vi.mocked(requireContractorTeamAdmin).mockResolvedValueOnce({
			response: new Response(JSON.stringify({ error: 'Forbidden' }), { status: 403 })
		});

		const response = await GET(event());

		expect(response.status).toBe(403);
		expect(rpc).not.toHaveBeenCalled();
	});

	it('validates the member identifier before the database call', async () => {
		const response = await GET(event('not-a-uuid'));

		expect(response.status).toBe(422);
		expect(response.headers.get('cache-control')).toBe('private, no-cache');
		expect(rpc).not.toHaveBeenCalled();
	});

	it('returns only the approved member detail shape', async () => {
		rpc.mockResolvedValueOnce({
			data: { ...detail, private_delivery_error: 'do not return this' },
			error: null
		});

		const response = await GET(event());

		expect(rpc).toHaveBeenCalledWith('get_team_member_detail', {
			target_organization_id: organizationId,
			target_user_id: memberId
		});
		expect(await response.json()).toEqual({ member: detail });
		expect(response.headers.get('cache-control')).toBe('private, no-cache');
	});

	it('keeps a missing member distinct from an internal failure', async () => {
		rpc.mockResolvedValueOnce({ data: null, error: { code: 'P0002', message: 'Not found' } });

		const response = await GET(event());

		expect(response.status).toBe(404);
		expect(await response.json()).toEqual({ error: 'That team member was not found.' });
	});

	it('does not pass an invalid database payload to the browser', async () => {
		const consoleError = vi.spyOn(console, 'error').mockImplementation(() => {});
		rpc.mockResolvedValueOnce({ data: { private: 'wrong shape' }, error: null });

		const response = await GET(event());

		expect(response.status).toBe(500);
		expect(await response.json()).toEqual({ error: 'That team member could not be loaded.' });
		consoleError.mockRestore();
	});
});
