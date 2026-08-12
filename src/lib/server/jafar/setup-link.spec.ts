import { beforeEach, describe, expect, it, vi } from 'vitest';
import { issueSetupLink } from './setup-link';
import { sendTransactionalEmail } from '$lib/server/email/brevo';
import { recordOperationOutcome, createOwnerNotification } from '$lib/server/events/outbox';

vi.mock('$lib/server/email/brevo', () => ({ sendTransactionalEmail: vi.fn() }));
vi.mock('$lib/server/events/outbox', () => ({
	recordOperationOutcome: vi.fn(),
	createOwnerNotification: vi.fn()
}));

const mockedSendEmail = vi.mocked(sendTransactionalEmail);
const mockedRecordOutcome = vi.mocked(recordOperationOutcome);
const mockedCreateNotification = vi.mocked(createOwnerNotification);

const DEFAULT_TEMPLATE = {
	subject_published: 'Set up your {{business_name}} administrator account',
	body_published:
		'<p>You\'ve been invited to administer <strong>{{business_name}}</strong>.</p><p><a href="{{setup_link}}">Set your password</a></p>'
};

function clientWith(templateRow: { subject_published: string | null; body_published: string | null } | null = DEFAULT_TEMPLATE) {
	const upsertCalls: unknown[] = [];
	const updateCalls: unknown[] = [];
	const upsert = vi.fn((payload: unknown) => {
		upsertCalls.push(payload);
		return Promise.resolve({ error: null as { message: string } | null });
	});
	const update = vi.fn((payload: unknown) => {
		updateCalls.push(payload);
		return { eq: vi.fn().mockResolvedValue({ error: null }) };
	});
	const maybeSingle = vi.fn().mockResolvedValue({ data: templateRow, error: null });

	return {
		from: (table: string) => {
			if (table === 'platform_onboarding_application_setup_links') return { upsert, update };
			if (table === 'platform_message_templates') {
				return { select: () => ({ eq: () => ({ maybeSingle }) }) };
			}
			throw new Error(`unexpected table ${table}`);
		},
		__upsertCalls: upsertCalls,
		__updateCalls: updateCalls,
		__upsert: upsert,
		__update: update
	};
}

const baseParams = {
	applicationId: 'app-1',
	administratorUserId: 'admin-1',
	intendedEmail: 'jordan@ridgeway.example',
	businessName: 'Ridgeway Electric',
	origin: 'http://localhost:5173'
};

describe('issueSetupLink', () => {
	beforeEach(() => {
		vi.clearAllMocks();
	});

	it('upserts a fresh 24-hour token keyed by application, sends the email, and records success', async () => {
		mockedSendEmail.mockResolvedValue(undefined);
		const client = clientWith();
		const before = Date.now();

		const result = await issueSetupLink(client as never, {
			...baseParams,
			actorEmail: 'owner@example.com'
		});

		expect(result).toEqual({ sent: true });
		expect(client.__upsert).toHaveBeenCalledWith(
			expect.objectContaining({
				application_id: 'app-1',
				administrator_user_id: 'admin-1',
				intended_email: 'jordan@ridgeway.example',
				consumed_at: null,
				last_error: null
			}),
			{ onConflict: 'application_id' }
		);
		const payload = client.__upsertCalls[0] as {
			expires_at: string;
			rendered_subject: string;
			rendered_body: string;
		};
		const expiresInMs = new Date(payload.expires_at).getTime() - before;
		expect(expiresInMs).toBeGreaterThan(23.9 * 60 * 60 * 1000);
		expect(expiresInMs).toBeLessThan(24.1 * 60 * 60 * 1000);

		expect(mockedSendEmail).toHaveBeenCalledWith(
			expect.objectContaining({
				to: { email: 'jordan@ridgeway.example' },
				subject: 'Set up your Ridgeway Electric administrator account',
				htmlContent: expect.stringContaining('Ridgeway Electric')
			})
		);
		const sentCall = mockedSendEmail.mock.calls[0][0];
		expect(sentCall.htmlContent).toContain('/setup-password?token=');
		expect(sentCall.textContent).not.toContain('<');
		expect(sentCall.textContent).toContain("You've been invited to administer Ridgeway Electric");
		expect(payload.rendered_subject).toBe(sentCall.subject);
		expect(payload.rendered_body).toBe(sentCall.htmlContent);
		expect(mockedRecordOutcome).toHaveBeenCalledWith(
			client,
			expect.objectContaining({ operationType: 'setup_email_delivery', success: true })
		);
		expect(mockedCreateNotification).not.toHaveBeenCalled();
	});

	it('throws before creating any link when the password setup template has not been published', async () => {
		const client = clientWith({ subject_published: null, body_published: null });

		await expect(issueSetupLink(client as never, baseParams)).rejects.toThrow(
			'has not been published yet'
		);
		expect(client.__upsert).not.toHaveBeenCalled();
		expect(mockedSendEmail).not.toHaveBeenCalled();
	});

	it('always stores the new token before attempting delivery, so a resend replaces the earlier link even if the send then fails', async () => {
		mockedSendEmail.mockRejectedValue(new Error('Brevo request failed with status 500: down'));
		const client = clientWith();

		const result = await issueSetupLink(client as never, baseParams);

		expect(result.sent).toBe(false);
		expect(client.__upsert).toHaveBeenCalledTimes(1);
		const upsertOrder = client.__upsert.mock.invocationCallOrder[0];
		const sendOrder = mockedSendEmail.mock.invocationCallOrder[0];
		expect(upsertOrder).toBeLessThan(sendOrder);
	});

	it('mints a different token on every call, proving a resend cannot reuse the previous link', async () => {
		mockedSendEmail.mockResolvedValue(undefined);
		const client = clientWith();

		await issueSetupLink(client as never, baseParams);
		await issueSetupLink(client as never, baseParams);

		const [firstHash, secondHash] = client.__upsertCalls.map(
			(payload) => (payload as { token_hash: string }).token_hash
		);
		expect(firstHash).not.toEqual(secondHash);
	});

	it('records the failure, marks the link row, and raises an urgent owner notification when Brevo delivery fails', async () => {
		mockedSendEmail.mockRejectedValue(
			new Error('Brevo request failed with status 500: server error')
		);
		const client = clientWith();

		const result = await issueSetupLink(client as never, {
			...baseParams,
			actorEmail: 'owner@example.com'
		});

		expect(result).toEqual({
			sent: false,
			error: 'Brevo request failed with status 500: server error'
		});
		expect(client.__update).toHaveBeenCalledWith({
			last_error: 'Brevo request failed with status 500: server error'
		});
		expect(mockedRecordOutcome).toHaveBeenCalledWith(
			client,
			expect.objectContaining({
				operationType: 'setup_email_delivery',
				success: false,
				error: 'Brevo request failed with status 500: server error',
				actorEmail: 'owner@example.com'
			})
		);
		expect(mockedCreateNotification).toHaveBeenCalledWith(
			client,
			expect.objectContaining({
				kind: 'setup_email_failed',
				severity: 'urgent',
				target: { targetKind: 'onboarding_application', targetId: 'app-1' }
			})
		);
	});

	it('propagates a failed upsert without attempting delivery', async () => {
		const client = clientWith();
		client.__upsert.mockResolvedValueOnce({ error: { message: 'db down' } });

		await expect(issueSetupLink(client as never, baseParams)).rejects.toBeTruthy();
		expect(mockedSendEmail).not.toHaveBeenCalled();
	});
});
