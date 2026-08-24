import { beforeEach, describe, expect, it, vi } from 'vitest';
import { PATCH } from './+server';
import { requireContractorTeamAdmin } from '$lib/server/access/contractor';
import { getTeamCommandClient } from '$lib/server/access/team-commands';
import { checkRateLimit } from '$lib/server/security/rate-limit';

vi.mock('$lib/server/access/contractor', () => ({ requireContractorTeamAdmin: vi.fn() }));
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));
vi.mock('$lib/server/security/rate-limit', async () => {
	const actual = await vi.importActual<typeof import('$lib/server/security/rate-limit')>(
		'$lib/server/security/rate-limit'
	);
	return { ...actual, checkRateLimit: vi.fn() };
});
vi.mock('$lib/server/access/team-commands', async () => {
	const actual = await vi.importActual<typeof import('$lib/server/access/team-commands')>(
		'$lib/server/access/team-commands'
	);
	return { ...actual, getTeamCommandClient: vi.fn() };
});

const organizationId = '00000000-0000-4000-8000-000000000011';
const managerId = '00000000-0000-4000-8000-000000000012';
const memberId = '00000000-0000-4000-8000-000000000013';
const rpc = vi.fn();
const client = { rpc } as never;

function event(body: unknown, userId = memberId) {
	return {
		params: { userId },
		request: new Request(`https://app.example.com/api/team/members/${userId}/profile`, {
			method: 'PATCH',
			headers: { 'content-type': 'application/json' },
			body: JSON.stringify(body)
		}),
		locals: {}
	} as Parameters<typeof PATCH>[0];
}

function respond(result: unknown) {
	rpc.mockReturnValueOnce({ single: () => Promise.resolve(result) });
}

describe('team member profile API', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(requireContractorTeamAdmin).mockResolvedValue({
			context: {
				auth: { user: { id: managerId }, organization: { id: organizationId, role: 'admin' } },
				access: { features: { 'core.team': true }, permissions: { 'team.manage': true } }
			} as never
		});
		vi.mocked(getTeamCommandClient).mockReturnValue(client);
		vi.mocked(checkRateLimit).mockResolvedValue({ allowed: true, retryAfterSeconds: 0 });
	});

	it('validates before rate limiting or writing', async () => {
		const response = await PATCH(event({ expected_profile_revision: -1 }));

		expect(response.status).toBe(422);
		expect(response.headers.get('cache-control')).toBe('no-store');
		expect(checkRateLimit).not.toHaveBeenCalled();
		expect(rpc).not.toHaveBeenCalled();
	});

	it('saves all business profile fields through the database command', async () => {
		respond({ data: { user_id: memberId, profile_revision: 4 }, error: null });

		const response = await PATCH(
			event({
				full_name: ' Fern Field ',
				work_phone: '0400 123 456',
				job_title: 'Crew lead',
				schedule_color: '#4F7C1D',
				expected_profile_revision: 3
			})
		);

		expect(checkRateLimit).toHaveBeenCalledWith(client, {
			bucketKey: `team_member_profile:${organizationId}:${managerId}`,
			windowSeconds: 300,
			maxAttempts: 30
		});
		expect(rpc).toHaveBeenCalledWith('update_team_member_profile', {
			target_organization_id: organizationId,
			actor_user_id: managerId,
			target_user_id: memberId,
			new_full_name: 'Fern Field',
			new_work_phone: '0400 123 456',
			new_job_title: 'Crew lead',
			new_schedule_color: '#4F7C1D',
			expected_profile_revision: 3
		});
		expect(response.status).toBe(200);
		expect(response.headers.get('cache-control')).toBe('no-store');
		expect(await response.json()).toEqual({
			member: { user_id: memberId, profile_revision: 4 }
		});
	});

	it('rate limits before writing', async () => {
		vi.mocked(checkRateLimit).mockResolvedValueOnce({ allowed: false, retryAfterSeconds: 42 });

		const response = await PATCH(event({ expected_profile_revision: 3 }));

		expect(response.status).toBe(429);
		expect(response.headers.get('retry-after')).toBe('42');
		expect(rpc).not.toHaveBeenCalled();
	});

	it('keeps a revision conflict visible and non-cacheable', async () => {
		respond({
			data: null,
			error: {
				code: 'P0409',
				message: 'Someone else changed this person’s details while you were editing.'
			}
		});

		const response = await PATCH(event({ expected_profile_revision: 3 }));

		expect(response.status).toBe(409);
		expect(response.headers.get('cache-control')).toBe('no-store');
		expect(await response.json()).toEqual({
			error: 'Someone else changed this person’s details while you were editing.',
			stale: true
		});
	});
});
