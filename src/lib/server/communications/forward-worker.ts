import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { getObjectBytes } from '$lib/server/storage/r2';
import {
	OperationalEmailSubmissionError,
	sendOperationalEmail,
	type OperationalEmail
} from './brevo';
import { runBoundedDrain, type BoundedDrainOptions, type BoundedDrainResult } from './drain';

type ClaimedForward = {
	forward_event_id: string;
	claim_token: string;
	recipient_emails: string[];
	subject: string;
	html_content: string;
	text_content: string;
	sender_id: string;
	sender_email: string;
	sender_name: string;
};

type ForwardAttachmentRow = {
	inbound_attachment_id: string;
};

type InboundAttachmentRow = {
	id: string;
	file_name: string;
	mime_type: string;
	byte_size: number;
	object_key: string | null;
};

type RpcResult<T> = Promise<{ data: T | null; error: { message: string } | null }>;
type SelectResult<T> = Promise<{ data: T[] | null; error: { message: string } | null }>;

export type CommunicationForwardWorkerClient = {
	rpc(name: string, args?: Record<string, unknown>): RpcResult<unknown>;
	from(table: string): {
		select(columns: string): {
			eq(column: string, value: string): SelectResult<unknown>;
			in(column: string, values: string[]): SelectResult<unknown>;
		};
	};
};

type WorkerDependencies = {
	client?: CommunicationForwardWorkerClient;
	send?: (message: OperationalEmail) => Promise<{ messageId: string }>;
	readAttachment?: (objectKey: string) => Promise<Uint8Array>;
};

// One claim/send/finalize attempt. 'idle' means no claimable forward; otherwise the finalized provider
// outcome for the single forward this call processed.
export type ProcessedForwardResult =
	| { status: 'idle' }
	| {
			status: 'submitted' | 'retry' | 'cancelled' | 'submission_unknown';
			forwardEventId: string;
	  };

function rpcError(action: string, error: { message: string } | null) {
	return new Error(`${action}: ${error?.message ?? 'The database returned no result.'}`);
}

function resolveClient(
	client?: CommunicationForwardWorkerClient
): CommunicationForwardWorkerClient {
	return client ?? (getOwnerSupabaseClient() as unknown as CommunicationForwardWorkerClient);
}

// Releases abandoned forward claims from a prior wake back to the queue. Runs once per drain.
export async function quarantineStaleForwardClaims(
	client: CommunicationForwardWorkerClient
): Promise<number> {
	const quarantine = await client.rpc('quarantine_stale_communication_forward_claims', {
		batch_size: 50,
		stale_after: '15 minutes'
	});
	if (quarantine.error)
		throw rpcError('Could not quarantine stale forward claims', quarantine.error);
	return typeof quarantine.data === 'number' ? quarantine.data : 0;
}

export async function processClaimedForward(
	dependencies: WorkerDependencies = {}
): Promise<ProcessedForwardResult> {
	const client = resolveClient(dependencies.client);
	const send = dependencies.send ?? sendOperationalEmail;
	const readAttachment = dependencies.readAttachment ?? getObjectBytes;

	const claimed = await client.rpc('claim_communication_forward_event');
	if (claimed.error) throw rpcError('Could not claim a message forward', claimed.error);
	const forward = Array.isArray(claimed.data)
		? (claimed.data[0] as ClaimedForward | undefined)
		: undefined;
	if (!forward) return { status: 'idle' };

	const forwardAttachmentsResult = await client
		.from('communication_forward_attachments')
		.select('inbound_attachment_id')
		.eq('forward_event_id', forward.forward_event_id);
	if (forwardAttachmentsResult.error)
		throw rpcError('Could not list forward attachment links', forwardAttachmentsResult.error);
	const inboundAttachmentIds = (
		(forwardAttachmentsResult.data ?? []) as ForwardAttachmentRow[]
	).map((row) => row.inbound_attachment_id);

	let attachmentRows: InboundAttachmentRow[] = [];
	if (inboundAttachmentIds.length > 0) {
		const inboundAttachmentsResult = await client
			.from('communication_inbound_attachments')
			.select('id, file_name, mime_type, byte_size, object_key')
			.in('id', inboundAttachmentIds);
		if (inboundAttachmentsResult.error)
			throw rpcError('Could not load forward attachments', inboundAttachmentsResult.error);
		attachmentRows = (inboundAttachmentsResult.data ?? []) as InboundAttachmentRow[];
	}

	let outcome: 'submitted' | 'retry' | 'cancelled' | 'submission_unknown';
	let providerMessageId: string | undefined;
	let failureCode: string | undefined;
	let failureMessage: string | undefined;

	try {
		const attachments = await Promise.all(
			attachmentRows
				.filter((row): row is InboundAttachmentRow & { object_key: string } =>
					Boolean(row.object_key)
				)
				.map(async (row) => ({
					name: row.file_name,
					content: Buffer.from(await readAttachment(row.object_key)).toString('base64')
				}))
		);

		const submitted = await send({
			from: { email: forward.sender_email, name: forward.sender_name },
			to: forward.recipient_emails.map((email) => ({ email })),
			subject: forward.subject,
			htmlContent: forward.html_content,
			textContent: forward.text_content,
			intentId: forward.forward_event_id,
			attachments
		});
		outcome = 'submitted';
		providerMessageId = submitted.messageId;
	} catch (error) {
		if (error instanceof OperationalEmailSubmissionError) {
			outcome = error.outcome;
			failureCode = error.code;
			failureMessage = error.message;
		} else {
			outcome = 'submission_unknown';
			failureCode = 'worker_submission_unknown';
			failureMessage = 'The worker could not determine the provider submission outcome.';
		}
	}

	const finalizeArgs = {
		target_forward_event_id: forward.forward_event_id,
		target_claim_token: forward.claim_token,
		target_outcome: outcome,
		target_provider_message_id: providerMessageId,
		target_failure_code: failureCode,
		target_failure_message: failureMessage
	};
	const finalized = await client.rpc('finalize_communication_forward_event', finalizeArgs);
	if (finalized.error) throw rpcError('Could not finalize a message forward', finalized.error);

	return { status: outcome, forwardEventId: forward.forward_event_id };
}

// Wakes the forward queue: quarantine once, then bounded concurrent claim/send/finalize until idle, the claim
// cap, or the time budget. Entry point for the internal route and (later) a supervised worker.
export async function drainCommunicationForwardQueue(
	dependencies: WorkerDependencies & BoundedDrainOptions = {}
): Promise<BoundedDrainResult> {
	const client = resolveClient(dependencies.client);
	const send = dependencies.send ?? sendOperationalEmail;
	const readAttachment = dependencies.readAttachment ?? getObjectBytes;

	return runBoundedDrain(
		() => quarantineStaleForwardClaims(client),
		() => processClaimedForward({ client, send, readAttachment }),
		dependencies
	);
}
