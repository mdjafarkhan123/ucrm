import { beforeEach, describe, expect, it, vi } from 'vitest';
import { POST } from './+server';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { checkRateLimit } from '$lib/server/security/rate-limit';
import { verifyTurnstileToken } from '$lib/server/security/turnstile';

vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));
vi.mock('$lib/server/security/rate-limit', async (importOriginal) => ({
	...(await importOriginal<typeof import('$lib/server/security/rate-limit')>()),
	checkRateLimit: vi.fn()
}));
vi.mock('$lib/server/security/turnstile', () => ({ verifyTurnstileToken: vi.fn() }));

const mockedClient = vi.mocked(getOwnerSupabaseClient);
const mockedCheckRateLimit = vi.mocked(checkRateLimit);
const mockedVerifyTurnstile = vi.mocked(verifyTurnstileToken);

function postEvent(body: unknown) {
	return {
		request: new Request('http://localhost/api/get-started', {
			method: 'POST',
			body: JSON.stringify(body)
		}),
		getClientAddress: () => '203.0.113.1'
	} as Parameters<typeof POST>[0];
}

const validBody = {
	business_name: 'Ridgeway Roofing',
	main_contact_name: 'Jordan Ridgeway',
	main_contact_email: 'jordan@ridgeway.example',
	main_contact_phone: '555-0100',
	is_administrator_same_as_contact: true,
	trade: 'Roofing',
	city_country: 'Austin, USA',
	time_zone: 'America/Chicago',
	package_version_id: '11111111-1111-4111-8111-111111111111',
	privacy_policy_agreed: true,
	turnstile_token: 'a-token'
};

function clientWith(options: { rpcError?: unknown; applicationId?: string } = {}) {
	const notificationInsert = vi.fn().mockResolvedValue({ error: null });
	const rpc = vi
		.fn()
		.mockResolvedValue(
			options.rpcError
				? { data: null, error: options.rpcError }
				: { data: options.applicationId ?? 'app-1', error: null }
		);

	return {
		from: (table: string) => {
			if (table === 'platform_owner_settings') {
				return {
					upsert: () => ({ error: null }),
					select: () => ({
						eq: () => ({
							single: async () => ({
								data: {
									privacy_policy_url: 'https://example.com/privacy',
									privacy_policy_version: 'v1',
									payment_instructions: 'Pay via bank transfer.',
									sender_display_name: 'UpliftContractor',
									reply_to_address: 'owner@example.com',
									alert_recipient_emails: ['owner@example.com'],
									updated_at: '2026-08-12T00:00:00Z'
								},
								error: null
							})
						})
					})
				};
			}
			if (table === 'platform_owner_notifications') {
				return { insert: notificationInsert };
			}
			throw new Error(`unexpected table ${table}`);
		},
		rpc,
		__rpc: rpc,
		__notificationInsert: notificationInsert
	};
}

describe('public onboarding application submission API boundary', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		mockedCheckRateLimit.mockResolvedValue({ allowed: true, retryAfterSeconds: 0 });
		mockedVerifyTurnstile.mockResolvedValue(true);
	});

	it('validates the request body before touching the database', async () => {
		const response = await POST(postEvent({ ...validBody, main_contact_email: 'not-an-email' }));
		expect(response.status).toBe(422);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('rejects a submission that has not agreed to the privacy policy', async () => {
		const response = await POST(postEvent({ ...validBody, privacy_policy_agreed: false }));
		expect(response.status).toBe(422);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('returns 429 once the per-IP rate limit is exceeded', async () => {
		mockedClient.mockReturnValue(clientWith() as never);
		mockedCheckRateLimit.mockResolvedValue({ allowed: false, retryAfterSeconds: 300 });

		const response = await POST(postEvent(validBody));
		expect(response.status).toBe(429);
		expect(response.headers.get('Retry-After')).toBe('300');
	});

	it('rejects the submission when the spam check fails', async () => {
		mockedClient.mockReturnValue(clientWith() as never);
		mockedVerifyTurnstile.mockResolvedValue(false);

		const response = await POST(postEvent(validBody));
		expect(response.status).toBe(422);
	});

	it('saves the application and records a new-application notification on the happy path', async () => {
		const client = clientWith({ applicationId: 'app-42' });
		mockedClient.mockReturnValue(client as never);

		const response = await POST(postEvent(validBody));
		expect(response.status).toBe(200);
		expect(client.__rpc).toHaveBeenCalledWith(
			'submit_onboarding_application',
			expect.objectContaining({
				target_business_name: 'Ridgeway Roofing',
				target_main_contact_email: 'jordan@ridgeway.example',
				target_initial_administrator_name: '',
				target_initial_administrator_email: '',
				target_package_version_id: '11111111-1111-4111-8111-111111111111',
				target_privacy_policy_version: 'v1'
			})
		);
		expect(client.__notificationInsert).toHaveBeenCalledWith(
			expect.objectContaining({ kind: 'onboarding_application_submitted', severity: 'attention' })
		);
	});

	it('passes through the separate administrator name/email when the contact is not the administrator', async () => {
		const client = clientWith({ applicationId: 'app-42' });
		mockedClient.mockReturnValue(client as never);

		await POST(
			postEvent({
				...validBody,
				is_administrator_same_as_contact: false,
				initial_administrator_name: 'Alex Admin',
				initial_administrator_email: 'alex@ridgeway.example'
			})
		);
		expect(client.__rpc).toHaveBeenCalledWith(
			'submit_onboarding_application',
			expect.objectContaining({
				target_initial_administrator_name: 'Alex Admin',
				target_initial_administrator_email: 'alex@ridgeway.example'
			})
		);
	});

	it('raises an urgent owner alert and returns 500 when saving unexpectedly fails', async () => {
		const client = clientWith({ rpcError: new Error('db is down') });
		mockedClient.mockReturnValue(client as never);

		const response = await POST(postEvent(validBody));
		expect(response.status).toBe(500);
		expect(client.__notificationInsert).toHaveBeenCalledWith(
			expect.objectContaining({
				kind: 'onboarding_application_submission_failed',
				severity: 'urgent'
			})
		);
	});
});
