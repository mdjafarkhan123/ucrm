import { beforeEach, describe, expect, it, vi } from 'vitest';
import { PATCH } from './+server';
import { requireContractorTeamAdmin } from '$lib/server/access/contractor';
import { getTeamCommandClient } from '$lib/server/access/team-commands';

vi.mock('$lib/server/access/contractor', () => ({
	requireContractorTeamAdmin: vi.fn()
}));
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));

const mockedRequire = vi.mocked(requireContractorTeamAdmin);
const adminId = '00000000-0000-4000-8000-000000000021';
const memberId = '00000000-0000-4000-8000-000000000022';

const rpc = vi.fn();
vi.mock('$lib/server/access/team-commands', async () => {
	const actual = await vi.importActual<typeof import('$lib/server/access/team-commands')>(
		'$lib/server/access/team-commands'
	);
	return { ...actual, getTeamCommandClient: vi.fn() };
});

function event(userId: string, body: unknown) {
	return {
		params: { userId },
		request: new Request('http://localhost/api/team/members/' + userId, {
			method: 'PATCH',
			headers: { 'content-type': 'application/json' },
			body: JSON.stringify(body)
		}),
		locals: {}
	} as Parameters<typeof PATCH>[0];
}

const context = {
	auth: {
		user: { id: adminId },
		organization: { id: 'org-id', role: 'admin' }
	},
	access: { features: { 'core.team': true }, permissions: { 'team.manage': true } }
} as never;

const savedMember = {
	user_id: memberId,
	role: 'sales',
	status: 'active',
	access_revision: 4,
	created_at: '2026-08-01T00:00:00Z',
	job_title: 'Estimator'
};

function respond(result: unknown) {
	rpc.mockReturnValueOnce({ single: () => Promise.resolve(result) });
}

describe('team member role API', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		mockedRequire.mockResolvedValue({ context });
		vi.mocked(getTeamCommandClient).mockReturnValue({ rpc } as never);
	});

	it('returns validation errors before calling the command', async () => {
		const response = await PATCH(
			event('not-a-uuid', { role: 'office', keep_adjustments: true, expected_access_revision: 3 })
		);

		expect(response.status).toBe(422);
		expect(rpc).not.toHaveBeenCalled();
	});

	it('refuses a save that carries no revision', async () => {
		const response = await PATCH(event(memberId, { role: 'office', keep_adjustments: true }));

		expect(response.status).toBe(422);
		expect(rpc).not.toHaveBeenCalled();
	});

	it('refuses ownership as a role without asking the database', async () => {
		const response = await PATCH(
			event(memberId, { role: 'owner', keep_adjustments: true, expected_access_revision: 3 })
		);

		expect(response.status).toBe(422);
		expect(rpc).not.toHaveBeenCalled();
	});

	it('hands the whole change to the command and returns the saved member', async () => {
		respond({ data: savedMember, error: null });

		const response = await PATCH(
			event(memberId, { role: 'sales', keep_adjustments: false, expected_access_revision: 3 })
		);

		expect(rpc).toHaveBeenCalledWith('change_team_member_role', {
			target_organization_id: 'org-id',
			actor_user_id: adminId,
			target_user_id: memberId,
			new_role: 'sales',
			keep_adjustments: false,
			expected_access_revision: 3
		});
		expect(response.status).toBe(200);
		expect(await response.json()).toEqual({
			member: {
				user_id: memberId,
				role: 'sales',
				status: 'active',
				access_revision: 4,
				created_at: '2026-08-01T00:00:00Z'
			}
		});
	});

	it('explains a stale editor as a conflict, not a fault', async () => {
		respond({
			data: null,
			error: {
				code: 'P0409',
				message: 'Someone else changed this person’s access while you were editing.'
			}
		});

		const response = await PATCH(
			event(memberId, { role: 'sales', keep_adjustments: true, expected_access_revision: 1 })
		);

		expect(response.status).toBe(409);
		expect(await response.json()).toEqual({
			error: 'Someone else changed this person’s access while you were editing.',
			stale: true
		});
	});

	it('passes an authority refusal through with its own message', async () => {
		respond({
			data: null,
			error: { code: '23514', message: 'Only the owner can make someone an administrator.' }
		});

		const response = await PATCH(
			event(memberId, { role: 'admin', keep_adjustments: true, expected_access_revision: 3 })
		);

		expect(response.status).toBe(409);
		expect(await response.json()).toEqual({
			error: 'Only the owner can make someone an administrator.'
		});
	});

	it('answers 404 when the member is not in this organization', async () => {
		respond({ data: null, error: { code: 'P0002', message: 'That team member was not found.' } });

		const response = await PATCH(
			event(memberId, { role: 'sales', keep_adjustments: true, expected_access_revision: 3 })
		);

		expect(response.status).toBe(404);
	});

	it('does not leak a database fault to the screen', async () => {
		respond({ data: null, error: { code: '42883', message: 'function does not exist' } });

		const response = await PATCH(
			event(memberId, { role: 'sales', keep_adjustments: true, expected_access_revision: 3 })
		);

		expect(response.status).toBe(500);
		expect(await response.json()).toEqual({ error: 'The employee role could not be changed.' });
	});
});
