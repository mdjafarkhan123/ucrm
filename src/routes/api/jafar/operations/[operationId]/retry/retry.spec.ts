import { beforeEach, describe, expect, it, vi } from 'vitest';
import { POST } from './+server';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { issueSetupLink } from '$lib/server/jafar/setup-link';
import { dispatchOutboxDelivery } from '$lib/server/events/dispatcher';

vi.mock('$lib/server/auth/owner', () => ({ getOwnerSession: vi.fn() }));
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));
vi.mock('$lib/server/jafar/setup-link', () => ({ issueSetupLink: vi.fn() }));
vi.mock('$lib/server/events/dispatcher', () => ({ dispatchOutboxDelivery: vi.fn() }));

const mockedOwnerSession = vi.mocked(getOwnerSession);
const mockedClient = vi.mocked(getOwnerSupabaseClient);
const mockedIssueSetupLink = vi.mocked(issueSetupLink);
const mockedDispatchOutboxDelivery = vi.mocked(dispatchOutboxDelivery);

const operationId = '123e4567-e89b-12d3-a456-426614174000';
const applicationId = '223e4567-e89b-12d3-a456-426614174000';

function event(id: string) {
	return {
		params: { operationId: id },
		url: new URL('http://localhost/api/jafar/operations/' + id + '/retry'),
		cookies: {}
	} as Parameters<typeof POST>[0];
}

function session() {
	return { email: 'owner@example.com', expiresAt: Date.now() + 1000 };
}

function single(data: unknown, error: null | { message: string } = null) {
	return { maybeSingle: () => Promise.resolve({ data, error }) };
}

function clientWith(tables: Record<string, unknown>) {
	return { from: (table: string) => (tables[table] as { select: () => unknown }) };
}

function attemptTable(data: unknown, error: null | { message: string } = null) {
	return { select: () => ({ eq: () => single(data, error) }) };
}

describe('platform owner operation retry API boundary', () => {
	beforeEach(() => vi.clearAllMocks());

	it('rejects callers without the separate owner session', async () => {
		mockedOwnerSession.mockReturnValue(null);
		const response = await POST(event(operationId));
		expect(response.status).toBe(401);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('rejects an invalid operation identifier', async () => {
		mockedOwnerSession.mockReturnValue(session());
		const response = await POST(event('not-a-uuid'));
		expect(response.status).toBe(422);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('returns 404 when the operation does not exist', async () => {
		mockedOwnerSession.mockReturnValue(session());
		mockedClient.mockReturnValue(
			clientWith({ platform_operation_attempts: attemptTable(null) }) as never
		);

		const response = await POST(event(operationId));
		expect(response.status).toBe(404);
	});

	it('rejects retrying an operation that is not open for retry', async () => {
		mockedOwnerSession.mockReturnValue(session());
		mockedClient.mockReturnValue(
			clientWith({
				platform_operation_attempts: attemptTable({
					operation_type: 'outbox_email_delivery',
					target_id: null,
					idempotency_key: 'delivery-1',
					status: 'succeeded'
				})
			}) as never
		);

		const response = await POST(event(operationId));
		expect(response.status).toBe(409);
		expect(mockedDispatchOutboxDelivery).not.toHaveBeenCalled();
	});

	it('retries a queued outbox email delivery directly', async () => {
		mockedOwnerSession.mockReturnValue(session());
		mockedClient.mockReturnValue(
			clientWith({
				platform_operation_attempts: attemptTable({
					operation_type: 'outbox_email_delivery',
					target_id: null,
					idempotency_key: 'delivery-1',
					status: 'retrying'
				})
			}) as never
		);
		mockedDispatchOutboxDelivery.mockResolvedValue(undefined);

		const response = await POST(event(operationId));
		expect(response.status).toBe(200);
		expect(mockedDispatchOutboxDelivery).toHaveBeenCalledWith(expect.anything(), 'delivery-1');
	});

	it('rejects a setup email retry with no linked application', async () => {
		mockedOwnerSession.mockReturnValue(session());
		mockedClient.mockReturnValue(
			clientWith({
				platform_operation_attempts: attemptTable({
					operation_type: 'setup_email_delivery',
					target_id: null,
					idempotency_key: 'setup-1',
					status: 'retrying'
				})
			}) as never
		);

		const response = await POST(event(operationId));
		expect(response.status).toBe(409);
		expect(mockedIssueSetupLink).not.toHaveBeenCalled();
	});

	it('returns 404 when the linked application no longer exists', async () => {
		mockedOwnerSession.mockReturnValue(session());
		mockedClient.mockReturnValue(
			clientWith({
				platform_operation_attempts: attemptTable({
					operation_type: 'setup_email_delivery',
					target_id: applicationId,
					idempotency_key: 'setup-1',
					status: 'retrying'
				}),
				platform_onboarding_applications: attemptTable(null)
			}) as never
		);

		const response = await POST(event(operationId));
		expect(response.status).toBe(404);
	});

	it('rejects a setup email retry with no provisioned administrator', async () => {
		mockedOwnerSession.mockReturnValue(session());
		mockedClient.mockReturnValue(
			clientWith({
				platform_operation_attempts: attemptTable({
					operation_type: 'setup_email_delivery',
					target_id: applicationId,
					idempotency_key: 'setup-1',
					status: 'retrying'
				}),
				platform_onboarding_applications: attemptTable({
					business_name: 'Bright Co',
					main_contact_email: 'contact@example.com',
					initial_administrator_email: null
				}),
				platform_onboarding_application_provisions: attemptTable(null)
			}) as never
		);

		const response = await POST(event(operationId));
		expect(response.status).toBe(409);
		expect(mockedIssueSetupLink).not.toHaveBeenCalled();
	});

	it('re-sends the setup email for a provisioned application', async () => {
		mockedOwnerSession.mockReturnValue(session());
		mockedClient.mockReturnValue(
			clientWith({
				platform_operation_attempts: attemptTable({
					operation_type: 'setup_email_delivery',
					target_id: applicationId,
					idempotency_key: 'setup-1',
					status: 'retrying'
				}),
				platform_onboarding_applications: attemptTable({
					business_name: 'Bright Co',
					main_contact_email: 'contact@example.com',
					initial_administrator_email: 'admin@example.com'
				}),
				platform_onboarding_application_provisions: attemptTable({
					administrator_user_id: 'user-1'
				})
			}) as never
		);
		mockedIssueSetupLink.mockResolvedValue({ sent: true });

		const response = await POST(event(operationId));
		expect(response.status).toBe(200);
		expect(mockedIssueSetupLink).toHaveBeenCalledWith(
			expect.anything(),
			expect.objectContaining({
				applicationId,
				administratorUserId: 'user-1',
				intendedEmail: 'admin@example.com',
				actorEmail: 'owner@example.com'
			})
		);
	});

	it('returns 502 when the setup email retry still fails to send', async () => {
		mockedOwnerSession.mockReturnValue(session());
		mockedClient.mockReturnValue(
			clientWith({
				platform_operation_attempts: attemptTable({
					operation_type: 'setup_email_delivery',
					target_id: applicationId,
					idempotency_key: 'setup-1',
					status: 'retrying'
				}),
				platform_onboarding_applications: attemptTable({
					business_name: 'Bright Co',
					main_contact_email: 'contact@example.com',
					initial_administrator_email: 'admin@example.com'
				}),
				platform_onboarding_application_provisions: attemptTable({
					administrator_user_id: 'user-1'
				})
			}) as never
		);
		mockedIssueSetupLink.mockResolvedValue({ sent: false, error: 'Brevo is unavailable.' });

		const response = await POST(event(operationId));
		expect(response.status).toBe(502);
	});

	it('rejects retrying an operation type that has its own screen', async () => {
		mockedOwnerSession.mockReturnValue(session());
		mockedClient.mockReturnValue(
			clientWith({
				platform_operation_attempts: attemptTable({
					operation_type: 'onboarding_application_provisioning',
					target_id: applicationId,
					idempotency_key: applicationId,
					status: 'retrying'
				})
			}) as never
		);

		const response = await POST(event(operationId));
		expect(response.status).toBe(409);
	});

	it('returns a safe server error when the lookup fails', async () => {
		mockedOwnerSession.mockReturnValue(session());
		mockedClient.mockReturnValue(
			clientWith({
				platform_operation_attempts: attemptTable(null, { message: 'internal database details' })
			}) as never
		);

		const response = await POST(event(operationId));
		expect(response.status).toBe(500);
		expect(await response.json()).toEqual({ error: 'The operation could not be retried.' });
	});
});
