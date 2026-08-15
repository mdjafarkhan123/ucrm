import { beforeEach, describe, expect, it, vi } from 'vitest';
import { sendAdministratorEmailRecoveryNotices } from './team-notifications';
import { enqueueEmailDelivery } from '$lib/server/events/dispatcher';

vi.mock('$lib/server/events/dispatcher', () => ({ enqueueEmailDelivery: vi.fn() }));

const mockedEnqueueEmail = vi.mocked(enqueueEmailDelivery);

const client = {} as never;

describe('sendAdministratorEmailRecoveryNotices', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		mockedEnqueueEmail.mockResolvedValue('delivery-1');
	});

	it('sends both the old and new address notices when the old email is known', async () => {
		await sendAdministratorEmailRecoveryNotices(client, {
			organizationId: 'org-1',
			userId: 'user-1',
			oldEmail: 'old@example.com',
			newEmail: 'new@example.com',
			businessName: 'Ridgeway Electric'
		});

		expect(mockedEnqueueEmail).toHaveBeenCalledTimes(2);
		expect(mockedEnqueueEmail).toHaveBeenCalledWith(
			client,
			expect.objectContaining({ recipientEmail: 'old@example.com' })
		);
		expect(mockedEnqueueEmail).toHaveBeenCalledWith(
			client,
			expect.objectContaining({ recipientEmail: 'new@example.com' })
		);
	});

	it('skips the old-address notice and still confirms the new address when the old email is unknown', async () => {
		await sendAdministratorEmailRecoveryNotices(client, {
			organizationId: 'org-1',
			userId: 'user-1',
			oldEmail: null,
			newEmail: 'new@example.com',
			businessName: 'Ridgeway Electric'
		});

		expect(mockedEnqueueEmail).toHaveBeenCalledTimes(1);
		expect(mockedEnqueueEmail).toHaveBeenCalledWith(
			client,
			expect.objectContaining({ recipientEmail: 'new@example.com' })
		);
	});
});
