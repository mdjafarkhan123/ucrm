import { describe, expect, it, vi } from 'vitest';
import {
	runCommunicationInboundAttachmentWorker,
	type CommunicationWorkerClient
} from './inbound-attachment-worker';

const claimed = {
	id: 'attachment-1',
	organization_id: 'org-1',
	inbound_message_id: 'message-1',
	file_name: 'estimate.pdf',
	mime_type: 'application/pdf',
	claim_token: 'claim-1',
	provider: 'ses',
	provider_download_token: 'org-1/ses-msg-1#0'
};

const claimedTwilio = {
	id: 'attachment-2',
	organization_id: 'org-1',
	inbound_message_id: 'message-2',
	file_name: 'mms-1.jpg',
	mime_type: 'image/jpeg',
	claim_token: 'claim-2',
	provider: 'twilio',
	provider_download_token: 'https://api.twilio.com/2010-04-01/Accounts/AC1/Messages/MM1/Media/ME1'
};

const claimedSes = {
	id: 'attachment-3',
	organization_id: 'org-1',
	inbound_message_id: 'message-3',
	file_name: 'photo.jpg',
	mime_type: 'image/jpeg',
	claim_token: 'claim-3',
	provider: 'ses',
	provider_download_token: 'org-1/ses-msg-1#0'
};

function clientWithClaim(
	value: (typeof claimed | typeof claimedTwilio | typeof claimedSes)[] = []
) {
	const rpc = vi.fn(async (name: string) => {
		if (name === 'claim_communication_inbound_attachment_imports')
			return { data: value, error: null };
		if (name === 'finalize_communication_inbound_attachment_import')
			return { data: { status: 'pending_scan' }, error: null };
		return { data: null, error: { message: 'Unexpected RPC.' } };
	});
	return { client: { rpc } as CommunicationWorkerClient, rpc };
}

describe('communication inbound attachment worker service', () => {
	it('claims nothing and imports nothing when the queue is empty', async () => {
		const { client } = clientWithClaim([]);
		const downloadSesAttachment = vi.fn();
		const store = vi.fn();

		await expect(
			runCommunicationInboundAttachmentWorker({ client, downloadSesAttachment, store })
		).resolves.toEqual({ claimed: 0, imported: 0, failed: 0 });
		expect(downloadSesAttachment).not.toHaveBeenCalled();
	});

	it('downloads an SES attachment, stores it, and finalizes it as pending_scan', async () => {
		const { client, rpc } = clientWithClaim([claimed]);
		const downloadSesAttachment = vi.fn().mockResolvedValue(new Uint8Array([1, 2, 3]));
		const store = vi.fn().mockResolvedValue(undefined);

		await expect(
			runCommunicationInboundAttachmentWorker({ client, downloadSesAttachment, store })
		).resolves.toEqual({ claimed: 1, imported: 1, failed: 0 });

		expect(downloadSesAttachment).toHaveBeenCalledWith('org-1/ses-msg-1#0');
		expect(store).toHaveBeenCalledWith(
			expect.stringContaining('org-1/inbound-email-attachments/message-1/'),
			expect.any(Uint8Array),
			'application/pdf'
		);
		expect(rpc).toHaveBeenCalledWith(
			'finalize_communication_inbound_attachment_import',
			expect.objectContaining({
				target_attachment_id: 'attachment-1',
				target_claim_token: 'claim-1',
				target_status: 'pending_scan',
				target_byte_size: 3
			})
		);
	});

	it('downloads a twilio MMS attachment through the twilio-branch dependency and its own object key prefix', async () => {
		const { client, rpc } = clientWithClaim([claimedTwilio]);
		const downloadSesAttachment = vi.fn();
		const downloadTwilioMedia = vi.fn().mockResolvedValue(new Uint8Array([1, 2, 3, 4]));
		const store = vi.fn().mockResolvedValue(undefined);

		await expect(
			runCommunicationInboundAttachmentWorker({
				client,
				downloadSesAttachment,
				downloadTwilioMedia,
				store
			})
		).resolves.toEqual({ claimed: 1, imported: 1, failed: 0 });

		expect(downloadSesAttachment).not.toHaveBeenCalled();
		expect(downloadTwilioMedia).toHaveBeenCalledWith(
			claimedTwilio.provider_download_token,
			'org-1'
		);
		expect(store).toHaveBeenCalledWith(
			expect.stringContaining('org-1/inbound-sms-attachments/message-2/'),
			expect.any(Uint8Array),
			'image/jpeg'
		);
		expect(rpc).toHaveBeenCalledWith(
			'finalize_communication_inbound_attachment_import',
			expect.objectContaining({
				target_attachment_id: 'attachment-2',
				target_claim_token: 'claim-2',
				target_status: 'pending_scan',
				target_byte_size: 4
			})
		);
	});

	it('finalizes as import_failed when the download rejects', async () => {
		const { client, rpc } = clientWithClaim([claimed]);
		const downloadSesAttachment = vi
			.fn()
			.mockRejectedValue(new Error('Amazon S3 rejected the request.'));
		const store = vi.fn();

		await expect(
			runCommunicationInboundAttachmentWorker({ client, downloadSesAttachment, store })
		).resolves.toEqual({ claimed: 1, imported: 0, failed: 1 });

		expect(store).not.toHaveBeenCalled();
		expect(rpc).toHaveBeenCalledWith(
			'finalize_communication_inbound_attachment_import',
			expect.objectContaining({
				target_attachment_id: 'attachment-1',
				target_status: 'import_failed',
				target_failure_reason: 'Amazon S3 rejected the request.'
			})
		);
	});

	it('finalizes as import_failed when the downloaded bytes exceed the safe size ceiling', async () => {
		const { client, rpc } = clientWithClaim([claimed]);
		const downloadSesAttachment = vi.fn().mockResolvedValue(new Uint8Array(21 * 1024 * 1024));
		const store = vi.fn();

		await runCommunicationInboundAttachmentWorker({ client, downloadSesAttachment, store });

		expect(store).not.toHaveBeenCalled();
		expect(rpc).toHaveBeenCalledWith(
			'finalize_communication_inbound_attachment_import',
			expect.objectContaining({ target_status: 'import_failed' })
		);
	});

	it('refuses an attachment from an unsupported provider', async () => {
		const { client, rpc } = clientWithClaim([{ ...claimed, provider: 'unknown' }]);
		const downloadSesAttachment = vi.fn();
		const store = vi.fn();

		await expect(
			runCommunicationInboundAttachmentWorker({ client, downloadSesAttachment, store })
		).resolves.toEqual({ claimed: 1, imported: 0, failed: 1 });

		expect(downloadSesAttachment).not.toHaveBeenCalled();
		expect(rpc).toHaveBeenCalledWith(
			'finalize_communication_inbound_attachment_import',
			expect.objectContaining({ target_status: 'import_failed' })
		);
	});
});
