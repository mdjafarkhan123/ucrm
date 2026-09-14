import { beforeEach, describe, expect, it, vi } from 'vitest';
import { GET, PATCH } from './[registrationId]/+server';
import { POST as submit } from './[registrationId]/submit/+server';
import {
	SMS_REGISTRATION_ATTESTATION_TEXT,
	SMS_REGISTRATION_ATTESTATION_VERSION
} from '$lib/server/communications/sms-registration';
import { requireOrganizationAdmin } from '$lib/server/access/permission';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';

vi.mock('$lib/server/access/permission', () => ({ requireOrganizationAdmin: vi.fn() }));
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));

const organizationId = '123e4567-e89b-42d3-a456-426614174000';
const userId = '123e4567-e89b-42d3-a456-426614174001';
const registrationId = '123e4567-e89b-42d3-a456-426614174002';

const answers = {
	legal_business_name: 'Ridgeway Services LLC',
	business_type: 'limited_liability_company',
	business_registration_id_type: 'EIN',
	business_registration_id: '12-3456789',
	website_url: 'https://ridgeway.example',
	business_address: {
		line1: '12 Main Street',
		city: 'Austin',
		region: 'TX',
		postal_code: '78701',
		country_code: 'US'
	},
	authorized_representative: {
		first_name: 'Alex',
		last_name: 'Morgan',
		business_title: 'Owner',
		job_position: 'Owner',
		email: 'owner@ridgeway.example',
		phone_number: '+15125550100'
	},
	messaging: {
		description: 'Customer appointment updates and replies.',
		consent_method: 'website_form',
		consent_description: 'Customers tick an unchecked consent box on the request form.',
		sample_messages: [
			'Ridgeway: Your visit is booked for Tuesday. Reply STOP to opt out.',
			'Ridgeway: We are on the way. Reply STOP to opt out.'
		],
		privacy_policy_url: 'https://ridgeway.example/privacy',
		terms_url: 'https://ridgeway.example/terms',
		estimated_monthly_messages: 'under_500'
	}
};

function event(method: string, body?: unknown) {
	return {
		params: { registrationId },
		request: new Request(
			`http://localhost/api/settings/communications/sms/registrations/${registrationId}`,
			{
				method,
				headers: body === undefined ? undefined : { 'content-type': 'application/json' },
				body: body === undefined ? undefined : JSON.stringify(body)
			}
		),
		locals: {}
	} as never;
}

function rpcClient(result: { data: unknown; error: unknown }) {
	return { rpc: vi.fn().mockResolvedValue(result) };
}

describe('contractor SMS registration API', () => {
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

		const response = await PATCH(
			event('PATCH', { expected_revision: 1, questionnaire_version: 1, answers: {} })
		);

		expect(response.status).toBe(403);
		expect(getOwnerSupabaseClient).not.toHaveBeenCalled();
	});

	it('validates draft input before database access', async () => {
		const response = await PATCH(
			event('PATCH', { expected_revision: 0, questionnaire_version: 1, answers: {} })
		);

		expect(response.status).toBe(422);
		expect(getOwnerSupabaseClient).not.toHaveBeenCalled();
	});

	it('saves a draft with organization and actor identity from the session', async () => {
		const client = rpcClient({
			data: { id: registrationId, status: 'waiting_for_info', draft_revision: 2 },
			error: null
		});
		vi.mocked(getOwnerSupabaseClient).mockReturnValue(client as never);

		const response = await PATCH(
			event('PATCH', {
				expected_revision: 1,
				questionnaire_version: 1,
				answers: { legal_business_name: 'Ridgeway' }
			})
		);

		expect(response.status).toBe(200);
		expect(client.rpc).toHaveBeenCalledWith(
			'communication_sms_save_registration_draft',
			expect.objectContaining({
				p_organization_id: organizationId,
				p_registration_id: registrationId,
				p_actor: userId
			})
		);
	});

	it('requires the explicit authorized-representative confirmation', async () => {
		const response = await submit(
			event('POST', {
				expected_revision: 1,
				questionnaire_version: 1,
				answers,
				confirm_authorized_representative: false
			})
		);

		expect(response.status).toBe(422);
		expect(getOwnerSupabaseClient).not.toHaveBeenCalled();
	});

	it('submits the validated answers with server-owned attestation wording and signed-in identity', async () => {
		const client = rpcClient({
			data: {
				id: registrationId,
				status: 'under_review',
				submitted_at: '2026-09-14T00:00:00Z',
				draft_revision: 2
			},
			error: null
		});
		vi.mocked(getOwnerSupabaseClient).mockReturnValue(client as never);

		const response = await submit(
			event('POST', {
				expected_revision: 1,
				questionnaire_version: 1,
				answers,
				confirm_authorized_representative: true
			})
		);

		expect(response.status).toBe(200);
		expect(client.rpc).toHaveBeenCalledWith(
			'communication_sms_submit_registration_answers',
			expect.objectContaining({
				p_organization_id: organizationId,
				p_registration_id: registrationId,
				p_attested_by: userId,
				p_attestor_email: 'signed-in@ridgeway.example',
				p_attestation_version: SMS_REGISTRATION_ATTESTATION_VERSION,
				p_attestation_text: SMS_REGISTRATION_ATTESTATION_TEXT
			})
		);
	});

	it('does not attest for an account with no authenticated email', async () => {
		vi.mocked(requireOrganizationAdmin).mockResolvedValue({
			auth: {
				user: { id: userId, email: null },
				organization: { id: organizationId, name: 'Ridgeway', role: 'owner' }
			},
			access: { features: {}, limits: {}, permissions: {} }
		} as never);

		const response = await submit(
			event('POST', {
				expected_revision: 1,
				questionnaire_version: 1,
				answers,
				confirm_authorized_representative: true
			})
		);

		expect(response.status).toBe(409);
		expect(getOwnerSupabaseClient).not.toHaveBeenCalled();
	});

	it('keeps a registration read scoped to the signed-in organization', async () => {
		const maybeSingle = vi.fn().mockResolvedValue({ data: null, error: null });
		const secondEq = vi.fn().mockReturnValue({ maybeSingle });
		const firstEq = vi.fn().mockReturnValue({ eq: secondEq });
		const select = vi.fn().mockReturnValue({ eq: firstEq });
		vi.mocked(getOwnerSupabaseClient).mockReturnValue({
			from: vi.fn().mockReturnValue({ select })
		} as never);

		const response = await GET(event('GET'));

		expect(response.status).toBe(404);
		expect(firstEq).toHaveBeenCalledWith('organization_id', organizationId);
		expect(secondEq).toHaveBeenCalledWith('id', registrationId);
	});
});
