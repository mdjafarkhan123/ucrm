import { beforeEach, describe, expect, it, vi } from 'vitest';
import { GET } from './+server';
import { requireContractorTeamAdmin } from '$lib/server/access/contractor';
import { getTeamCommandClient } from '$lib/server/access/team-commands';

vi.mock('$lib/server/access/contractor', async () => {
	const actual = await vi.importActual<typeof import('$lib/server/access/contractor')>(
		'$lib/server/access/contractor'
	);
	return { ...actual, requireContractorTeamAdmin: vi.fn() };
});
vi.mock('$lib/server/access/team-commands', () => ({ getTeamCommandClient: vi.fn() }));

const mockedRequire = vi.mocked(requireContractorTeamAdmin);
const actorId = '00000000-0000-4000-8000-000000000021';
const memberId = '00000000-0000-4000-8000-000000000022';

const context = {
	auth: {
		user: { id: actorId },
		organization: { id: 'org-id', role: 'admin' }
	},
	access: {
		features: { 'core.team': true, quotes: true, pipeline: true, customers: true }
	}
} as never;

function event(userId: string) {
	return { params: { userId }, locals: {} } as Parameters<typeof GET>[0];
}

function commandClient(member: unknown) {
	return {
		from: vi.fn((table: string) => {
			if (table === 'organization_members') {
				return {
					select: () => ({
						eq: () => ({ eq: () => ({ maybeSingle: () => Promise.resolve(member) }) })
					})
				};
			}
			if (table === 'role_permissions') {
				return {
					select: () =>
						Promise.resolve({
							data: [
								{ role: 'office', permission_key: 'customers.view' },
								{ role: 'office', permission_key: 'quotes.view' }
							],
							error: null
						})
				};
			}
			return {
				select: () => ({
					eq: () => ({
						eq: () =>
							Promise.resolve({
								data: [{ permission_key: 'quotes.view_cost', override_state: 'grant' }],
								error: null
							})
					})
				})
			};
		})
	};
}

describe('team member access editor API', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		mockedRequire.mockResolvedValue({ context });
	});

	it('validates the member id before reading access', async () => {
		const from = vi.fn();
		vi.mocked(getTeamCommandClient).mockReturnValue({ from } as never);

		const response = await GET(event('not-a-uuid'));

		expect(response.status).toBe(422);
		expect(from).not.toHaveBeenCalled();
	});

	it('returns a bounded editor model without internal permission keys', async () => {
		vi.mocked(getTeamCommandClient).mockReturnValue(
			commandClient({
				data: { role: 'office', status: 'active', access_revision: 4 },
				error: null
			}) as never
		);

		const response = await GET(event(memberId));
		const body = await response.json();

		expect(response.status).toBe(200);
		expect(body.access.member).toMatchObject({
			role: 'office',
			access_revision: 4,
			can_edit: true,
			is_adjusted: true
		});
		expect(body.access.capabilities[0].controls[0]).toMatchObject({
			id: 'view-customers',
			label: 'View customers'
		});
		expect(JSON.stringify(body)).not.toContain('customers.view');
		expect(JSON.stringify(body)).not.toContain('quotes.view_cost');
	});

	it('does not let an administrator edit another administrator', async () => {
		vi.mocked(getTeamCommandClient).mockReturnValue(
			commandClient({
				data: { role: 'admin', status: 'active', access_revision: 4 },
				error: null
			}) as never
		);

		const response = await GET(event(memberId));
		const body = await response.json();

		expect(response.status).toBe(200);
		expect(body.access.member).toMatchObject({
			can_edit: false,
			cannot_edit_reason: 'Only the Owner can change an Administrator’s access.'
		});
	});

	it('does not let an administrator edit their own role or access', async () => {
		vi.mocked(getTeamCommandClient).mockReturnValue(
			commandClient({
				data: { role: 'admin', status: 'active', access_revision: 4 },
				error: null
			}) as never
		);

		const response = await GET(event(actorId));
		const body = await response.json();

		expect(response.status).toBe(200);
		expect(body.access.member).toMatchObject({
			can_edit: false,
			cannot_edit_reason: 'People cannot change their own role or access.'
		});
		expect(body.access.roles.find((role: { id: string }) => role.id === 'admin')).toMatchObject({
			available: false
		});
	});

	it('does not leak another organization member through the editor', async () => {
		vi.mocked(getTeamCommandClient).mockReturnValue(
			commandClient({ data: null, error: null }) as never
		);

		const response = await GET(event(memberId));

		expect(response.status).toBe(404);
	});
});
