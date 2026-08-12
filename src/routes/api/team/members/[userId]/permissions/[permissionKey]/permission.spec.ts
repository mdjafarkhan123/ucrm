import { beforeEach, describe, expect, it, vi } from 'vitest';
import { PATCH } from './+server';
import { requireContractorTeamAdmin } from '$lib/server/access/contractor';

vi.mock('$lib/server/access/contractor', () => ({
	requireContractorTeamAdmin: vi.fn()
}));

const mockedRequire = vi.mocked(requireContractorTeamAdmin);
const adminId = '00000000-0000-4000-8000-000000000021';
const memberId = '00000000-0000-4000-8000-000000000022';

function event(userId: string, permissionKey: string, body: unknown, supabase: unknown) {
	return {
		params: { userId, permissionKey },
		request: new Request(
			'http://localhost/api/team/members/' + userId + '/permissions/' + permissionKey,
			{
				method: 'PATCH',
				headers: { 'content-type': 'application/json' },
				body: JSON.stringify(body)
			}
		),
		locals: { supabase }
	} as Parameters<typeof PATCH>[0];
}

function query(result: unknown) {
	const builder = {
		select: () => builder,
		eq: () => builder,
		maybeSingle: () => Promise.resolve(result),
		delete: () => builder,
		upsert: () => builder,
		single: () => Promise.resolve(result)
	};
	return builder;
}

const context = {
	auth: {
		user: { id: adminId },
		organization: { id: 'org-id', role: 'admin' }
	},
	access: { features: { 'core.team': true }, permissions: { 'team.manage': true } }
} as never;

describe('employee permission override API', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		mockedRequire.mockResolvedValue({ context });
	});

	it('prevents an owner or admin from denying team management', async () => {
		const memberQuery = query({ data: { user_id: adminId, role: 'admin' }, error: null });
		const permissionQuery = query({ data: { key: 'team.manage' }, error: null });
		const supabase = {
			from: vi.fn().mockReturnValueOnce(memberQuery).mockReturnValueOnce(permissionQuery)
		};
		const response = await PATCH(
			event(adminId, 'team.manage', { override_state: 'deny' }, supabase)
		);

		expect(response.status).toBe(409);
		expect(supabase.from).toHaveBeenCalledTimes(2);
	});

	it('supports inherit by deleting the existing override', async () => {
		const memberQuery = query({ data: { user_id: memberId, role: 'field' }, error: null });
		const permissionQuery = query({ data: { key: 'customer.edit' }, error: null });
		const deleteQuery = query({ data: null, error: null });
		const supabase = {
			from: vi
				.fn()
				.mockReturnValueOnce(memberQuery)
				.mockReturnValueOnce(permissionQuery)
				.mockReturnValueOnce(deleteQuery)
		};

		const response = await PATCH(
			event(memberId, 'customer.edit', { override_state: 'inherit' }, supabase)
		);

		expect(response.status).toBe(200);
		expect(await response.json()).toEqual({ override: null, override_state: 'inherit' });
	});

	it('supports a grant override for a valid member and permission', async () => {
		const memberQuery = query({ data: { user_id: memberId, role: 'field' }, error: null });
		const permissionQuery = query({ data: { key: 'customer.edit' }, error: null });
		const upsertQuery = query({
			data: {
				user_id: memberId,
				permission_key: 'customer.edit',
				override_state: 'grant',
				created_at: null,
				updated_at: null
			},
			error: null
		});
		const supabase = {
			from: vi
				.fn()
				.mockReturnValueOnce(memberQuery)
				.mockReturnValueOnce(permissionQuery)
				.mockReturnValueOnce(upsertQuery)
		};

		const response = await PATCH(
			event(memberId, 'customer.edit', { override_state: 'grant' }, supabase)
		);

		expect(response.status).toBe(200);
		expect((await response.json()).override.override_state).toBe('grant');
	});
});
