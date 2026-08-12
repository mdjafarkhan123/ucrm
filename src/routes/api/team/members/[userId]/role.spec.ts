import { beforeEach, describe, expect, it, vi } from 'vitest';
import { PATCH } from './+server';
import { requireContractorTeamAdmin } from '$lib/server/access/contractor';

vi.mock('$lib/server/access/contractor', () => ({
	requireContractorTeamAdmin: vi.fn()
}));

const mockedRequire = vi.mocked(requireContractorTeamAdmin);
const adminId = '00000000-0000-4000-8000-000000000021';
const memberId = '00000000-0000-4000-8000-000000000022';

function event(userId: string, body: unknown, supabase: unknown = { from: vi.fn() }) {
	return {
		params: { userId },
		request: new Request('http://localhost/api/team/members/' + userId, {
			method: 'PATCH',
			headers: { 'content-type': 'application/json' },
			body: JSON.stringify(body)
		}),
		locals: { supabase }
	} as Parameters<typeof PATCH>[0];
}

function query(result: unknown) {
	const builder = {
		select: () => builder,
		eq: () => builder,
		in: () => builder,
		maybeSingle: () => Promise.resolve(result),
		update: () => builder,
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

describe('team member role API', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		mockedRequire.mockResolvedValue({ context });
	});

	it('returns validation errors before querying the database', async () => {
		const supabase = { from: vi.fn() };
		const response = await PATCH(event('not-a-uuid', { role: 'office' }, supabase));

		expect(response.status).toBe(422);
		expect(supabase.from).not.toHaveBeenCalled();
	});

	it('blocks an administrator from demoting themselves', async () => {
		const memberQuery = query({
			data: { user_id: adminId, role: 'admin', created_at: null },
			error: null
		});
		const supabase = { from: vi.fn().mockReturnValueOnce(memberQuery) };
		const response = await PATCH(event(adminId, { role: 'office' }, supabase));

		expect(response.status).toBe(409);
		expect(supabase.from).toHaveBeenCalledTimes(1);
	});

	it('blocks removal of the last owner or administrator', async () => {
		const memberQuery = query({
			data: { user_id: memberId, role: 'admin', created_at: null },
			error: null
		});
		const countQuery = query({ data: null, count: 1, error: null });
		const supabase = {
			from: vi.fn().mockReturnValueOnce(memberQuery).mockReturnValueOnce(countQuery)
		};

		const response = await PATCH(event(memberId, { role: 'office' }, supabase));

		expect(response.status).toBe(409);
	});

	it('updates a member role after authorization and validation', async () => {
		const memberQuery = query({
			data: { user_id: memberId, role: 'office', created_at: null },
			error: null
		});
		const updateQuery = query({
			data: { user_id: memberId, role: 'sales', created_at: null },
			error: null
		});
		const supabase = {
			from: vi.fn().mockReturnValueOnce(memberQuery).mockReturnValueOnce(updateQuery)
		};

		const response = await PATCH(event(memberId, { role: 'sales' }, supabase));

		expect(response.status).toBe(200);
		expect(await response.json()).toEqual({
			member: { user_id: memberId, role: 'sales', created_at: null }
		});
	});
});
