import { describe, expect, it, vi } from 'vitest';
import { OperationalEmailSubmissionError } from './brevo';
import { runCommunicationEmailWorker, type CommunicationWorkerClient } from './email-worker';

const claim = {
	outbox_event_id: 'outbox-1',
	delivery_intent_id: 'intent-1',
	claim_token: 'claim-1',
	recipient_email: 'customer@example.com',
	subject: 'Your job update',
	html_content: '<p>Your job is scheduled.</p>',
	text_content: 'Your job is scheduled.',
	logical_send_key: 'job-update-1',
	sender_id: 'sender-1',
	sender_email: 'service@mail.ridgeway.example',
	sender_name: 'Ridgeway'
};

function clientWithClaim(
	value: typeof claim | undefined,
	stale = 0,
	attachments: {
		file_name: string;
		mime_type: string;
		byte_size: number;
		object_key: string;
	}[] = []
) {
	const rpc = vi.fn(async (name: string) => {
		if (name === 'quarantine_stale_communication_claims') return { data: stale, error: null };
		if (name === 'claim_communication_outbox_event')
			return { data: value ? [value] : [], error: null };
		if (name === 'list_communication_outbound_attachments')
			return { data: attachments, error: null };
		if (name === 'finalize_communication_outbox_event')
			return { data: [{ outbox_status: 'submitted' }], error: null };
		return { data: null, error: { message: 'Unexpected RPC.' } };
	});
	return { client: { rpc } as CommunicationWorkerClient, rpc };
}

describe('communication email worker service', () => {
	it('quarantines stale claims and exits without sending when the queue is empty', async () => {
		const { client } = clientWithClaim(undefined, 2);
		const send = vi.fn();

		await expect(runCommunicationEmailWorker({ client, send })).resolves.toEqual({
			status: 'idle',
			staleClaimsQuarantined: 2
		});
		expect(send).not.toHaveBeenCalled();
	});

	it('submits one claimed intent and finalizes it with the same lease', async () => {
		const { client, rpc } = clientWithClaim(claim);
		const send = vi.fn().mockResolvedValue({ messageId: 'provider-message-1' });

		await expect(runCommunicationEmailWorker({ client, send })).resolves.toEqual({
			status: 'submitted',
			intentId: 'intent-1',
			staleClaimsQuarantined: 0
		});
		expect(send).toHaveBeenCalledWith(
			expect.objectContaining({
				from: { email: claim.sender_email, name: claim.sender_name },
				intentId: 'intent-1'
			})
		);
		expect(rpc).toHaveBeenCalledWith(
			'finalize_communication_outbox_event',
			expect.objectContaining({
				target_outbox_event_id: 'outbox-1',
				target_claim_token: 'claim-1',
				target_outcome: 'submitted',
				target_provider_message_id: 'provider-message-1'
			})
		);
	});

	it('reads each listed attachment and hands Brevo base64 content', async () => {
		const attachmentRow = {
			file_name: 'quote.pdf',
			mime_type: 'application/pdf',
			byte_size: 4,
			object_key: 'org-1/outbound-email-attachments/i/quote.pdf'
		};
		const { client } = clientWithClaim(claim, 0, [attachmentRow]);
		const send = vi.fn().mockResolvedValue({ messageId: 'provider-message-1' });
		const readAttachment = vi.fn().mockResolvedValue(new Uint8Array([1, 2, 3, 4]));

		await expect(
			runCommunicationEmailWorker({ client, send, readAttachment })
		).resolves.toMatchObject({ status: 'submitted' });

		expect(readAttachment).toHaveBeenCalledWith(attachmentRow.object_key);
		expect(send).toHaveBeenCalledWith(
			expect.objectContaining({
				attachments: [{ name: 'quote.pdf', content: Buffer.from([1, 2, 3, 4]).toString('base64') }]
			})
		);
	});

	it('sends with an empty attachment list when the intent has no attachments', async () => {
		const { client } = clientWithClaim(claim);
		const send = vi.fn().mockResolvedValue({ messageId: 'provider-message-1' });

		await runCommunicationEmailWorker({ client, send });

		expect(send).toHaveBeenCalledWith(expect.objectContaining({ attachments: [] }));
	});

	it.each([
		['retry', 'brevo_http_503'],
		['cancelled', 'brevo_http_400'],
		['submission_unknown', 'brevo_network_unknown']
	] as const)('records a %s provider outcome without a second send', async (outcome, code) => {
		const { client, rpc } = clientWithClaim(claim);
		const send = vi
			.fn()
			.mockRejectedValue(new OperationalEmailSubmissionError('Provider outcome.', outcome, code));

		await expect(runCommunicationEmailWorker({ client, send })).resolves.toMatchObject({
			status: outcome,
			intentId: 'intent-1'
		});
		expect(send).toHaveBeenCalledTimes(1);
		expect(rpc).toHaveBeenCalledWith(
			'finalize_communication_outbox_event',
			expect.objectContaining({ target_outcome: outcome, target_failure_code: code })
		);
	});
});
