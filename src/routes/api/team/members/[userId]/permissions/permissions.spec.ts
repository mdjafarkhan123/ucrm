import { beforeEach, describe, expect, it, vi } from 'vitest';
import { PUT } from './+server';
import { requireContractorTeamAdmin } from '$lib/server/access/contractor';
import { getTeamCommandClient } from '$lib/server/access/team-commands';

vi.mock('$lib/server/access/contractor', () => ({
	requireContractorTeamAdmin: vi.fn()
}));
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));

const rpc = vi.fn();
const from = vi.fn(() => ({
	select: () => ({ eq: () => ({ eq: () => Promise.resolve({ data: [], error: null }) }) })
}));
vi.mock('$lib/server/access/team-commands', async () => {
	const actual = await vi.importActual<typeof import('$lib/server/access/team-commands')>(
		'$lib/server/access/team-commands'
	);
	return { ...actual, getTeamCommandClient: vi.fn() };
});

const mockedRequire = vi.mocked(requireContractorTeamAdmin);
const adminId = '00000000-0000-4000-8000-000000000021';
const memberId = '00000000-0000-4000-8000-000000000022';

function event(userId: string, body: unknown) {
	return {
		params: { userId },
		request: new Request('http://localhost/api/team/members/' + userId + '/permissions', {
			method: 'PUT',
			headers: { 'content-type': 'application/json' },
			body: JSON.stringify(body)
		}),
		locals: {}
	} as Parameters<typeof PUT>[0];
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
	role: 'office',
	status: 'active',
	access_revision: 8,
	created_at: '2026-08-01T00:00:00Z',
	work_phone: null
};

function respond(result: unknown) {
	rpc.mockReturnValueOnce({ single: () => Promise.resolve(result) });
}

describe('team member permissions API', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		mockedRequire.mockResolvedValue({ context });
		vi.mocked(getTeamCommandClient).mockReturnValue({ rpc, from } as never);
	});

	it('refuses an override state the section cannot save', async () => {
		const response = await PUT(
			event(memberId, {
				expected_access_revision: 7,
				adjustments: [{ control_id: 'view-customers', override_state: 'inherit' }]
			})
		);

		expect(response.status).toBe(422);
		expect(rpc).not.toHaveBeenCalled();
	});

	it('refuses a database permission key from the browser', async () => {
		const response = await PUT(
			event(memberId, {
				expected_access_revision: 7,
				adjustments: [{ control_id: 'customers.view', override_state: 'grant' }]
			})
		);

		expect(response.status).toBe(422);
		expect(rpc).not.toHaveBeenCalled();
	});

	it('saves the whole adjustment set in one call', async () => {
		respond({ data: savedMember, error: null });
		const adjustments = [
			{ control_id: 'view-customers', override_state: 'grant' },
			{ control_id: 'send-quotes', override_state: 'deny' }
		];

		const response = await PUT(event(memberId, { expected_access_revision: 7, adjustments }));

		expect(rpc).toHaveBeenCalledWith('save_team_member_permissions', {
			target_organization_id: 'org-id',
			actor_user_id: adminId,
			target_user_id: memberId,
			desired_overrides: [
				{ permission_key: 'customers.view', override_state: 'grant' },
				{ permission_key: 'quotes.send', override_state: 'deny' }
			],
			expected_access_revision: 7
		});
		expect(response.status).toBe(200);
		expect(await response.json()).toEqual({
			member: {
				user_id: memberId,
				role: 'office',
				status: 'active',
				access_revision: 8,
				created_at: '2026-08-01T00:00:00Z'
			},
			adjustments
		});
	});

	it('treats an empty list as clearing every visible adjustment', async () => {
		respond({ data: savedMember, error: null });

		const response = await PUT(event(memberId, { expected_access_revision: 7, adjustments: [] }));

		expect(response.status).toBe(200);
		expect(rpc).toHaveBeenCalledWith(
			'save_team_member_permissions',
			expect.objectContaining({ desired_overrides: [] })
		);
	});

	it('explains a stale editor as a conflict, not a fault', async () => {
		respond({
			data: null,
			error: {
				code: 'P0409',
				message: 'Someone else changed this person’s access while you were editing.'
			}
		});

		const response = await PUT(
			event(memberId, {
				expected_access_revision: 2,
				adjustments: [{ control_id: 'view-customers', override_state: 'grant' }]
			})
		);

		expect(response.status).toBe(409);
		expect((await response.json()).stale).toBe(true);
	});

	it('does not leak a database fault to the screen', async () => {
		respond({ data: null, error: { code: '42883', message: 'function does not exist' } });

		const response = await PUT(event(memberId, { expected_access_revision: 7, adjustments: [] }));

		expect(response.status).toBe(500);
		expect(await response.json()).toEqual({
			error: 'The permission adjustments could not be saved.'
		});
	});
});
