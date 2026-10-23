import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { runBoundedDrain, type BoundedDrainOptions, type BoundedDrainResult } from './drain';
import { loadMessengerPageToken } from './messenger-connections';
import { MessengerGraphError, sendMessengerText } from './messenger-graph';

// Messenger Part 7: the send half of the Messenger worker. Same contract as the SMS worker -- release abandoned
// claims once per wake, then bounded claim/send/finalize -- without its money and consent steps. Postgres owns
// eligibility (Page still connected, 24-hour window still open) and retry timing; this worker makes the one Send
// API call each claim allows, with the Page key decrypted just before it.

type ClaimedMessenger = {
	outbox_event_id: string;
	delivery_intent_id: string;
	organization_id: string;
	connection_id: string;
	page_id: string;
	psid: string;
	claim_token: string;
	attempt_number: number;
	body: string;
};

type RpcResult<T> = Promise<{ data: T | null; error: { message: string } | null }>;

export type MessengerSendWorkerClient = {
	rpc(name: string, args?: Record<string, unknown>): RpcResult<unknown>;
};

type SendOutcome = 'submitted' | 'retry' | 'cancelled' | 'submission_unknown';

type MessengerSendDependencies = {
	client?: MessengerSendWorkerClient;
	send?: typeof sendMessengerText;
	loadPageToken?: typeof loadMessengerPageToken;
};

export type ProcessedMessengerResult =
	{ status: 'idle' } | { status: SendOutcome; intentId: string };

function rpcError(action: string, error: { message: string } | null) {
	return new Error(`${action}: ${error?.message ?? 'The database returned no result.'}`);
}

function resolveClient(client?: MessengerSendWorkerClient): MessengerSendWorkerClient {
	return client ?? (getOwnerSupabaseClient() as unknown as MessengerSendWorkerClient);
}

/** Meta's answer to a send → what happens to the message, in words staff read on it. Exported for tests. */
export function messengerSendFailure(error: unknown): {
	outcome: Exclude<SendOutcome, 'submitted'>;
	code: string;
	message: string;
} {
	if (!(error instanceof MessengerGraphError)) {
		// Something broke after the request may have left: never resend blindly; our echo settles it.
		return {
			outcome: 'submission_unknown',
			code: 'worker_submission_unknown',
			message: 'It is not clear whether Facebook received this message.'
		};
	}
	if (error.networkCause)
		return {
			outcome: 'submission_unknown',
			code: 'messenger_no_answer',
			message: 'Facebook did not answer in time, so it is not clear whether this message was sent.'
		};
	if (error.failure === 'token_invalid')
		return {
			outcome: 'cancelled',
			code: 'token_invalid',
			message: 'Facebook stopped accepting messages from this Page. Reconnect it in Settings.'
		};
	if (error.failure === 'permission_missing')
		return {
			outcome: 'cancelled',
			code: 'permission_missing',
			message: 'This Page no longer lets UCRM send messages. Reconnect it in Settings.'
		};
	if (error.failure === 'unavailable')
		return {
			outcome: 'retry',
			code: 'messenger_unavailable',
			message: 'Facebook is busy right now. UCRM will try again.'
		};
	return {
		outcome: 'cancelled',
		code: 'messenger_rejected',
		message:
			"Facebook didn't accept this message. The customer may not be able to receive it right now."
	};
}

// Releases claims a crashed wake left behind. They become "unknown", never resent.
export async function quarantineStaleMessengerClaims(
	client: MessengerSendWorkerClient
): Promise<number> {
	const quarantine = await client.rpc('quarantine_stale_communication_messenger_claims', {
		batch_size: 50,
		stale_after: '5 minutes'
	});
	if (quarantine.error)
		throw rpcError('Could not release stale Messenger claims', quarantine.error);
	return typeof quarantine.data === 'number' ? quarantine.data : 0;
}

export async function processClaimedMessenger(
	dependencies: MessengerSendDependencies = {}
): Promise<ProcessedMessengerResult> {
	const client = resolveClient(dependencies.client);
	const send = dependencies.send ?? sendMessengerText;
	const loadPageToken = dependencies.loadPageToken ?? loadMessengerPageToken;

	const claimed = await client.rpc('claim_communication_messenger_outbox_event');
	if (claimed.error) throw rpcError('Could not claim a Messenger reply', claimed.error);
	const message = Array.isArray(claimed.data)
		? (claimed.data[0] as ClaimedMessenger | undefined)
		: undefined;
	if (!message) return { status: 'idle' };

	let outcome: SendOutcome;
	let providerMessageId: string | undefined;
	let failureCode: string | undefined;
	let failureMessage: string | undefined;

	let pageToken: string | null = null;
	try {
		pageToken = await loadPageToken({
			organizationId: message.organization_id,
			connectionId: message.connection_id
		});
	} catch {
		pageToken = null;
	}

	if (!pageToken) {
		// Meta was never contacted, so trying again later is safe.
		outcome = 'retry';
		failureCode = 'messenger_page_key_unavailable';
		failureMessage = "The Page's Facebook key could not be read. UCRM will try again.";
	} else {
		try {
			const sent = await send({
				pageId: message.page_id,
				pageToken,
				psid: message.psid,
				text: message.body,
				metadata: message.delivery_intent_id
			});
			outcome = 'submitted';
			providerMessageId = sent.messageId;
		} catch (error) {
			const failure = messengerSendFailure(error);
			outcome = failure.outcome;
			failureCode = failure.code;
			failureMessage = failure.message;
		}
	}

	const finalized = await client.rpc('finalize_communication_messenger_outbox_event', {
		target_outbox_event_id: message.outbox_event_id,
		target_claim_token: message.claim_token,
		target_outcome: outcome,
		target_provider_message_id: providerMessageId,
		target_failure_code: failureCode,
		target_failure_message: failureMessage
	});
	if (finalized.error) throw rpcError('Could not finalize a Messenger reply', finalized.error);

	return { status: outcome, intentId: message.delivery_intent_id };
}

// One wake of the Messenger send queue. Claims use SKIP LOCKED, so the reply route's instant wake and the
// one-minute cron can overlap safely without a lease.
export async function drainMessengerSendQueue(
	dependencies: MessengerSendDependencies & BoundedDrainOptions = {}
): Promise<BoundedDrainResult> {
	const client = resolveClient(dependencies.client);
	return runBoundedDrain(
		() => quarantineStaleMessengerClaims(client),
		() => processClaimedMessenger({ ...dependencies, client }),
		dependencies
	);
}
