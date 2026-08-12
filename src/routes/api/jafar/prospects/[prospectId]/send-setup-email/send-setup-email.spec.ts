import { beforeEach, describe, expect, it, vi } from 'vitest';
import { POST } from './+server';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { issueSetupLink } from '$lib/server/jafar/setup-link';

vi.mock('$lib/server/auth/owner', () => ({ getOwnerSession: vi.fn() }));
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));
vi.mock('$lib/server/jafar/setup-link', () => ({ issueSetupLink: vi.fn() }));

const mockedOwnerSession = vi.mocked(getOwnerSession);
const mockedClient = vi.mocked(getOwnerSupabaseClient);
const mockedIssueSetupLink = vi.mocked(issueSetupLink);

const prospectId = '123e4567-e89b-12d3-a456-426614174000';

function event(id: string) {
	return {
		params: { prospectId: id },
		request: new Request('http://localhost/api/jafar/prospects/' + id + '/send-setup-email', {
			method: 'POST'
		}),
		url: new URL('http://localhost/api/jafar/prospects/' + id + '/send-setup-email'),
		cookies: {}
	} as Parameters<typeof POST>[0];
}

function session() {
	return { email: 'owner@example.com', expiresAt: Date.now() + 1000 };
}

type ClientOptions = {
	applicationStage: string | null;
	provision?: { status: string; administrator_user_id: string | null } | null;
	existingLink?: { consumed_at: string | null } | null;
};

function clientWith(options: ClientOptions) {
	return {
		from: (table: string) => {
			if (table === 'platform_onboarding_applications') {
				return {
					select: () => ({
						eq: () => ({
							maybeSingle: async () =>
								options.applicationStage === null
									? { data: null, error: null }
									: {
											data: {
												stage: options.applicationStage,
												business_name: 'Ridgeway Electric',
												main_contact_email: 'jordan@ridgeway.example',
												initial_administrator_email: null
											},
											error: null
										}
						})
					})
				};
			}
			if (table === 'platform_onboarding_application_provisions') {
				return {
					select: () => ({
						eq: () => ({
							maybeSingle: async () => ({ data: options.provision ?? null, error: null })
						})
					})
				};
			}
			if (table === 'platform_onboarding_application_setup_links') {
				return {
					select: () => ({
						eq: () => ({
							maybeSingle: async () => ({ data: options.existingLink ?? null, error: null })
						})
					})
				};
			}
			throw new Error(`unexpected table ${table}`);
		}
	};
}

describe('platform owner prospect setup-email send API boundary', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		mockedIssueSetupLink.mockResolvedValue({ sent: true });
	});

	it('rejects callers without the separate owner session', async () => {
		mockedOwnerSession.mockReturnValue(null);
		const response = await POST(event(prospectId));
		expect(response.status).toBe(401);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('validates the prospect identifier before database access', async () => {
		mockedOwnerSession.mockReturnValue(session());
		const response = await POST(event('not-a-uuid'));
		expect(response.status).toBe(422);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('returns 404 when the prospect does not exist', async () => {
		mockedOwnerSession.mockReturnValue(session());
		mockedClient.mockReturnValue(clientWith({ applicationStage: null }) as never);

		const response = await POST(event(prospectId));
		expect(response.status).toBe(404);
	});

	it('rejects when the application has not been provisioned', async () => {
		mockedOwnerSession.mockReturnValue(session());
		mockedClient.mockReturnValue(clientWith({ applicationStage: 'payment_confirmed' }) as never);

		const response = await POST(event(prospectId));
		expect(response.status).toBe(409);
		expect(mockedIssueSetupLink).not.toHaveBeenCalled();
	});

	it('rejects when no successful provision record exists', async () => {
		mockedOwnerSession.mockReturnValue(session());
		mockedClient.mockReturnValue(
			clientWith({
				applicationStage: 'account_created',
				provision: { status: 'failed', administrator_user_id: null }
			}) as never
		);

		const response = await POST(event(prospectId));
		expect(response.status).toBe(409);
		expect(mockedIssueSetupLink).not.toHaveBeenCalled();
	});

	it('rejects resending once the administrator has already completed setup', async () => {
		mockedOwnerSession.mockReturnValue(session());
		mockedClient.mockReturnValue(
			clientWith({
				applicationStage: 'account_created',
				provision: { status: 'succeeded', administrator_user_id: 'admin-user-id' },
				existingLink: { consumed_at: '2026-08-01T00:00:00Z' }
			}) as never
		);

		const response = await POST(event(prospectId));
		expect(response.status).toBe(409);
		expect(mockedIssueSetupLink).not.toHaveBeenCalled();
	});

	it('returns 502 when delivery fails', async () => {
		mockedOwnerSession.mockReturnValue(session());
		mockedClient.mockReturnValue(
			clientWith({
				applicationStage: 'account_created',
				provision: { status: 'succeeded', administrator_user_id: 'admin-user-id' },
				existingLink: null
			}) as never
		);
		mockedIssueSetupLink.mockResolvedValue({ sent: false, error: 'Brevo request failed' });

		const response = await POST(event(prospectId));
		expect(response.status).toBe(502);
	});

	it('sends the setup email on the happy path', async () => {
		mockedOwnerSession.mockReturnValue(session());
		const client = clientWith({
			applicationStage: 'account_created',
			provision: { status: 'succeeded', administrator_user_id: 'admin-user-id' },
			existingLink: { consumed_at: null }
		});
		mockedClient.mockReturnValue(client as never);

		const response = await POST(event(prospectId));
		expect(response.status).toBe(200);
		expect(mockedIssueSetupLink).toHaveBeenCalledWith(
			client,
			expect.objectContaining({
				applicationId: prospectId,
				administratorUserId: 'admin-user-id',
				intendedEmail: 'jordan@ridgeway.example',
				businessName: 'Ridgeway Electric'
			})
		);
	});
});
