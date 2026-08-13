import { beforeEach, describe, expect, it, vi } from 'vitest';
import { POST } from './+server';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { checkRateLimit } from '$lib/server/security/rate-limit';
import { verifyTurnstileToken } from '$lib/server/security/turnstile';
import { sendApplicationReceipt } from '$lib/server/jafar/application-receipt';
import { raiseOwnerAlert } from '$lib/server/jafar/owner-alerts';

vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));
vi.mock('$lib/server/security/rate-limit', async (importOriginal) => ({
	...(await importOriginal<typeof import('$lib/server/security/rate-limit')>()),
	checkRateLimit: vi.fn()
}));
vi.mock('$lib/server/security/turnstile', () => ({ verifyTurnstileToken: vi.fn() }));
vi.mock('$lib/server/jafar/application-receipt', () => ({ sendApplicationReceipt: vi.fn() }));
vi.mock('$lib/server/jafar/owner-alerts', () => ({ raiseOwnerAlert: vi.fn() }));

const mockedClient = vi.mocked(getOwnerSupabaseClient);
const mockedCheckRateLimit = vi.mocked(checkRateLimit);
const mockedVerifyTurnstile = vi.mocked(verifyTurnstileToken);
const mockedSendReceipt = vi.mocked(sendApplicationReceipt);
const mockedRaiseAlert = vi.mocked(raiseOwnerAlert);

function postEvent(body: unknown) {
	return {
		request: new Request('http://localhost/api/get-started', {
			method: 'POST',
			body: JSON.stringify(body)
		}),
		url: new URL('http://localhost/api/get-started'),
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
			throw new Error(`unexpected table ${table}`);
		},
		rpc,
		__rpc: rpc
	};
}

describe('public onboarding application submission API boundary', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		mockedCheckRateLimit.mockResolvedValue({ allowed: true, retryAfterSeconds: 0 });
		mockedVerifyTurnstile.mockResolvedValue(true);
		mockedSendReceipt.mockResolvedValue(undefined);
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
		expect(mockedRaiseAlert).toHaveBeenCalledWith(
			client,
			expect.objectContaining({
				kind: 'onboarding_application_submitted',
				severity: 'attention',
				target: { targetKind: 'onboarding_application', targetId: 'app-42' }
			})
		);
	});

	it('returns the new application id and queues the receipt email to the main contact', async () => {
		const client = clientWith({ applicationId: 'app-42' });
		mockedClient.mockReturnValue(client as never);

		const response = await POST(postEvent(validBody));
		const result = await response.json();

		expect(result).toEqual({ ok: true, applicationId: 'app-42' });
		expect(mockedSendReceipt).toHaveBeenCalledWith(
			client,
			expect.objectContaining({
				applicationId: 'app-42',
				recipientEmail: 'jordan@ridgeway.example',
				paymentInstructions: 'Pay via bank transfer.'
			})
		);
	});

	it('still saves the application and returns success when the receipt email fails to queue', async () => {
		const client = clientWith({ applicationId: 'app-42' });
		mockedClient.mockReturnValue(client as never);
		mockedSendReceipt.mockRejectedValue(new Error('Brevo is down'));

		const response = await POST(postEvent(validBody));
		expect(response.status).toBe(200);
		expect(await response.json()).toEqual({ ok: true, applicationId: 'app-42' });
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

	it('rejects a separate administrator with no name or email, which the browser form hides', async () => {
		const response = await POST(
			postEvent({ ...validBody, is_administrator_same_as_contact: false })
		);
		const result = await response.json();

		expect(response.status).toBe(422);
		expect(result.field_errors).toMatchObject({
			initial_administrator_name: expect.any(String),
			initial_administrator_email: expect.any(String)
		});
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('asks the visitor to choose again when the package was retired while they were filling the form', async () => {
		const client = clientWith({
			rpcError: { code: '23514', message: 'The selected package is no longer available.' }
		});
		mockedClient.mockReturnValue(client as never);

		const response = await POST(postEvent(validBody));
		const result = await response.json();

		expect(response.status).toBe(422);
		expect(result.field_errors.package_version_id).toContain('no longer available');
		expect(mockedRaiseAlert).not.toHaveBeenCalled();
		expect(mockedSendReceipt).not.toHaveBeenCalled();
	});

	it('does the same when the chosen package no longer exists at all', async () => {
		const client = clientWith({
			rpcError: { code: '23503', message: 'The selected package no longer exists.' }
		});
		mockedClient.mockReturnValue(client as never);

		const response = await POST(postEvent(validBody));

		expect(response.status).toBe(422);
		expect(mockedRaiseAlert).not.toHaveBeenCalled();
	});

	it('never leaks the underlying database error to the public form', async () => {
		const client = clientWith({
			rpcError: new Error('relation "platform_onboarding_applications" does not exist')
		});
		mockedClient.mockReturnValue(client as never);

		const response = await POST(postEvent(validBody));
		const result = await response.json();

		expect(response.status).toBe(500);
		expect(JSON.stringify(result)).not.toContain('platform_onboarding_applications');
	});

	it('raises an urgent owner alert and returns 500 when saving unexpectedly fails', async () => {
		const client = clientWith({ rpcError: new Error('db is down') });
		mockedClient.mockReturnValue(client as never);

		const response = await POST(postEvent(validBody));
		expect(response.status).toBe(500);
		expect(mockedRaiseAlert).toHaveBeenCalledWith(
			client,
			expect.objectContaining({
				kind: 'onboarding_application_submission_failed',
				severity: 'urgent'
			})
		);
	});

	it('still saves the application and returns success when the owner alert itself fails', async () => {
		const client = clientWith({ applicationId: 'app-42' });
		mockedClient.mockReturnValue(client as never);
		mockedRaiseAlert.mockRejectedValue(new Error('notifications table unreachable'));

		const response = await POST(postEvent(validBody));
		expect(response.status).toBe(200);
		expect(await response.json()).toEqual({ ok: true, applicationId: 'app-42' });
		expect(mockedSendReceipt).toHaveBeenCalled();
	});
});
