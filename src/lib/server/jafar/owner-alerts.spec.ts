import { beforeEach, describe, expect, it, vi } from 'vitest';
import { raiseOwnerAlert } from './owner-alerts';
import { createOwnerNotification } from '$lib/server/events/outbox';
import { enqueueEmailDelivery } from '$lib/server/events/dispatcher';
import { getOrCreateOwnerSettings } from '$lib/server/jafar/owner-settings';

vi.mock('$lib/server/events/outbox', () => ({ createOwnerNotification: vi.fn() }));
vi.mock('$lib/server/events/dispatcher', () => ({ enqueueEmailDelivery: vi.fn() }));
vi.mock('$lib/server/jafar/owner-settings', () => ({ getOrCreateOwnerSettings: vi.fn() }));

const mockedCreateNotification = vi.mocked(createOwnerNotification);
const mockedEnqueueEmail = vi.mocked(enqueueEmailDelivery);
const mockedSettings = vi.mocked(getOrCreateOwnerSettings);

const client = {} as never;

const applicationAlert = {
	kind: 'onboarding_application_submitted',
	severity: 'attention' as const,
	title: 'New application from Ridgeway Roofing',
	body: 'Jordan Ridgeway applied for Roofing in Austin, USA.',
	target: { targetKind: 'onboarding_application' as const, targetId: 'app-42' },
	origin: 'https://crm.example'
};

function settingsWith(recipients: string[]) {
	return {
		privacy_policy_url: null,
		privacy_policy_version: 'v1',
		payment_instructions: null,
		sender_display_name: 'UpliftContractor',
		reply_to_address: 'owner@example.com',
		alert_recipient_emails: recipients,
		updated_at: '2026-08-13T00:00:00Z'
	};
}

describe('raiseOwnerAlert', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		mockedCreateNotification.mockResolvedValue('notification-1');
		mockedSettings.mockResolvedValue(settingsWith(['owner@example.com']) as never);
		mockedEnqueueEmail.mockResolvedValue('delivery-1');
	});

	it('always records the in-app notification, whatever the kind', async () => {
		await raiseOwnerAlert(client, {
			kind: 'organization_suspended',
			severity: 'info',
			title: 'Ridgeway Roofing was suspended',
			target: { targetKind: 'organization', targetId: 'org-1' }
		});

		expect(mockedCreateNotification).toHaveBeenCalledWith(
			client,
			expect.objectContaining({ kind: 'organization_suspended', severity: 'info' })
		);
	});

	it('leaves routine events in-app only, with no email and no settings read', async () => {
		await raiseOwnerAlert(client, {
			kind: 'organization_suspended',
			severity: 'info',
			title: 'Ridgeway Roofing was suspended',
			target: { targetKind: 'organization', targetId: 'org-1' }
		});

		expect(mockedEnqueueEmail).not.toHaveBeenCalled();
		expect(mockedSettings).not.toHaveBeenCalled();
	});

	it('queues one email per alert recipient for an email-worthy kind', async () => {
		mockedSettings.mockResolvedValue(
			settingsWith(['owner@example.com', 'backup@example.com']) as never
		);

		await raiseOwnerAlert(client, applicationAlert);

		expect(mockedEnqueueEmail).toHaveBeenCalledTimes(2);
		const recipients = mockedEnqueueEmail.mock.calls.map((call) => call[1].recipientEmail);
		expect(recipients).toEqual(['owner@example.com', 'backup@example.com']);
	});

	it('keys each email on the notification id and recipient, so a repeat send cannot duplicate it', async () => {
		mockedSettings.mockResolvedValue(
			settingsWith(['owner@example.com', 'backup@example.com']) as never
		);

		await raiseOwnerAlert(client, applicationAlert);

		const keys = mockedEnqueueEmail.mock.calls.map((call) => call[1].idempotencyKey);
		expect(keys).toEqual([
			'owner_alert:notification-1:owner@example.com',
			'owner_alert:notification-1:backup@example.com'
		]);
	});

	it('links straight to the record in the Control Room and carries no sensitive detail', async () => {
		await raiseOwnerAlert(client, applicationAlert);

		const email = mockedEnqueueEmail.mock.calls[0][1];
		expect(email.subject).toBe('Action needed: New application from Ridgeway Roofing');
		expect(email.htmlContent).toContain('https://crm.example/jafar/prospects?application=app-42');
		expect(email.textContent).toContain('Jordan Ridgeway applied for Roofing');
		expect(email.textContent).not.toContain('token');
		expect(email.textContent).not.toContain('password');
	});

	it('files an operations-target alert against the platform, since the outbox has no such target', async () => {
		await raiseOwnerAlert(client, {
			kind: 'setup_email_failed',
			severity: 'urgent',
			title: 'Setup email failed for Ridgeway Roofing',
			target: { targetKind: 'operation_attempt', targetId: 'attempt-1' }
		});

		expect(mockedEnqueueEmail.mock.calls[0][1].target).toEqual({
			targetKind: 'platform',
			targetId: null
		});
	});

	it('keeps going for the remaining recipients when one address cannot be queued', async () => {
		mockedSettings.mockResolvedValue(
			settingsWith(['broken@example.com', 'owner@example.com']) as never
		);
		mockedEnqueueEmail.mockRejectedValueOnce(new Error('Brevo rejected the address'));

		await expect(raiseOwnerAlert(client, applicationAlert)).resolves.toBe('notification-1');
		expect(mockedEnqueueEmail).toHaveBeenCalledTimes(2);
	});

	it('records the notification even when no alert address is configured', async () => {
		mockedSettings.mockResolvedValue(settingsWith([]) as never);

		await raiseOwnerAlert(client, applicationAlert);

		expect(mockedCreateNotification).toHaveBeenCalled();
		expect(mockedEnqueueEmail).not.toHaveBeenCalled();
	});
});
