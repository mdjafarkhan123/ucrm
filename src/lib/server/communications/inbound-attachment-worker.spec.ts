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
	provider_download_token: 'download-token-1'
};

function clientWithClaim(value: (typeof claimed)[] = []) {
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
		const download = vi.fn();
		const store = vi.fn();

		await expect(
			runCommunicationInboundAttachmentWorker({ client, download, store })
		).resolves.toEqual({ claimed: 0, imported: 0, failed: 0 });
		expect(download).not.toHaveBeenCalled();
	});

	it('downloads, stores, and finalizes a claimed attachment as pending_scan', async () => {
		const { client, rpc } = clientWithClaim([claimed]);
		const download = vi.fn().mockResolvedValue(new Uint8Array([1, 2, 3]));
		const store = vi.fn().mockResolvedValue(undefined);

		await expect(
			runCommunicationInboundAttachmentWorker({ client, download, store })
		).resolves.toEqual({ claimed: 1, imported: 1, failed: 0 });

		expect(download).toHaveBeenCalledWith('download-token-1');
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
				target_status: 'pending_scan'
			})
		);
	});

	it('finalizes as import_failed when the download rejects', async () => {
		const { client, rpc } = clientWithClaim([claimed]);
		const download = vi.fn().mockRejectedValue(new Error('Brevo rejected the request.'));
		const store = vi.fn();

		await expect(
			runCommunicationInboundAttachmentWorker({ client, download, store })
		).resolves.toEqual({ claimed: 1, imported: 0, failed: 1 });

		expect(store).not.toHaveBeenCalled();
		expect(rpc).toHaveBeenCalledWith(
			'finalize_communication_inbound_attachment_import',
			expect.objectContaining({
				target_attachment_id: 'attachment-1',
				target_status: 'import_failed',
				target_failure_reason: 'Brevo rejected the request.'
			})
		);
	});

	it('finalizes as import_failed when the downloaded bytes exceed the safe size ceiling', async () => {
		const { client, rpc } = clientWithClaim([claimed]);
		const download = vi.fn().mockResolvedValue(new Uint8Array(21 * 1024 * 1024));
		const store = vi.fn();

		await runCommunicationInboundAttachmentWorker({ client, download, store });

		expect(store).not.toHaveBeenCalled();
		expect(rpc).toHaveBeenCalledWith(
			'finalize_communication_inbound_attachment_import',
			expect.objectContaining({ target_status: 'import_failed' })
		);
	});
});
