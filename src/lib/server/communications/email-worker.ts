import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import {
	OperationalEmailSubmissionError,
	sendOperationalEmail,
	type OperationalEmail
} from './brevo';

type ClaimedEmail = {
	outbox_event_id: string;
	delivery_intent_id: string;
	claim_token: string;
	recipient_email: string;
	subject: string;
	html_content: string;
	text_content: string;
	logical_send_key: string;
	sender_id: string;
	sender_email: string;
	sender_name: string;
};

type RpcResult<T> = Promise<{ data: T | null; error: { message: string } | null }>;

export type CommunicationWorkerClient = {
	rpc(name: string, args?: Record<string, unknown>): RpcResult<unknown>;
};

type WorkerDependencies = {
	client?: CommunicationWorkerClient;
	send?: (message: OperationalEmail) => Promise<{ messageId: string }>;
};

export type CommunicationWorkerResult =
	| { status: 'idle'; staleClaimsQuarantined: number }
	| {
			status: 'submitted' | 'retry' | 'cancelled' | 'submission_unknown';
			intentId: string;
			staleClaimsQuarantined: number;
	  };

function rpcError(action: string, error: { message: string } | null) {
	return new Error(`${action}: ${error?.message ?? 'The database returned no result.'}`);
}

export async function runCommunicationEmailWorker(
	dependencies: WorkerDependencies = {}
): Promise<CommunicationWorkerResult> {
	const injectedClient = dependencies.client;
	const ownerClient = injectedClient ? null : getOwnerSupabaseClient();
	const send = dependencies.send ?? sendOperationalEmail;

	const quarantineArgs = { batch_size: 50, stale_after: '15 minutes' };
	const quarantine = injectedClient
		? await injectedClient.rpc('quarantine_stale_communication_claims', quarantineArgs)
		: await ownerClient!.rpc('quarantine_stale_communication_claims', quarantineArgs);
	if (quarantine.error)
		throw rpcError('Could not quarantine stale communication claims', quarantine.error);
	const staleClaimsQuarantined = typeof quarantine.data === 'number' ? quarantine.data : 0;

	const claimed = injectedClient
		? await injectedClient.rpc('claim_communication_outbox_event')
		: await ownerClient!.rpc('claim_communication_outbox_event');
	if (claimed.error) throw rpcError('Could not claim a communication email', claimed.error);
	const email = Array.isArray(claimed.data)
		? (claimed.data[0] as ClaimedEmail | undefined)
		: undefined;
	if (!email) return { status: 'idle', staleClaimsQuarantined };

	let outcome: 'submitted' | 'retry' | 'cancelled' | 'submission_unknown';
	let providerMessageId: string | undefined;
	let failureCode: string | undefined;
	let failureMessage: string | undefined;

	try {
		const submitted = await send({
			from: { email: email.sender_email, name: email.sender_name },
			to: { email: email.recipient_email },
			subject: email.subject,
			htmlContent: email.html_content,
			textContent: email.text_content,
			intentId: email.delivery_intent_id
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
		target_outbox_event_id: email.outbox_event_id,
		target_claim_token: email.claim_token,
		target_outcome: outcome,
		target_provider_message_id: providerMessageId,
		target_failure_code: failureCode,
		target_failure_message: failureMessage
	};
	const finalized = injectedClient
		? await injectedClient.rpc('finalize_communication_outbox_event', finalizeArgs)
		: await ownerClient!.rpc('finalize_communication_outbox_event', finalizeArgs);
	if (finalized.error) throw rpcError('Could not finalize a communication email', finalized.error);

	return { status: outcome, intentId: email.delivery_intent_id, staleClaimsQuarantined };
}
