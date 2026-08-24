import { beforeEach, describe, expect, it, vi } from 'vitest';
import type { Database } from '$lib/database.types';
import {
	BrevoManagementError,
	createBrevoSender,
	listBrevoSenders,
	updateBrevoSender
} from './brevo';
import {
	SenderCommandError,
	createCommunicationSender,
	updateCommunicationSender
} from './sender-commands';

vi.mock('./brevo', async (importOriginal) => ({
	...(await importOriginal<typeof import('./brevo')>()),
	createBrevoSender: vi.fn(),
	listBrevoSenders: vi.fn(),
	updateBrevoSender: vi.fn()
}));

type Sender = Database['public']['Tables']['communication_email_senders']['Row'];

const sender: Sender = {
	id: '123e4567-e89b-12d3-a456-426614174010',
	organization_id: '123e4567-e89b-12d3-a456-426614174000',
	domain_id: '123e4567-e89b-12d3-a456-426614174020',
	email_address: 'alex@mail.ridgeway.example',
	display_name: 'Alex | Ridgeway',
	provider: 'brevo',
	provider_sender_id: null,
	lifecycle_state: 'pending_verification',
	assigned_user_id: '123e4567-e89b-12d3-a456-426614174030',
	is_organization_default: true,
	allows_manual: true,
	allows_automated: false,
	restriction_reason: null,
	provider_cleanup_error: null,
	created_by: '123e4567-e89b-12d3-a456-426614174030',
	created_at: '2026-08-24T00:00:00.000Z',
	updated_at: '2026-08-24T00:00:00.000Z'
};

const createInput = {
	organizationId: sender.organization_id,
	actorUserId: sender.assigned_user_id!,
	domainId: sender.domain_id,
	emailAddress: sender.email_address,
	displayName: sender.display_name,
	assignedUserId: sender.assigned_user_id,
	isOrganizationDefault: true,
	allowsManual: true,
	allowsAutomated: false,
	idempotencyKey: '123e4567-e89b-12d3-a456-426614174040'
};

function clientWith(
	...results: Array<{ data: unknown; error: null | { code: string; message: string } }>
) {
	return { rpc: vi.fn().mockImplementation(() => Promise.resolve(results.shift())) };
}

describe('contractor communication sender commands', () => {
	beforeEach(() => vi.clearAllMocks());

	it('reconciles by exact provider email before creating and finalizes the stored claim', async () => {
		const enabled = { ...sender, lifecycle_state: 'enabled', provider_sender_id: 81 } as Sender;
		const client = clientWith(
			{ data: { replayed: false, sender }, error: null },
			{ data: enabled, error: null }
		);
		vi.mocked(listBrevoSenders).mockResolvedValue([]);
		vi.mocked(createBrevoSender).mockResolvedValue({ id: 81 });

		await expect(createCommunicationSender(client as never, createInput)).resolves.toEqual({
			sender: enabled,
			replayed: false
		});
		expect(listBrevoSenders).toHaveBeenCalledWith('mail.ridgeway.example');
		expect(createBrevoSender).toHaveBeenCalledWith({
			email: sender.email_address,
			name: sender.display_name
		});
		expect(client.rpc).toHaveBeenLastCalledWith(
			'finalize_communication_email_sender_create',
			expect.objectContaining({ provider_sender_id: 81 })
		);
	});

	it('returns an already completed replay without another provider request', async () => {
		const enabled = { ...sender, lifecycle_state: 'enabled', provider_sender_id: 81 } as Sender;
		const client = clientWith({ data: { replayed: true, sender: enabled }, error: null });

		await expect(createCommunicationSender(client as never, createInput)).resolves.toEqual({
			sender: enabled,
			replayed: true
		});
		expect(listBrevoSenders).not.toHaveBeenCalled();
		expect(createBrevoSender).not.toHaveBeenCalled();
	});

	it('keeps an ambiguous provider create retryable behind the persisted claim', async () => {
		const client = clientWith({ data: { replayed: false, sender }, error: null });
		vi.mocked(listBrevoSenders).mockRejectedValue(
			new BrevoManagementError('network', null, 'brevo_network_unknown')
		);

		await expect(createCommunicationSender(client as never, createInput)).rejects.toMatchObject({
			status: 502,
			reason: 'provider_unavailable'
		});
		expect(client.rpc).toHaveBeenCalledTimes(1);
	});

	it('updates the provider name before finalizing local sender settings', async () => {
		const current = { ...sender, lifecycle_state: 'enabled', provider_sender_id: 81 } as Sender;
		const changed = { ...current, display_name: 'Alex Updated', allows_automated: true } as Sender;
		const client = clientWith(
			{ data: { replayed: false, sender: current }, error: null },
			{ data: changed, error: null }
		);
		vi.mocked(listBrevoSenders).mockResolvedValue([
			{ id: 81, email: current.email_address, name: current.display_name, active: true }
		]);

		await expect(
			updateCommunicationSender(client as never, {
				...createInput,
				senderId: current.id,
				displayName: 'Alex Updated',
				enabled: true,
				allowsAutomated: true
			})
		).resolves.toEqual({ sender: changed, replayed: false });
		expect(updateBrevoSender).toHaveBeenCalledWith(81, { name: 'Alex Updated' });
	});

	it('turns database eligibility failures into a safe command error', async () => {
		const client = clientWith({
			data: null,
			error: { code: '23514', message: 'A verified healthy sending domain is required.' }
		});

		await expect(createCommunicationSender(client as never, createInput)).rejects.toBeInstanceOf(
			SenderCommandError
		);
	});
});
