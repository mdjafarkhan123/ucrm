import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { getObjectBytes } from '$lib/server/storage/r2';
import {
	OperationalEmailSubmissionError,
	sendOperationalEmail,
	type OperationalEmail
} from './brevo';
import { runBoundedDrain, type BoundedDrainOptions, type BoundedDrainResult } from './drain';

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
	reply_to_email: string | null;
	reply_to_name: string | null;
};

type OutboundAttachmentRow = {
	file_name: string;
	mime_type: string;
	byte_size: number;
	object_key: string;
};

type RpcResult<T> = Promise<{ data: T | null; error: { message: string } | null }>;

export type CommunicationWorkerClient = {
	rpc(name: string, args?: Record<string, unknown>): RpcResult<unknown>;
};

type WorkerDependencies = {
	client?: CommunicationWorkerClient;
	send?: (message: OperationalEmail) => Promise<{ messageId: string }>;
	readAttachment?: (objectKey: string) => Promise<Uint8Array>;
};

// One claim/send/finalize attempt. 'idle' means the queue held no claimable row; otherwise the finalized
// provider outcome for the single intent this call processed.
export type ProcessedEmailResult =
	| { status: 'idle' }
	| {
			status: 'submitted' | 'retry' | 'cancelled' | 'submission_unknown';
			intentId: string;
	  };

function rpcError(action: string, error: { message: string } | null) {
	return new Error(`${action}: ${error?.message ?? 'The database returned no result.'}`);
}

function resolveClient(client?: CommunicationWorkerClient): CommunicationWorkerClient {
	return client ?? (getOwnerSupabaseClient() as unknown as CommunicationWorkerClient);
}

// Releases abandoned claims from a prior wake back to the queue. Runs once per drain, before any slot claims.
export async function quarantineStaleEmailClaims(
	client: CommunicationWorkerClient
): Promise<number> {
	const quarantine = await client.rpc('quarantine_stale_communication_claims', {
		batch_size: 50,
		stale_after: '15 minutes'
	});
	if (quarantine.error)
		throw rpcError('Could not quarantine stale communication claims', quarantine.error);
	return typeof quarantine.data === 'number' ? quarantine.data : 0;
}

export async function processClaimedEmail(
	dependencies: WorkerDependencies = {}
): Promise<ProcessedEmailResult> {
	const client = resolveClient(dependencies.client);
	const send = dependencies.send ?? sendOperationalEmail;
	const readAttachment = dependencies.readAttachment ?? getObjectBytes;

	const claimed = await client.rpc('claim_communication_outbox_event');
	if (claimed.error) throw rpcError('Could not claim a communication email', claimed.error);
	const email = Array.isArray(claimed.data)
		? (claimed.data[0] as ClaimedEmail | undefined)
		: undefined;
	if (!email) return { status: 'idle' };

	const attachmentsListed = await client.rpc('list_communication_outbound_attachments', {
		target_delivery_intent_id: email.delivery_intent_id
	});
	if (attachmentsListed.error)
		throw rpcError('Could not list outbound attachments', attachmentsListed.error);
	const attachmentRows = Array.isArray(attachmentsListed.data)
		? (attachmentsListed.data as OutboundAttachmentRow[])
		: [];

	let outcome: 'submitted' | 'retry' | 'cancelled' | 'submission_unknown';
	let providerMessageId: string | undefined;
	let failureCode: string | undefined;
	let failureMessage: string | undefined;

	try {
		const attachments = await Promise.all(
			attachmentRows.map(async (row) => ({
				name: row.file_name,
				content: Buffer.from(await readAttachment(row.object_key)).toString('base64')
			}))
		);

		const submitted = await send({
			from: { email: email.sender_email, name: email.sender_name },
			to: { email: email.recipient_email },
			replyTo: email.reply_to_email
				? { email: email.reply_to_email, name: email.reply_to_name ?? undefined }
				: undefined,
			subject: email.subject,
			htmlContent: email.html_content,
			textContent: email.text_content,
			intentId: email.delivery_intent_id,
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
		target_outbox_event_id: email.outbox_event_id,
		target_claim_token: email.claim_token,
		target_outcome: outcome,
		target_provider_message_id: providerMessageId,
		target_failure_code: failureCode,
		target_failure_message: failureMessage
	};
	const finalized = await client.rpc('finalize_communication_outbox_event', finalizeArgs);
	if (finalized.error) throw rpcError('Could not finalize a communication email', finalized.error);

	return { status: outcome, intentId: email.delivery_intent_id };
}

// Wakes the email outbox: quarantine once, then bounded concurrent claim/send/finalize until the queue is
// idle, the claim cap is reached, or the time budget expires. This is the entry point the internal route and
// (later) a supervised worker call.
export async function drainCommunicationEmailQueue(
	dependencies: WorkerDependencies & BoundedDrainOptions = {}
): Promise<BoundedDrainResult> {
	const client = resolveClient(dependencies.client);
	const send = dependencies.send ?? sendOperationalEmail;
	const readAttachment = dependencies.readAttachment ?? getObjectBytes;

	return runBoundedDrain(
		() => quarantineStaleEmailClaims(client),
		() => processClaimedEmail({ client, send, readAttachment }),
		dependencies
	);
}

// Stable identity for the email outbox worker's lease and ledger rows. Must match the name the Cron dispatch
// function and the health read use.
export const EMAIL_WORKER_NAME = 'communications-email-outbox';
// The lease outlives one drain but expires before the next 60s wake, so a crashed wake frees the worker within
// one cycle rather than wedging it. The whole-route deadline is the hard backstop above the drain's own 20s
// admission budget and each send's 10s abort: it exists for a path with no timeout of its own (an R2
// attachment read), and sits under the 50s pg_net HTTP timeout.
const LEASE_TTL_SECONDS = 55;
const ROUTE_DEADLINE_MS = 40_000;

// The route-reported outcome recorded in the ledger: the three drain terminals, the two the route itself
// decides, and 'error' for an infrastructure failure the route turns into a 500.
export type EmailWakeOutcome =
	| BoundedDrainResult['stoppedBy']
	| 'already_running'
	| 'route_deadline'
	| 'error';

export type MonitoredEmailWakeResult = { outcome: EmailWakeOutcome } & Partial<BoundedDrainResult>;

type MonitoredWakeDependencies = WorkerDependencies &
	BoundedDrainOptions & {
		wakeCorrelationId: string;
		leaseTtlSeconds?: number;
		routeDeadlineMs?: number;
		nowIso?: () => string;
	};

// The ledger is best-effort monitoring, never the correctness boundary. A failed ledger write must not turn a
// drain that actually sent mail into an HTTP error (health reads the real pg_net status anyway), so recording
// swallows its own errors after logging them.
async function recordEmailWakeResult(
	client: CommunicationWorkerClient,
	args: {
		wakeCorrelationId: string;
		startedAt: string;
		finishedAt: string;
		outcome: EmailWakeOutcome;
		result?: BoundedDrainResult;
	}
): Promise<void> {
	const { result } = args;
	const record = await client.rpc('record_communication_worker_wake_result', {
		p_worker_name: EMAIL_WORKER_NAME,
		p_wake_correlation_id: args.wakeCorrelationId,
		p_started_at: args.startedAt,
		p_finished_at: args.finishedAt,
		p_route_outcome: args.outcome,
		p_stale_claims_quarantined: result?.staleClaimsQuarantined ?? null,
		p_claimed: result?.claimed ?? null,
		p_submitted: result?.submitted ?? null,
		p_retried: result?.retried ?? null,
		p_cancelled: result?.cancelled ?? null,
		p_submission_unknown: result?.submissionUnknown ?? null
	});
	if (record.error) console.error('Could not record the email worker wake result.', record.error);
}

// One monitored wake: take the single-flight lease, run the bounded drain under a hard route deadline, record
// the attributable outcome, and release the lease. A wake that cannot take the lease reports already_running
// (a 2xx no-op). If the deadline trips, the lease is deliberately NOT released -- it expires on its own so the
// still-running drain keeps its claim ownership, and finalize stays token-guarded.
export async function runMonitoredEmailWake(
	dependencies: MonitoredWakeDependencies
): Promise<MonitoredEmailWakeResult> {
	const client = resolveClient(dependencies.client);
	const nowIso = dependencies.nowIso ?? (() => new Date().toISOString());
	const startedAt = nowIso();

	const acquired = await client.rpc('acquire_communication_worker_lease', {
		p_worker_name: EMAIL_WORKER_NAME,
		p_ttl_seconds: dependencies.leaseTtlSeconds ?? LEASE_TTL_SECONDS
	});
	if (acquired.error) throw rpcError('Could not acquire the email worker lease', acquired.error);
	const leaseToken = typeof acquired.data === 'string' ? acquired.data : null;

	if (!leaseToken) {
		await recordEmailWakeResult(client, {
			wakeCorrelationId: dependencies.wakeCorrelationId,
			startedAt,
			finishedAt: nowIso(),
			outcome: 'already_running'
		});
		return { outcome: 'already_running' };
	}

	const deadlineMs = dependencies.routeDeadlineMs ?? ROUTE_DEADLINE_MS;
	let deadlineTimer: ReturnType<typeof setTimeout> | undefined;
	const drain = drainCommunicationEmailQueue({ ...dependencies, client });

	try {
		const raced = await Promise.race([
			drain.then((result) => ({ kind: 'done' as const, result })),
			new Promise<{ kind: 'deadline' }>((resolve) => {
				deadlineTimer = setTimeout(() => resolve({ kind: 'deadline' }), deadlineMs);
			})
		]);

		if (raced.kind === 'deadline') {
			// The drain overran its budget on a path with no abort of its own. Leave the lease to expire so the
			// in-flight work keeps its claim; a stray later rejection must not surface as unhandled.
			drain.catch(() => {});
			await recordEmailWakeResult(client, {
				wakeCorrelationId: dependencies.wakeCorrelationId,
				startedAt,
				finishedAt: nowIso(),
				outcome: 'route_deadline'
			});
			return { outcome: 'route_deadline' };
		}

		await releaseEmailWakeLease(client, leaseToken);
		await recordEmailWakeResult(client, {
			wakeCorrelationId: dependencies.wakeCorrelationId,
			startedAt,
			finishedAt: nowIso(),
			outcome: raced.result.stoppedBy,
			result: raced.result
		});
		return { outcome: raced.result.stoppedBy, ...raced.result };
	} catch (error) {
		// An infrastructure failure inside the drain (not a provider outcome, which finalize already owns).
		// Release the lease, record the attempt, and let the route turn it into a 500.
		await releaseEmailWakeLease(client, leaseToken);
		await recordEmailWakeResult(client, {
			wakeCorrelationId: dependencies.wakeCorrelationId,
			startedAt,
			finishedAt: nowIso(),
			outcome: 'error'
		});
		throw error;
	} finally {
		if (deadlineTimer) clearTimeout(deadlineTimer);
	}
}

// Best-effort: the lease self-expires, so a failed release only means the worker waits out one TTL.
async function releaseEmailWakeLease(
	client: CommunicationWorkerClient,
	leaseToken: string
): Promise<void> {
	const released = await client.rpc('release_communication_worker_lease', {
		p_worker_name: EMAIL_WORKER_NAME,
		p_lease_token: leaseToken
	});
	if (released.error) console.error('Could not release the email worker lease.', released.error);
}
