import {
	SQSClient,
	ReceiveMessageCommand,
	DeleteMessageCommand,
	GetQueueAttributesCommand
} from '@aws-sdk/client-sqs';
import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '$lib/database.types';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { getSesEnv, sesEventQueueUrl, sesEventDlqUrl } from '$lib/server/communications/ses-env';
import { raiseOwnerAlert } from '$lib/server/jafar/owner-alerts';
import { operationalCallbackEventKind } from '$lib/server/communications/operational-ses-events';
import {
	parseSesEvent,
	sesEventConfigurationSetName,
	sesEventKey,
	sesEventOccurredAt,
	sesEventTag,
	type SesEvent
} from './ses-events';

// The Marketing SES event consumer (M4 stage 4): drain the provisioned SQS queue, durably record each event
// once (idempotent on provider_event_key), then run the projector RPC to advance recipient status. Unlike
// dispatcher.ts's claim/finalize shape, there is nothing in Postgres to claim here -- SQS's own visibility
// timeout is the retry mechanism, so a message is only ever deleted once it is durably recorded or confirmed
// a duplicate. See Memory/campaigns/marketing-growth/parts/M4.md's "Stage 4 decisions" for the full reasoning.
//
// The one SNS -> SQS pipeline now carries both streams: a Marketing configuration set's events go to
// marketing_campaign_recipient_events (insertEvent) as before, and an operational configuration set's events
// (name starts with 'ucrm-operational-') go to communication_provider_callback_events (insertCallbackEvent)
// instead. process_communication_provider_callbacks is
// provider-neutral and already reads any channel='email' row, so it needs no change.

type RpcResult<T> = Promise<{ data: T | null; error: { message: string } | null }>;

export type MarketingEventsWorkerClient = {
	rpc(name: string, args?: Record<string, unknown>): RpcResult<unknown>;
	insertEvent(row: {
		provider_event_key: string;
		provider_message_id: string;
		event_kind: string;
		occurred_at: string | null;
		payload: SesEvent;
	}): Promise<{ error: { code?: string; message: string } | null }>;
	insertCallbackEvent(row: {
		provider_event_key: string;
		delivery_intent_id: string | null;
		event_kind: string;
		occurred_at: string | null;
		payload: SesEvent;
	}): Promise<{ error: { code?: string; message: string } | null }>;
};

export type SqsMessage = { receiptHandle: string; body: string };

export type SqsClientLike = {
	receive(maxMessages: number, waitTimeSeconds: number): Promise<SqsMessage[]>;
	remove(receiptHandle: string): Promise<void>;
};

function rpcError(action: string, error: { message: string } | null) {
	return new Error(`${action}: ${error?.message ?? 'The database returned no result.'}`);
}

function resolveClient(client?: MarketingEventsWorkerClient): MarketingEventsWorkerClient {
	if (client) return client;
	const owner = getOwnerSupabaseClient();
	return {
		rpc: (name, args) => owner.rpc(name as never, args as never) as unknown as RpcResult<unknown>,
		insertEvent: async (row) => {
			const { error } = await owner
				.from('marketing_campaign_recipient_events')
				.insert(row as never);
			return { error };
		},
		insertCallbackEvent: async (row) => {
			const { error } = await owner
				.from('communication_provider_callback_events')
				.insert({ ...row, provider: 'ses' } as never);
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
			queueUrl: sesEventQueueUrl(env)
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
			queueUrl: sesEventDlqUrl(env)
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

const DLQ_ALERT_KIND = 'marketing_ses_dlq_message';
// Amazon's own ApproximateNumberOfMessages is a poll estimate (not a push notification), so this rides
// the same one-minute wake that drains the main queue instead of its own schedule. Re-alerting is
// suppressed for a day at a time by checking for an unread notification of this kind first, so a
// message stuck for a week produces one alert a day instead of one a minute.
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
		console.error('Could not check for a recent SES dead-letter-queue alert.', error);
		return { depth, alerted: false };
	}
	if (recent && recent.length > 0) return { depth, alerted: false };

	await raiseOwnerAlert(owner, {
		kind: DLQ_ALERT_KIND,
		severity: 'urgent',
		title: `${depth} email delivery event${depth === 1 ? '' : 's'} stuck in the SES dead-letter queue`,
		body:
			'Amazon SES could not process one or more marketing or operational email delivery events after ' +
			'5 attempts, and moved them to the ucrm-ses-events-dlq queue in SQS. Recipient or delivery status ' +
			'may be stale until this is investigated in the AWS console.',
		target: { targetKind: 'platform', targetId: null }
	});
	return { depth, alerted: true };
}

export type EventDrainResult = {
	received: number;
	recorded: number;
	duplicates: number;
	ignored: number;
	skipped: number;
	processed: number;
	processedCallbacks: number;
	stoppedBy: 'idle' | 'max_messages' | 'time_budget';
};

export type EventDrainOptions = {
	maxMessages?: number;
	receiveBatchSize?: number;
	waitTimeSeconds?: number;
	timeBudgetMs?: number;
	projectBatchSize?: number;
	now?: () => number;
};

// Conservative defaults matching drain.ts's philosophy: bound the wake, not the throughput claim. 50 messages
// per wake at a one-minute cadence is 3,000/hour per organization sharing the one queue; raise only once
// measured.
const DEFAULT_MAX_MESSAGES = 50;
const DEFAULT_RECEIVE_BATCH = 10;
const DEFAULT_WAIT_TIME_SECONDS = 10;
const DEFAULT_TIME_BUDGET_MS = 20_000;
const DEFAULT_PROJECT_BATCH_SIZE = 200;

// SES/SNS sends this plain-text confirmation to the topic every time a configuration set's event
// destination is (re)created -- e.g. once per contractor's sender setup. It is never JSON, so without
// this check it would silently poison the queue and eventually dead-letter on every new contractor,
// making the DLQ alert fire for expected setup noise instead of real stuck events.
const SNS_TOPIC_VALIDATION_MESSAGE =
	'Successfully validated SNS topic for Amazon SES event publishing.';

async function recordOneMessage(
	client: MarketingEventsWorkerClient,
	message: SqsMessage
): Promise<'recorded' | 'duplicate' | 'ignored' | 'invalid'> {
	if (message.body.trim() === SNS_TOPIC_VALIDATION_MESSAGE) return 'ignored';

	let parsedBody: unknown;
	try {
		parsedBody = JSON.parse(message.body);
	} catch {
		console.error(
			'A marketing event message body was not valid JSON; leaving it for the DLQ policy.'
		);
		return 'invalid';
	}

	const event = parseSesEvent(parsedBody);
	if (!event) {
		console.error(
			'A marketing event message did not match the expected SES event shape; leaving it for the DLQ policy.'
		);
		return 'invalid';
	}

	const configurationSetName = sesEventConfigurationSetName(event);
	if (configurationSetName?.startsWith('ucrm-operational-')) {
		const { error } = await client.insertCallbackEvent({
			provider_event_key: sesEventKey(event),
			delivery_intent_id: sesEventTag(event, 'ucrm-intent'),
			event_kind: operationalCallbackEventKind(event),
			occurred_at: sesEventOccurredAt(event),
			payload: event
		});

		if (!error) return 'recorded';
		if (error.code === '23505') return 'duplicate';
		if (error.code === '23503') {
			// The tag names a delivery intent that no longer exists (deleted, or sent outside the outbox). A
			// retry can never succeed, so this event is acknowledged and skipped rather than left for the DLQ.
			console.warn('An operational SES event names an unknown delivery intent; skipping.', {
				deliveryIntentId: sesEventTag(event, 'ucrm-intent')
			});
			return 'ignored';
		}
		throw rpcError('Could not record an operational email delivery event', error);
	}

	const { error } = await client.insertEvent({
		provider_event_key: sesEventKey(event),
		provider_message_id: event.mail.messageId,
		event_kind: event.eventType,
		occurred_at: sesEventOccurredAt(event),
		payload: event
	});

	if (!error) return 'recorded';
	if (error.code === '23505') return 'duplicate';
	throw rpcError('Could not record a marketing campaign recipient event', error);
}

// Drains the queue until it is empty, a message-count bound, or a time budget is hit, then runs one bounded
// pass of the projector RPC over whatever is now unprocessed (including durable rows from earlier wakes that
// a previous crash left unprojected).
export async function drainMarketingEventQueue(
	dependencies: {
		client?: MarketingEventsWorkerClient;
		sqs?: SqsClientLike;
	} & EventDrainOptions = {}
): Promise<EventDrainResult> {
	const client = resolveClient(dependencies.client);
	const sqs = resolveSqs(dependencies.sqs);
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

	const result: EventDrainResult = {
		received: 0,
		recorded: 0,
		duplicates: 0,
		ignored: 0,
		skipped: 0,
		processed: 0,
		processedCallbacks: 0,
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
			const outcome = await recordOneMessage(client, message);
			if (outcome === 'recorded') result.recorded += 1;
			else if (outcome === 'duplicate') result.duplicates += 1;
			else if (outcome === 'ignored') result.ignored += 1;
			else {
				result.skipped += 1;
				continue;
			}
			await sqs.remove(message.receiptHandle);
		}
	}

	const projected = await client.rpc('project_marketing_campaign_recipient_events', {
		batch_size: dependencies.projectBatchSize ?? DEFAULT_PROJECT_BATCH_SIZE
	});
	if (projected.error)
		throw rpcError('Could not project marketing campaign recipient events', projected.error);
	result.processed = typeof projected.data === 'number' ? projected.data : 0;

	const processedCallbacks = await client.rpc('process_communication_provider_callbacks', {
		batch_size: dependencies.projectBatchSize ?? DEFAULT_PROJECT_BATCH_SIZE
	});
	if (processedCallbacks.error)
		throw rpcError(
			'Could not process operational email delivery callbacks',
			processedCallbacks.error
		);
	result.processedCallbacks =
		typeof processedCallbacks.data === 'number' ? processedCallbacks.data : 0;

	return result;
}

// ---------------------------------------------------------------------------------------------------
// Monitored wake: same single-flight lease / route deadline / ledger shape as runMonitoredMarketingWake,
// adapted to a queue drain instead of a claim/finalize loop.
// ---------------------------------------------------------------------------------------------------

export const MARKETING_EVENTS_WORKER_NAME = 'communications-marketing-events';
const LEASE_TTL_SECONDS = 55;
const ROUTE_DEADLINE_MS = 40_000;

export type MarketingEventsWakeOutcome =
	EventDrainResult['stoppedBy'] | 'already_running' | 'route_deadline' | 'error';

export type MonitoredMarketingEventsWakeResult = {
	outcome: MarketingEventsWakeOutcome;
} & Partial<EventDrainResult>;

type MonitoredWakeDependencies = {
	client?: MarketingEventsWorkerClient;
	sqs?: SqsClientLike;
	dlq?: DlqClientLike;
	owner?: SupabaseClient<Database>;
} & EventDrainOptions & {
		wakeCorrelationId: string;
		leaseTtlSeconds?: number;
		routeDeadlineMs?: number;
		nowIso?: () => string;
	};

// The ledger's claimed/submitted columns predate this worker and describe a claim/finalize shape this drain
// does not have; received/recorded are the closest honest fit. retried/cancelled/submission_unknown do not
// apply and stay null rather than carry a misleading zero.
async function recordEventsWakeResult(
	client: MarketingEventsWorkerClient,
	args: {
		wakeCorrelationId: string;
		startedAt: string;
		finishedAt: string;
		outcome: MarketingEventsWakeOutcome;
		result?: EventDrainResult;
	}
): Promise<void> {
	const { result } = args;
	const record = await client.rpc('record_communication_worker_wake_result', {
		p_worker_name: MARKETING_EVENTS_WORKER_NAME,
		p_wake_correlation_id: args.wakeCorrelationId,
		p_started_at: args.startedAt,
		p_finished_at: args.finishedAt,
		p_route_outcome: args.outcome,
		p_claimed: result?.received ?? null,
		p_submitted: result?.recorded ?? null
	});
	if (record.error)
		console.error('Could not record the marketing events worker wake result.', record.error);
}

export async function runMonitoredMarketingEventsWake(
	dependencies: MonitoredWakeDependencies
): Promise<MonitoredMarketingEventsWakeResult> {
	const client = resolveClient(dependencies.client);
	const nowIso = dependencies.nowIso ?? (() => new Date().toISOString());
	const startedAt = nowIso();

	const acquired = await client.rpc('acquire_communication_worker_lease', {
		p_worker_name: MARKETING_EVENTS_WORKER_NAME,
		p_ttl_seconds: dependencies.leaseTtlSeconds ?? LEASE_TTL_SECONDS
	});
	if (acquired.error)
		throw rpcError('Could not acquire the marketing events worker lease', acquired.error);
	const leaseToken = typeof acquired.data === 'string' ? acquired.data : null;

	if (!leaseToken) {
		await recordEventsWakeResult(client, {
			wakeCorrelationId: dependencies.wakeCorrelationId,
			startedAt,
			finishedAt: nowIso(),
			outcome: 'already_running'
		});
		return { outcome: 'already_running' };
	}

	const deadlineMs = dependencies.routeDeadlineMs ?? ROUTE_DEADLINE_MS;
	let deadlineTimer: ReturnType<typeof setTimeout> | undefined;
	const drain = drainMarketingEventQueue({ ...dependencies, client });

	try {
		const raced = await Promise.race([
			drain.then((result) => ({ kind: 'done' as const, result })),
			new Promise<{ kind: 'deadline' }>((resolve) => {
				deadlineTimer = setTimeout(() => resolve({ kind: 'deadline' }), deadlineMs);
			})
		]);

		if (raced.kind === 'deadline') {
			drain.catch(() => {});
			await recordEventsWakeResult(client, {
				wakeCorrelationId: dependencies.wakeCorrelationId,
				startedAt,
				finishedAt: nowIso(),
				outcome: 'route_deadline'
			});
			return { outcome: 'route_deadline' };
		}

		await releaseEventsWakeLease(client, leaseToken);
		await recordEventsWakeResult(client, {
			wakeCorrelationId: dependencies.wakeCorrelationId,
			startedAt,
			finishedAt: nowIso(),
			outcome: raced.result.stoppedBy,
			result: raced.result
		});

		// Monitoring, not the drain's job: a failure here must never turn a successful drain into a
		// reported error, so it is isolated and only logged.
		try {
			await checkDlqAndAlert(
				dependencies.owner ?? getOwnerSupabaseClient(),
				resolveDlq(dependencies.dlq)
			);
		} catch (error) {
			console.error('Could not check the SES dead-letter queue for stuck marketing events.', error);
		}

		return { outcome: raced.result.stoppedBy, ...raced.result };
	} catch (error) {
		await releaseEventsWakeLease(client, leaseToken);
		await recordEventsWakeResult(client, {
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

async function releaseEventsWakeLease(
	client: MarketingEventsWorkerClient,
	leaseToken: string
): Promise<void> {
	const released = await client.rpc('release_communication_worker_lease', {
		p_worker_name: MARKETING_EVENTS_WORKER_NAME,
		p_lease_token: leaseToken
	});
	if (released.error)
		console.error('Could not release the marketing events worker lease.', released.error);
}
