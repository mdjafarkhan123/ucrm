import { describe, expect, it, vi } from 'vitest';
import { OperationalEmailSubmissionError } from './brevo';
import {
	runCommunicationForwardWorker,
	type CommunicationForwardWorkerClient
} from './forward-worker';

const forward = {
	forward_event_id: 'forward-1',
	claim_token: 'claim-1',
	recipient_emails: ['colleague@example.com'],
	subject: 'Fwd: Your job update',
	html_content: '<p>Forwarded.</p>',
	text_content: 'Forwarded.',
	sender_id: 'sender-1',
	sender_email: 'service@mail.ridgeway.example',
	sender_name: 'Ridgeway'
};

function clientWithClaim(
	value: typeof forward | undefined,
	stale = 0,
	forwardAttachmentRows: { inbound_attachment_id: string }[] = [],
	inboundAttachmentRows: {
		id: string;
		file_name: string;
		mime_type: string;
		byte_size: number;
		object_key: string | null;
	}[] = []
) {
	const rpc = vi.fn(async (name: string) => {
		if (name === 'quarantine_stale_communication_forward_claims')
			return { data: stale, error: null };
		if (name === 'claim_communication_forward_event')
			return { data: value ? [value] : [], error: null };
		if (name === 'finalize_communication_forward_event')
			return { data: [{ status: 'submitted' }], error: null };
		return { data: null, error: { message: 'Unexpected RPC.' } };
	});
	const from = vi.fn((table: string) => ({
		select: (_columns: string) => ({
			eq: async (_column: string, _value: string) => {
				if (table === 'communication_forward_attachments')
					return { data: forwardAttachmentRows, error: null };
				return { data: null, error: { message: 'Unexpected eq() call.' } };
			},
			in: async (_column: string, _values: string[]) => {
				if (table === 'communication_inbound_attachments')
					return { data: inboundAttachmentRows, error: null };
				return { data: null, error: { message: 'Unexpected in() call.' } };
			}
		})
	}));
	return { client: { rpc, from } as CommunicationForwardWorkerClient, rpc, from };
}

describe('communication forward worker service', () => {
	it('quarantines stale claims and exits without sending when the queue is empty', async () => {
		const { client } = clientWithClaim(undefined, 3);
		const send = vi.fn();

		await expect(runCommunicationForwardWorker({ client, send })).resolves.toEqual({
			status: 'idle',
			staleClaimsQuarantined: 3
		});
		expect(send).not.toHaveBeenCalled();
	});

	it('submits one claimed forward to every recipient and finalizes it with the same lease', async () => {
		const { client, rpc } = clientWithClaim(forward);
		const send = vi.fn().mockResolvedValue({ messageId: 'provider-message-1' });

		await expect(runCommunicationForwardWorker({ client, send })).resolves.toEqual({
			status: 'submitted',
			forwardEventId: 'forward-1',
			staleClaimsQuarantined: 0
		});
		expect(send).toHaveBeenCalledWith(
			expect.objectContaining({
				from: { email: forward.sender_email, name: forward.sender_name },
				to: [{ email: 'colleague@example.com' }],
				intentId: 'forward-1'
			})
		);
		expect(rpc).toHaveBeenCalledWith(
			'finalize_communication_forward_event',
			expect.objectContaining({
				target_forward_event_id: 'forward-1',
				target_claim_token: 'claim-1',
				target_outcome: 'submitted',
				target_provider_message_id: 'provider-message-1'
			})
		);
	});

	it('reads each attached inbound file and hands Brevo base64 content', async () => {
		const attachmentRow = {
			id: 'attachment-1',
			file_name: 'photo.jpg',
			mime_type: 'image/jpeg',
			byte_size: 4,
			object_key: 'org-1/inbound-attachments/i/photo.jpg'
		};
		const { client } = clientWithClaim(
			forward,
			0,
			[{ inbound_attachment_id: 'attachment-1' }],
			[attachmentRow]
		);
		const send = vi.fn().mockResolvedValue({ messageId: 'provider-message-1' });
		const readAttachment = vi.fn().mockResolvedValue(new Uint8Array([1, 2, 3, 4]));

		await expect(
			runCommunicationForwardWorker({ client, send, readAttachment })
		).resolves.toMatchObject({ status: 'submitted' });

		expect(readAttachment).toHaveBeenCalledWith(attachmentRow.object_key);
		expect(send).toHaveBeenCalledWith(
			expect.objectContaining({
				attachments: [{ name: 'photo.jpg', content: Buffer.from([1, 2, 3, 4]).toString('base64') }]
			})
		);
	});

	it('sends with an empty attachment list when the forward has none', async () => {
		const { client } = clientWithClaim(forward);
		const send = vi.fn().mockResolvedValue({ messageId: 'provider-message-1' });

		await runCommunicationForwardWorker({ client, send });

		expect(send).toHaveBeenCalledWith(expect.objectContaining({ attachments: [] }));
	});

	it.each([
		['retry', 'brevo_http_503'],
		['cancelled', 'brevo_http_400'],
		['submission_unknown', 'brevo_network_unknown']
	] as const)('records a %s provider outcome without a second send', async (outcome, code) => {
		const { client, rpc } = clientWithClaim(forward);
		const send = vi
			.fn()
			.mockRejectedValue(new OperationalEmailSubmissionError('Provider outcome.', outcome, code));

		await expect(runCommunicationForwardWorker({ client, send })).resolves.toMatchObject({
			status: outcome,
			forwardEventId: 'forward-1'
		});
		expect(send).toHaveBeenCalledTimes(1);
		expect(rpc).toHaveBeenCalledWith(
			'finalize_communication_forward_event',
			expect.objectContaining({ target_outcome: outcome, target_failure_code: code })
		);
	});
});
