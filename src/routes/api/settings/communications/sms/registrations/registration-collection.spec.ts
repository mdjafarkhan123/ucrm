import { beforeEach, describe, expect, it, vi } from 'vitest';
import { GET, POST } from './+server';
import { requireOrganizationAdmin } from '$lib/server/access/permission';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';

vi.mock('$lib/server/access/permission', () => ({ requireOrganizationAdmin: vi.fn() }));
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));

const organizationId = '123e4567-e89b-42d3-a456-426614174000';
const userId = '123e4567-e89b-42d3-a456-426614174001';
const registrationId = '123e4567-e89b-42d3-a456-426614174002';

function event(method: string) {
	return {
		request: new Request('http://localhost/api/settings/communications/sms/registrations', {
			method
		}),
		locals: {}
	} as never;
}

describe('contractor SMS registration collection API', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(requireOrganizationAdmin).mockResolvedValue({
			auth: {
				user: { id: userId, email: 'signed-in@ridgeway.example' },
				organization: { id: organizationId, name: 'Ridgeway', role: 'admin' }
			},
			access: { features: {}, limits: {}, permissions: {} }
		} as never);
	});

	it('stops before database access when owner/admin authorization is denied', async () => {
		vi.mocked(requireOrganizationAdmin).mockResolvedValue({
			response: new Response(null, { status: 403 })
		});

		const response = await GET(event('GET'));

		expect(response.status).toBe(403);
		expect(getOwnerSupabaseClient).not.toHaveBeenCalled();
	});

	it('reads null when the organization has not started a registration yet', async () => {
		const maybeSingle = vi.fn().mockResolvedValue({ data: null, error: null });
		const eq4 = vi.fn().mockReturnValue({ maybeSingle });
		const eq3 = vi.fn().mockReturnValue({ eq: eq4 });
		const eq2 = vi.fn().mockReturnValue({ eq: eq3 });
		const eq1 = vi.fn().mockReturnValue({ eq: eq2 });
		const select = vi.fn().mockReturnValue({ eq: eq1 });
		const rpc = vi.fn().mockResolvedValue({
			data: { readiness_state: 'needs_setup', effective_mode: 'operational', live_sender_count: 0 },
			error: null
		});
		vi.mocked(getOwnerSupabaseClient).mockReturnValue({
			from: vi.fn().mockReturnValue({ select }),
			rpc
		} as never);

		const response = await GET(event('GET'));
		const body = await response.json();

		expect(response.status).toBe(200);
		expect(body.registration).toBeNull();
		expect(body.readiness.readiness_state).toBe('needs_setup');
		expect(eq1).toHaveBeenCalledWith('organization_id', organizationId);
	});

	it('starts a registration scoped to the signed-in organization and actor', async () => {
		const rpc = vi.fn().mockResolvedValue({
			data: { id: registrationId, status: 'waiting_for_info', draft_revision: 1 },
			error: null
		});
		vi.mocked(getOwnerSupabaseClient).mockReturnValue({ rpc } as never);

		const response = await POST(event('POST'));
		const body = await response.json();

		expect(response.status).toBe(200);
		expect(body.registration.id).toBe(registrationId);
		expect(rpc).toHaveBeenCalledWith(
			'communication_sms_start_registration',
			expect.objectContaining({
				p_organization_id: organizationId,
				p_country_code: 'US',
				p_sender_type: 'long_code',
				p_actor: userId
			})
		);
	});
});
