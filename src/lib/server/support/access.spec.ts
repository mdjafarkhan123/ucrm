import { describe, expect, it, vi } from 'vitest';
import { requireSupportMember } from './access';

// The database decides who may use support (public.support_member_context: an active member of a business
// that is active, paused, or pending closure). This only checks the door turns that answer into a context.
function event(user: unknown, rpcResult: { data: unknown; error: unknown }) {
	return {
		locals: {
			getUser: vi.fn().mockResolvedValue(user),
			supabase: { rpc: vi.fn().mockResolvedValue(rpcResult) }
		}
	} as never;
}

const USER = { id: 'user-1', email: 'sam@example.com' };
const ORGANIZATION = { id: 'org-1', name: 'Bright Spark', slug: 'bright-spark', role: 'field' };

describe('requireSupportMember', () => {
	it('gives the organization the database names, paused or not', async () => {
		const result = await requireSupportMember(event(USER, { data: ORGANIZATION, error: null }));
		expect(result).toEqual({ auth: { user: USER, organization: ORGANIZATION } });
	});

	it('refuses someone signed out', async () => {
		const result = await requireSupportMember(event(null, { data: ORGANIZATION, error: null }));
		expect('response' in result && result.response.status).toBe(401);
	});

	it('refuses someone support is not open to', async () => {
		const result = await requireSupportMember(event(USER, { data: null, error: null }));
		expect('response' in result && result.response.status).toBe(401);
	});

	it('refuses a role the app does not know', async () => {
		const result = await requireSupportMember(
			event(USER, { data: { ...ORGANIZATION, role: 'customer' }, error: null })
		);
		expect('response' in result && result.response.status).toBe(401);
	});

	it('reports a database failure as one', async () => {
		const result = await requireSupportMember(
			event(USER, { data: null, error: { message: 'down' } })
		);
		expect('response' in result && result.response.status).toBe(500);
	});
});
