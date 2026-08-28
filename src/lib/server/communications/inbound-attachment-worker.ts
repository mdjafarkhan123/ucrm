import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { downloadBrevoInboundAttachment } from './brevo';
import { INBOUND_ATTACHMENT_TOTAL_SIZE_BYTES } from './inbound-email';
import { buildInboundEmailAttachmentObjectKey, putObject } from '$lib/server/storage/r2';

type ClaimedInboundAttachment = {
	id: string;
	organization_id: string;
	inbound_message_id: string;
	file_name: string;
	mime_type: string;
	claim_token: string;
	provider_download_token: string | null;
};

type RpcResult<T> = Promise<{ data: T | null; error: { message: string } | null }>;

export type CommunicationWorkerClient = {
	rpc(name: string, args?: Record<string, unknown>): RpcResult<unknown>;
};

type WorkerDependencies = {
	client?: CommunicationWorkerClient;
	download?: (downloadToken: string) => Promise<Uint8Array>;
	store?: (objectKey: string, body: Uint8Array, mimeType: string) => Promise<void>;
};

export type CommunicationInboundAttachmentWorkerResult = {
	claimed: number;
	imported: number;
	failed: number;
};

function rpcError(action: string, error: { message: string } | null) {
	return new Error(`${action}: ${error?.message ?? 'The database returned no result.'}`);
}

export async function runCommunicationInboundAttachmentWorker(
	dependencies: WorkerDependencies = {}
): Promise<CommunicationInboundAttachmentWorkerResult> {
	const injectedClient = dependencies.client;
	const ownerClient = injectedClient ? null : getOwnerSupabaseClient();
	const client: CommunicationWorkerClient =
		injectedClient ?? (ownerClient as unknown as CommunicationWorkerClient);
	const download = dependencies.download ?? downloadBrevoInboundAttachment;
	const store = dependencies.store ?? putObject;

	const claimed = await client.rpc('claim_communication_inbound_attachment_imports', {
		batch_size: 20
	});
	if (claimed.error) throw rpcError('Could not claim inbound attachment imports', claimed.error);
	const attachments = Array.isArray(claimed.data)
		? (claimed.data as ClaimedInboundAttachment[])
		: [];

	let imported = 0;
	let failed = 0;

	for (const attachment of attachments) {
		let finalizeArgs: Record<string, unknown>;
		try {
			if (!attachment.provider_download_token)
				throw new Error('The claimed attachment has no provider download token.');

			const bytes = await download(attachment.provider_download_token);
			if (bytes.byteLength > INBOUND_ATTACHMENT_TOTAL_SIZE_BYTES)
				throw new Error('The downloaded attachment exceeds the safe size ceiling.');

			const objectKey = buildInboundEmailAttachmentObjectKey(
				attachment.organization_id,
				attachment.inbound_message_id,
				attachment.file_name
			);
			await store(objectKey, bytes, attachment.mime_type);

			finalizeArgs = {
				target_attachment_id: attachment.id,
				target_claim_token: attachment.claim_token,
				target_status: 'pending_scan',
				target_object_key: objectKey
			};
			imported += 1;
		} catch (error) {
			finalizeArgs = {
				target_attachment_id: attachment.id,
				target_claim_token: attachment.claim_token,
				target_status: 'import_failed',
				target_failure_reason:
					error instanceof Error
						? error.message
						: 'The attachment import failed for an unknown reason.'
			};
			failed += 1;
		}

		const finalized = await client.rpc(
			'finalize_communication_inbound_attachment_import',
			finalizeArgs
		);
		if (finalized.error)
			throw rpcError('Could not finalize an inbound attachment import', finalized.error);
	}

	return { claimed: attachments.length, imported, failed };
}
