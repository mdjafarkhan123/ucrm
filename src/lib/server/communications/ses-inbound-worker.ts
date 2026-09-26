import {
	SQSClient,
	ReceiveMessageCommand,
	DeleteMessageCommand,
	GetQueueAttributesCommand
} from '@aws-sdk/client-sqs';
import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database, Json } from '$lib/database.types';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { raiseOwnerAlert } from '$lib/server/jafar/owner-alerts';
import {
	attachmentExtension,
	DANGEROUS_ATTACHMENT_EXTENSIONS,
	INBOUND_ATTACHMENT_TOTAL_SIZE_BYTES
} from './inbound-email';
import {
	fetchSesInboundObject,
	parseSesInboundMessage,
	parseSesReceiptNotification,
	sesInboundEventKey,
	type SesReceiptNotification
} from './ses-inbound-email';
import { getSesEnv, sesInboundDlqUrl, sesInboundQueueUrl } from './ses-env';

// Operational email SES Part 4: drains the customer-reply SQS queue (deliberately its own queue, DLQ, and
// idempotency space from the delivery-events pipeline in marketing/event-consumer.ts -- a stuck reply must
// never block outgoing mail and vice versa). Unlike that consumer, there is no separate bulk projector RPC:
// each message needs its own S3 fetch and MIME parse, so record_communication_inbound_message is called
// directly per message.

type InboundMessageRow = { id: string; organization_id: string };

type RpcResult<T> = Promise<{ data: T | null; error: { message: string; code?: string } | null }>;

export type SesInboundWorkerClient = {
	rpc(name: string, args?: Record<string, unknown>): RpcResult<unknown>;
	insertCallbackEvent(row: {
		provider_event_key: string;
		event_kind: string;
		occurred_at: string | null;
		payload: SesReceiptNotification;
	}): Promise<{ data: { id: string } | null; error: { code?: string; message: string } | null }>;
	findCallbackEventId(
		providerEventKey: string
	): Promise<{ data: { id: string } | null; error: { message: string } | null }>;
	insertAttachments(
		rows: {
			organization_id: string;
			inbound_message_id: string;
			file_name: string;
			mime_type: string;
			byte_size: number;
			status: string;
			provider: 'ses';
			provider_download_token: string | null;
		}[]
	): Promise<{ error: { message: string } | null }>;
};

export type SqsMessage = { receiptHandle: string; body: string };

export type SqsClientLike = {
	receive(maxMessages: number, waitTimeSeconds: number): Promise<SqsMessage[]>;
	remove(receiptHandle: string): Promise<void>;
};

export type FetchObject = (bucketName: string, objectKey: string) => Promise<Buffer>;

function rpcError(action: string, error: { message: string } | null) {
	return new Error(`${action}: ${error?.message ?? 'The database returned no result.'}`);
}

function resolveClient(client?: SesInboundWorkerClient): SesInboundWorkerClient {
	if (client) return client;
	const owner = getOwnerSupabaseClient();
	return {
		rpc: (name, args) => owner.rpc(name as never, args as never) as unknown as RpcResult<unknown>,
		insertCallbackEvent: async (row) => {
			const { data, error } = await owner
				.from('communication_provider_callback_events')
				.insert({ ...row, provider: 'ses' } as never)
				.select('id')
				.single();
			return { data: data as { id: string } | null, error };
		},
		findCallbackEventId: async (providerEventKey) => {
			const { data, error } = await owner
				.from('communication_provider_callback_events')
				.select('id')
				.eq('provider', 'ses')
				.eq('provider_event_key', providerEventKey)
				.maybeSingle();
			return { data, error };
		},
		insertAttachments: async (rows) => {
			const { error } = await owner.from('communication_inbound_attachments').insert(rows as never);
			return { error };
		}
	};
}

let cachedSqs: { client: SQSClient; queueUrl: string } | null = null;

function resolveSqs(sqs?: SqsClientLike): SqsClientLike {
	if (sqs) return sqs;
	if (!cachedSqs) {
		const env = getSesEnv();
		cachedSqs = {
			client: new SQSClient({
				region: env.AWS_SES_REGION,
				credentials: {
					accessKeyId: env.AWS_SES_ACCESS_KEY_ID,
					secretAccessKey: env.AWS_SES_SECRET_ACCESS_KEY
				},
				requestHandler: { requestTimeout: 15_000, connectionTimeout: 5_000 }
			}),
			queueUrl: sesInboundQueueUrl(env)
		};
	}
	const { client, queueUrl } = cachedSqs;
	return {
		async receive(maxMessages, waitTimeSeconds) {
			const result = await client.send(
				new ReceiveMessageCommand({
					QueueUrl: queueUrl,
					MaxNumberOfMessages: maxMessages,
					WaitTimeSeconds: waitTimeSeconds
				})
			);
			return (result.Messages ?? [])
				.filter((message) => message.ReceiptHandle && message.Body)
				.map((message) => ({ receiptHandle: message.ReceiptHandle!, body: message.Body! }));
		},
		async remove(receiptHandle) {
			await client.send(
				new DeleteMessageCommand({ QueueUrl: queueUrl, ReceiptHandle: receiptHandle })
			);
		}
	};
}

export type DlqClientLike = { approximateDepth(): Promise<number> };

let cachedDlq: { client: SQSClient; queueUrl: string } | null = null;

function resolveDlq(dlq?: DlqClientLike): DlqClientLike {
	if (dlq) return dlq;
	if (!cachedDlq) {
		const env = getSesEnv();
		cachedDlq = {
			client: new SQSClient({
				region: env.AWS_SES_REGION,
				credentials: {
					accessKeyId: env.AWS_SES_ACCESS_KEY_ID,
					secretAccessKey: env.AWS_SES_SECRET_ACCESS_KEY
				},
				requestHandler: { requestTimeout: 15_000, connectionTimeout: 5_000 }
			}),
			queueUrl: sesInboundDlqUrl(env)
		};
	}
	const { client, queueUrl } = cachedDlq;
	return {
		async approximateDepth() {
			const result = await client.send(
				new GetQueueAttributesCommand({
					QueueUrl: queueUrl,
					AttributeNames: ['ApproximateNumberOfMessages']
				})
			);
			const raw = result.Attributes?.ApproximateNumberOfMessages;
			const depth = raw ? Number.parseInt(raw, 10) : 0;
			return Number.isFinite(depth) ? depth : 0;
		}
	};
}

const DLQ_ALERT_KIND = 'ses_inbound_dlq_message';
const DLQ_ALERT_QUIET_HOURS = 24;

async function checkDlqAndAlert(
	owner: SupabaseClient<Database>,
	dlq: DlqClientLike
): Promise<{ depth: number; alerted: boolean }> {
	const depth = await dlq.approximateDepth();
	if (depth <= 0) return { depth, alerted: false };

	const since = new Date(Date.now() - DLQ_ALERT_QUIET_HOURS * 60 * 60 * 1000).toISOString();
	const { data: recent, error } = await owner
		.from('platform_owner_notifications')
		.select('id')
		.eq('kind', DLQ_ALERT_KIND)
		.is('read_at', null)
		.gte('created_at', since)
		.limit(1);
	if (error) {
		console.error('Could not check for a recent SES inbound dead-letter-queue alert.', error);
		return { depth, alerted: false };
	}
	if (recent && recent.length > 0) return { depth, alerted: false };

	await raiseOwnerAlert(owner, {
		kind: DLQ_ALERT_KIND,
		severity: 'urgent',
		title: `${depth} customer reply email${depth === 1 ? '' : 's'} stuck in the SES inbound dead-letter queue`,
		body:
			'Amazon SES could not process one or more inbound customer reply emails after 5 attempts, and moved ' +
			'them to the ucrm-ses-inbound-dlq queue in SQS. Those replies are not in any conversation yet and need ' +
			'investigation in the AWS console.',
		target: { targetKind: 'platform', targetId: null }
	});
	return { depth, alerted: true };
}

export type SesInboundDrainResult = {
	received: number;
	recorded: number;
	duplicates: number;
	invalid: number;
	stoppedBy: 'idle' | 'max_messages' | 'time_budget';
};

export type SesInboundDrainOptions = {
	maxMessages?: number;
	receiveBatchSize?: number;
	waitTimeSeconds?: number;
	timeBudgetMs?: number;
	now?: () => number;
};

// Same conservative defaults as the marketing events drain: bound the wake, not the throughput claim.
const DEFAULT_MAX_MESSAGES = 50;
const DEFAULT_RECEIVE_BATCH = 10;
const DEFAULT_WAIT_TIME_SECONDS = 10;
const DEFAULT_TIME_BUDGET_MS = 20_000;

function attachmentRows(
	organizationId: string,
	inboundMessageId: string,
	objectKey: string,
	attachments: { filename?: string; contentType: string; size: number }[]
) {
	const totalSize = attachments.reduce((sum, attachment) => sum + attachment.size, 0);
	const oversized = totalSize > INBOUND_ATTACHMENT_TOTAL_SIZE_BYTES;

	return attachments.map((attachment, index) => {
		const fileName = attachment.filename?.trim() || `attachment-${index + 1}`;
		const dangerous = DANGEROUS_ATTACHMENT_EXTENSIONS.has(attachmentExtension(fileName));
		const status = oversized ? 'blocked_size' : dangerous ? 'blocked_type' : 'pending_import';
		return {
			organization_id: organizationId,
			inbound_message_id: inboundMessageId,
			file_name: fileName,
			mime_type: attachment.contentType,
			byte_size: attachment.size,
			status,
			provider: 'ses' as const,
			// The re-fetch-and-reparse-on-claim token the attachment worker's SES branch expects: the S3 key
			// carries which raw MIME object to re-fetch, the index which of its parsed attachments this is.
			provider_download_token: status === 'pending_import' ? `${objectKey}#${index}` : null
		};
	});
}

async function ingestOneMessage(
	client: SesInboundWorkerClient,
	fetchObject: FetchObject,
	message: SqsMessage
): Promise<'recorded' | 'duplicate' | 'invalid'> {
	let notification: SesReceiptNotification | null;
	try {
		notification = parseSesReceiptNotification(JSON.parse(message.body));
	} catch {
		notification = null;
	}
	if (!notification) {
		console.error(
			'An SES inbound message body was not a valid receipt notification; leaving it for the DLQ policy.'
		);
		return 'invalid';
	}

	const providerEventKey = sesInboundEventKey(notification);
	let callback = await client.insertCallbackEvent({
		provider_event_key: providerEventKey,
		event_kind: 'inbound_email',
		occurred_at: notification.mail.timestamp
			? new Date(notification.mail.timestamp).toISOString()
			: null,
		payload: notification
	});
	// An existing callback row only proves an earlier attempt got this far -- it may have failed on the S3 fetch or
	// the filing RPC afterwards. Carry on with that row; the RPC's own unique key decides whether it is a duplicate.
	const seenBefore = callback.error?.code === '23505';
	if (seenBefore) callback = await client.findCallbackEventId(providerEventKey);
	if (callback.error || !callback.data)
		throw rpcError('Could not record an SES inbound callback event', callback.error);

	// A failed S3 fetch or MIME parse is treated as transient and per-message -- an AWS blip, a permissions
	// edge case, or one malformed message -- never a reason to abort the whole drain. It is left in the queue
	// for SQS's own redrive-after-5-receives policy to send to the DLQ if it truly never recovers.
	let parsed: Awaited<ReturnType<typeof parseSesInboundMessage>>;
	try {
		const mime = await fetchObject(
			notification.receipt.action.bucketName,
			notification.receipt.action.objectKey
		);
		parsed = await parseSesInboundMessage(notification, mime);
	} catch (error) {
		console.error(
			'Could not fetch or parse an SES inbound message; leaving it for the DLQ policy.',
			error
		);
		return 'invalid';
	}

	const { data: inboundMessage, error: rpcErr } = await client.rpc(
		'record_communication_inbound_message',
		{
			target_provider_message_id: notification.mail.messageId,
			target_in_reply_to_provider_message_id: parsed.inReplyToProviderMessageId,
			target_provider_callback_event_id: callback.data.id,
			target_sender_email: parsed.senderEmail,
			target_sender_name: parsed.senderName,
			target_to_recipients: parsed.toRecipients as unknown as Json,
			target_cc_recipients: parsed.ccRecipients as unknown as Json,
			target_subject: parsed.subject,
			target_html_content: parsed.htmlContent,
			target_text_content: parsed.textContent,
			target_message_kind: parsed.messageKind,
			target_candidate_recipients: parsed.candidateRecipients as unknown as Json,
			target_provider: 'ses'
		}
	);
	if (rpcErr) throw rpcError('Could not resolve an SES inbound message', rpcErr);

	// PostgREST hands back a composite function's NULL (no row inserted) as a row of nulls.
	const row = inboundMessage as Partial<InboundMessageRow> | null;
	const inserted = row?.id ? (row as InboundMessageRow) : null;
	if (!inserted && seenBefore) return 'duplicate';
	if (inserted && parsed.attachments.length > 0) {
		const rows = attachmentRows(
			inserted.organization_id,
			inserted.id,
			notification.receipt.action.objectKey,
			parsed.attachments
		);
		const { error: attachmentError } = await client.insertAttachments(rows);
		if (attachmentError)
			console.error('Could not record SES inbound attachments.', attachmentError);
	}

	return 'recorded';
}

export async function drainSesInboundQueue(
	dependencies: {
		client?: SesInboundWorkerClient;
		sqs?: SqsClientLike;
		fetchObject?: FetchObject;
	} & SesInboundDrainOptions = {}
): Promise<SesInboundDrainResult> {
	const client = resolveClient(dependencies.client);
	const sqs = resolveSqs(dependencies.sqs);
	const fetchObject = dependencies.fetchObject ?? fetchSesInboundObject;
	const maxMessages = Math.max(1, Math.floor(dependencies.maxMessages ?? DEFAULT_MAX_MESSAGES));
	const receiveBatchSize = Math.max(
		1,
		Math.min(10, Math.floor(dependencies.receiveBatchSize ?? DEFAULT_RECEIVE_BATCH))
	);
	const waitTimeSeconds = Math.max(
		0,
		Math.min(20, Math.floor(dependencies.waitTimeSeconds ?? DEFAULT_WAIT_TIME_SECONDS))
	);
	const timeBudgetMs = Math.max(0, dependencies.timeBudgetMs ?? DEFAULT_TIME_BUDGET_MS);
	const now = dependencies.now ?? Date.now;
	const deadline = now() + timeBudgetMs;

	const result: SesInboundDrainResult = {
		received: 0,
		recorded: 0,
		duplicates: 0,
		invalid: 0,
		stoppedBy: 'idle'
	};

	while (true) {
		if (result.received >= maxMessages) {
			result.stoppedBy = 'max_messages';
			break;
		}
		if (now() >= deadline) {
			result.stoppedBy = 'time_budget';
			break;
		}

		const remaining = maxMessages - result.received;
		const messages = await sqs.receive(Math.min(receiveBatchSize, remaining), waitTimeSeconds);
		if (messages.length === 0) {
			result.stoppedBy = 'idle';
			break;
		}

		for (const message of messages) {
			result.received += 1;
			const outcome = await ingestOneMessage(client, fetchObject, message);
			if (outcome === 'recorded') result.recorded += 1;
			else if (outcome === 'duplicate') result.duplicates += 1;
			else {
				result.invalid += 1;
				continue;
			}
			await sqs.remove(message.receiptHandle);
		}
	}

	return result;
}

// ---------------------------------------------------------------------------------------------------
// Monitored wake: same single-flight lease / route deadline / ledger shape as
// runMonitoredMarketingEventsWake, adapted to this drain's result shape.
// ---------------------------------------------------------------------------------------------------

export const SES_INBOUND_WORKER_NAME = 'communications-ses-inbound';
const LEASE_TTL_SECONDS = 55;
const ROUTE_DEADLINE_MS = 40_000;

export type SesInboundWakeOutcome =
	SesInboundDrainResult['stoppedBy'] | 'already_running' | 'route_deadline' | 'error';

export type MonitoredSesInboundWakeResult = {
	outcome: SesInboundWakeOutcome;
} & Partial<SesInboundDrainResult>;

type MonitoredWakeDependencies = {
	client?: SesInboundWorkerClient;
	sqs?: SqsClientLike;
	dlq?: DlqClientLike;
	fetchObject?: FetchObject;
	owner?: SupabaseClient<Database>;
} & SesInboundDrainOptions & {
		wakeCorrelationId: string;
		leaseTtlSeconds?: number;
		routeDeadlineMs?: number;
		nowIso?: () => string;
	};

async function recordWakeResult(
	client: SesInboundWorkerClient,
	args: {
		wakeCorrelationId: string;
		startedAt: string;
		finishedAt: string;
		outcome: SesInboundWakeOutcome;
		result?: SesInboundDrainResult;
	}
): Promise<void> {
	const { result } = args;
	const record = await client.rpc('record_communication_worker_wake_result', {
		p_worker_name: SES_INBOUND_WORKER_NAME,
		p_wake_correlation_id: args.wakeCorrelationId,
		p_started_at: args.startedAt,
		p_finished_at: args.finishedAt,
		p_route_outcome: args.outcome,
		p_claimed: result?.received ?? null,
		p_submitted: result?.recorded ?? null
	});
	if (record.error)
		console.error('Could not record the SES inbound worker wake result.', record.error);
}

async function releaseWakeLease(client: SesInboundWorkerClient, leaseToken: string): Promise<void> {
	const released = await client.rpc('release_communication_worker_lease', {
		p_worker_name: SES_INBOUND_WORKER_NAME,
		p_lease_token: leaseToken
	});
	if (released.error)
		console.error('Could not release the SES inbound worker lease.', released.error);
}

export async function runMonitoredSesInboundWake(
	dependencies: MonitoredWakeDependencies
): Promise<MonitoredSesInboundWakeResult> {
	const client = resolveClient(dependencies.client);
	const nowIso = dependencies.nowIso ?? (() => new Date().toISOString());
	const startedAt = nowIso();

	const acquired = await client.rpc('acquire_communication_worker_lease', {
		p_worker_name: SES_INBOUND_WORKER_NAME,
		p_ttl_seconds: dependencies.leaseTtlSeconds ?? LEASE_TTL_SECONDS
	});
	if (acquired.error)
		throw rpcError('Could not acquire the SES inbound worker lease', acquired.error);
	const leaseToken = typeof acquired.data === 'string' ? acquired.data : null;

	if (!leaseToken) {
		await recordWakeResult(client, {
			wakeCorrelationId: dependencies.wakeCorrelationId,
			startedAt,
			finishedAt: nowIso(),
			outcome: 'already_running'
		});
		return { outcome: 'already_running' };
	}

	const deadlineMs = dependencies.routeDeadlineMs ?? ROUTE_DEADLINE_MS;
	let deadlineTimer: ReturnType<typeof setTimeout> | undefined;
	const drain = drainSesInboundQueue({ ...dependencies, client });

	try {
		const raced = await Promise.race([
			drain.then((result) => ({ kind: 'done' as const, result })),
			new Promise<{ kind: 'deadline' }>((resolve) => {
				deadlineTimer = setTimeout(() => resolve({ kind: 'deadline' }), deadlineMs);
			})
		]);

		if (raced.kind === 'deadline') {
			drain.catch(() => {});
			await recordWakeResult(client, {
				wakeCorrelationId: dependencies.wakeCorrelationId,
				startedAt,
				finishedAt: nowIso(),
				outcome: 'route_deadline'
			});
			return { outcome: 'route_deadline' };
		}

		await releaseWakeLease(client, leaseToken);
		await recordWakeResult(client, {
			wakeCorrelationId: dependencies.wakeCorrelationId,
			startedAt,
			finishedAt: nowIso(),
			outcome: raced.result.stoppedBy,
			result: raced.result
		});

		try {
			await checkDlqAndAlert(
				dependencies.owner ?? getOwnerSupabaseClient(),
				resolveDlq(dependencies.dlq)
			);
		} catch (error) {
			console.error('Could not check the SES inbound dead-letter queue.', error);
		}

		return { outcome: raced.result.stoppedBy, ...raced.result };
	} catch (error) {
		await releaseWakeLease(client, leaseToken);
		await recordWakeResult(client, {
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
