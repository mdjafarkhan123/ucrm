import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '$lib/database.types';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { runBoundedDrain, type BoundedDrainOptions, type BoundedDrainResult } from './drain';
import { submitTwilioSms, TwilioSmsSubmissionError, type SubmitTwilioSmsInput } from './twilio';
import { createSupabaseTwilioProvisioningStore } from './twilio-provisioning-store';
import { decryptTwilioCredential } from './twilio-credential-crypto';

// A2 Stage 4B: the SMS half of the bounded delivery drain. It mirrors the email worker exactly -- quarantine
// stale claims once per wake, then bounded concurrent claim/send/finalize under a single-flight lease -- with
// two SMS-only differences: it uses the SMS claim/finalize/quarantine RPCs, and it decrypts the sending
// organization's least-privilege Twilio Restricted key just-in-time for each send (a plaintext secret can never
// live in the database claim). Postgres owns eligibility, retry timing and money; this worker performs only the
// one provider call each claim authorizes. Stage 4 stays dark until Stage 5 webhooks and a launch gate pass.

// The frozen row the SMS claim returns. Everything needed to send except the Restricted key secret, which the
// worker resolves and decrypts separately.
type ClaimedSms = {
	outbox_event_id: string;
	delivery_intent_id: string;
	organization_id: string;
	twilio_account_id: string;
	subaccount_sid: string;
	messaging_service_sid: string;
	claim_token: string;
	attempt_number: number;
	recipient_phone: string;
	sender_phone: string;
	body: string;
	encoding: string;
	segment_count: number;
};

type RpcResult<T> = Promise<{ data: T | null; error: { message: string } | null }>;

export type CommunicationWorkerClient = {
	rpc(name: string, args?: Record<string, unknown>): RpcResult<unknown>;
};

// The subaccount Restricted key the send authenticates with, resolved and decrypted per send.
export type ResolvedSmsCredentials = { apiKeySid: string; apiKeySecret: string };

export type ResolveSmsCredentials = (input: {
	organizationId: string;
	twilioAccountId: string;
	subaccountSid: string;
}) => Promise<ResolvedSmsCredentials>;

type SmsWorkerDependencies = {
	client?: CommunicationWorkerClient;
	submit?: (input: SubmitTwilioSmsInput) => Promise<{ providerMessageId: string }>;
	resolveCredentials?: ResolveSmsCredentials;
};

export type ProcessedSmsResult =
	| { status: 'idle' }
	| { status: 'submitted' | 'retry' | 'cancelled' | 'submission_unknown'; intentId: string };

function rpcError(action: string, error: { message: string } | null) {
	return new Error(`${action}: ${error?.message ?? 'The database returned no result.'}`);
}

function resolveClient(client?: CommunicationWorkerClient): CommunicationWorkerClient {
	return client ?? (getOwnerSupabaseClient() as unknown as CommunicationWorkerClient);
}

// The default credential resolver: read the subaccount's CURRENT Restricted key and decrypt it with the
// server-only keyring, binding the exact organization/credential/subaccount/purpose as authenticated context.
// Never logs or returns the plaintext beyond the immediate send caller.
async function defaultResolveSmsCredentials(input: {
	organizationId: string;
	twilioAccountId: string;
	subaccountSid: string;
}): Promise<ResolvedSmsCredentials> {
	const store = createSupabaseTwilioProvisioningStore(
		getOwnerSupabaseClient() as unknown as SupabaseClient<Database>
	);
	const credential = await store.getCredential({
		accountId: input.twilioAccountId,
		purpose: 'restricted_api_key',
		lifecycleState: 'current'
	});
	if (!credential || !credential.credentialSid) {
		throw new Error('No current Twilio Restricted key is available for this organization.');
	}
	const apiKeySecret = decryptTwilioCredential(credential.encrypted, {
		organizationId: input.organizationId,
		credentialId: credential.id,
		subaccountSid: input.subaccountSid,
		purpose: 'restricted_api_key'
	});
	return { apiKeySid: credential.credentialSid, apiKeySecret };
}

// Releases abandoned SMS claims from a prior wake back to the queue. Runs once per drain, before any slot claims.
export async function quarantineStaleSmsClaims(client: CommunicationWorkerClient): Promise<number> {
	const quarantine = await client.rpc('quarantine_stale_communication_sms_claims', {
		batch_size: 50,
		stale_after: '15 minutes'
	});
	if (quarantine.error)
		throw rpcError('Could not quarantine stale SMS claims', quarantine.error);
	return typeof quarantine.data === 'number' ? quarantine.data : 0;
}

export async function processClaimedSms(
	dependencies: SmsWorkerDependencies = {}
): Promise<ProcessedSmsResult> {
	const client = resolveClient(dependencies.client);
	const submit = dependencies.submit ?? submitTwilioSms;
	const resolveCredentials = dependencies.resolveCredentials ?? defaultResolveSmsCredentials;

	const claimed = await client.rpc('claim_communication_sms_outbox_event');
	if (claimed.error) throw rpcError('Could not claim an SMS', claimed.error);
	const sms = Array.isArray(claimed.data) ? (claimed.data[0] as ClaimedSms | undefined) : undefined;
	if (!sms) return { status: 'idle' };

	let outcome: 'submitted' | 'retry' | 'cancelled' | 'submission_unknown';
	let providerMessageId: string | undefined;
	let failureCode: string | undefined;
	let failureMessage: string | undefined;

	let credentials: ResolvedSmsCredentials | undefined;
	try {
		credentials = await resolveCredentials({
			organizationId: sms.organization_id,
			twilioAccountId: sms.twilio_account_id,
			subaccountSid: sms.subaccount_sid
		});
	} catch {
		// The provider was never contacted, so this is a safe pre-submission retry, not an ambiguous outcome.
		outcome = 'retry';
		failureCode = 'twilio_credentials_unavailable';
		failureMessage = 'The sending credentials were unavailable. UCRM will try again.';
	}

	if (credentials) {
		try {
			const submitted = await submit({
				subaccountSid: sms.subaccount_sid,
				messagingServiceSid: sms.messaging_service_sid,
				apiKeySid: credentials.apiKeySid,
				apiKeySecret: credentials.apiKeySecret,
				from: sms.sender_phone,
				to: sms.recipient_phone,
				body: sms.body,
				deliveryIntentId: sms.delivery_intent_id
			});
			outcome = 'submitted';
			providerMessageId = submitted.providerMessageId;
		} catch (error) {
			if (error instanceof TwilioSmsSubmissionError) {
				outcome = error.outcome;
				failureCode = error.code;
				failureMessage = error.message;
			} else {
				// An unexpected error after the request may have left UCRM: treat as ambiguous, never resend blindly.
				outcome = 'submission_unknown';
				failureCode = 'worker_submission_unknown';
				failureMessage = 'The worker could not determine the provider submission outcome.';
			}
		}
	}

	const finalized = await client.rpc('finalize_communication_sms_outbox_event', {
		target_outbox_event_id: sms.outbox_event_id,
		target_claim_token: sms.claim_token,
		target_outcome: outcome!,
		target_provider_message_id: providerMessageId,
		target_failure_code: failureCode,
		target_failure_message: failureMessage
	});
	if (finalized.error) throw rpcError('Could not finalize an SMS', finalized.error);

	return { status: outcome!, intentId: sms.delivery_intent_id };
}

// Wakes the SMS outbox: quarantine once, then bounded concurrent claim/send/finalize until the queue is idle,
// the claim cap is reached, or the time budget expires.
export async function drainCommunicationSmsQueue(
	dependencies: SmsWorkerDependencies & BoundedDrainOptions = {}
): Promise<BoundedDrainResult> {
	const client = resolveClient(dependencies.client);
	const submit = dependencies.submit ?? submitTwilioSms;
	const resolveCredentials = dependencies.resolveCredentials ?? defaultResolveSmsCredentials;

	return runBoundedDrain(
		() => quarantineStaleSmsClaims(client),
		() => processClaimedSms({ client, submit, resolveCredentials }),
		dependencies
	);
}

// Stable identity for the SMS outbox worker's lease and ledger rows. Separate from the email worker so the two
// channels have independent single-flight leases and budgets. Must match the name the (Stage 4C) SMS wake
// dispatch and health read use.
export const SMS_WORKER_NAME = 'communications-sms-outbox';

// The lease outlives one drain but expires before the next wake, so a crashed wake frees the worker within one
// cycle. The route deadline is the hard backstop under the pg_net HTTP timeout; each send has its own 10s abort.
const LEASE_TTL_SECONDS = 55;
const ROUTE_DEADLINE_MS = 40_000;

export type SmsWakeOutcome =
	| BoundedDrainResult['stoppedBy']
	| 'already_running'
	| 'route_deadline'
	| 'error';

export type MonitoredSmsWakeResult = { outcome: SmsWakeOutcome } & Partial<BoundedDrainResult>;

type MonitoredWakeDependencies = SmsWorkerDependencies &
	BoundedDrainOptions & {
		wakeCorrelationId: string;
		leaseTtlSeconds?: number;
		routeDeadlineMs?: number;
		nowIso?: () => string;
	};

// Best-effort monitoring: a failed ledger write must never turn a drain that actually sent into an HTTP error.
async function recordSmsWakeResult(
	client: CommunicationWorkerClient,
	args: {
		wakeCorrelationId: string;
		startedAt: string;
		finishedAt: string;
		outcome: SmsWakeOutcome;
		result?: BoundedDrainResult;
	}
): Promise<void> {
	const { result } = args;
	const record = await client.rpc('record_communication_worker_wake_result', {
		p_worker_name: SMS_WORKER_NAME,
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
	if (record.error) console.error('Could not record the SMS worker wake result.', record.error);
}

// One monitored wake: take the single-flight lease, run the bounded drain under a hard route deadline, record
// the attributable outcome, and release the lease. Mirrors runMonitoredEmailWake.
export async function runMonitoredSmsWake(
	dependencies: MonitoredWakeDependencies
): Promise<MonitoredSmsWakeResult> {
	const client = resolveClient(dependencies.client);
	const nowIso = dependencies.nowIso ?? (() => new Date().toISOString());
	const startedAt = nowIso();

	const acquired = await client.rpc('acquire_communication_worker_lease', {
		p_worker_name: SMS_WORKER_NAME,
		p_ttl_seconds: dependencies.leaseTtlSeconds ?? LEASE_TTL_SECONDS
	});
	if (acquired.error) throw rpcError('Could not acquire the SMS worker lease', acquired.error);
	const leaseToken = typeof acquired.data === 'string' ? acquired.data : null;

	if (!leaseToken) {
		await recordSmsWakeResult(client, {
			wakeCorrelationId: dependencies.wakeCorrelationId,
			startedAt,
			finishedAt: nowIso(),
			outcome: 'already_running'
		});
		return { outcome: 'already_running' };
	}

	const deadlineMs = dependencies.routeDeadlineMs ?? ROUTE_DEADLINE_MS;
	let deadlineTimer: ReturnType<typeof setTimeout> | undefined;
	const drain = drainCommunicationSmsQueue({ ...dependencies, client });

	try {
		const raced = await Promise.race([
			drain.then((result) => ({ kind: 'done' as const, result })),
			new Promise<{ kind: 'deadline' }>((resolve) => {
				deadlineTimer = setTimeout(() => resolve({ kind: 'deadline' }), deadlineMs);
			})
		]);

		if (raced.kind === 'deadline') {
			// The drain overran its budget. Leave the lease to expire so the in-flight work keeps its claim.
			drain.catch(() => {});
			await recordSmsWakeResult(client, {
				wakeCorrelationId: dependencies.wakeCorrelationId,
				startedAt,
				finishedAt: nowIso(),
				outcome: 'route_deadline'
			});
			return { outcome: 'route_deadline' };
		}

		await releaseSmsWakeLease(client, leaseToken);
		await recordSmsWakeResult(client, {
			wakeCorrelationId: dependencies.wakeCorrelationId,
			startedAt,
			finishedAt: nowIso(),
			outcome: raced.result.stoppedBy,
			result: raced.result
		});
		return { outcome: raced.result.stoppedBy, ...raced.result };
	} catch (error) {
		await releaseSmsWakeLease(client, leaseToken);
		await recordSmsWakeResult(client, {
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
async function releaseSmsWakeLease(
	client: CommunicationWorkerClient,
	leaseToken: string
): Promise<void> {
	const released = await client.rpc('release_communication_worker_lease', {
		p_worker_name: SMS_WORKER_NAME,
		p_lease_token: leaseToken
	});
	if (released.error) console.error('Could not release the SMS worker lease.', released.error);
}
