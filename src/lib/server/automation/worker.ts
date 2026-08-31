// Contractor Settings Part 6D-2: the automation worker.
//
// One wake does two bounded drains in order: turn new events into enrollments, then move due enrollments one
// step. Both are claim-based in Postgres, so several workers (or several overlapping wakes) may run at once —
// there is deliberately NO single-flight lease like the Communications email worker takes, because production
// runs more than one worker container and a global lock would serialise them.
//
// 6D-3: an `action` step now sends. advance returns 'action_due', and this module runs the effect — it mints
// the customer link (the app origin lives here, not in the database) and calls perform_automation_email_effect,
// which enqueues into the same Communications outbox the email worker already drains. Automation never talks to
// the provider.

import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { createQuoteEmailAccessLink } from '$lib/server/communications/quote-email';

type RpcResult<T> = Promise<{ data: T | null; error: { message: string } | null }>;

export type AutomationWorkerClient = {
	rpc(name: string, args?: Record<string, unknown>): RpcResult<unknown>;
};

type ClaimedWorkItem = {
	work_item_id: string;
	claim_token: string;
	organization_id: string;
	enrollment_id: string;
	step_index: number;
	attempts: number;
};

// What one transition did. `claim_lost` means another worker owns the row now — not an error, and not counted
// as work this wake performed. `action_due` means the step is an action whose effect this module must run.
type AdvanceOutcome =
	| 'claim_lost'
	| 'enrollment_inactive'
	| 'enrollment_expired'
	| 'recipe_not_active'
	| 'completed'
	| 'waiting'
	| 'action_due'
	| 'action_not_available';

// What running an action effect settled to. `claim_lost` mirrors advance: the lease moved on.
type ActionEffectOutcome = 'action_sent' | 'action_cancelled' | 'action_deferred' | 'claim_lost';

// A minted customer access link: the raw URL for the email body and the hash the database stores.
export type QuoteAccessLink = { url: string; tokenHash: string };

export type AutomationDrainCounts = {
	eventsProcessed: number;
	claimed: number;
	waited: number;
	completed: number;
	sent: number;
	cancelled: number;
	parked: number;
	retried: number;
};

export type AutomationDrainResult = AutomationDrainCounts & {
	stoppedBy: 'idle' | 'max_claims' | 'time_budget';
};

export type AutomationDrainOptions = {
	client?: AutomationWorkerClient;
	batchSize?: number;
	perOrganizationCap?: number;
	leaseSeconds?: number;
	maxClaims?: number;
	timeBudgetMs?: number;
	intakeBatchSize?: number;
	maxIntakeBatches?: number;
	workerName?: string;
	now?: () => number;
	// Mints the customer access link for an email action. Injectable so the effect is testable without env or
	// real crypto; defaults to the same link minter the quote send uses.
	createQuoteLink?: () => QuoteAccessLink;
};

// Conservative defaults to verify under load, not capacity claims. The time budget stays under the route
// deadline, which stays under the pg_net HTTP timeout, which stays under the one-minute wake interval.
const DEFAULT_BATCH_SIZE = 25;
const DEFAULT_PER_ORGANIZATION_CAP = 5;
const DEFAULT_LEASE_SECONDS = 120;
const DEFAULT_MAX_CLAIMS = 200;
const DEFAULT_TIME_BUDGET_MS = 20_000;
const DEFAULT_INTAKE_BATCH_SIZE = 50;
const DEFAULT_MAX_INTAKE_BATCHES = 20;

export const AUTOMATION_WORKER_NAME = 'automation-worker';

function rpcError(action: string, error: { message: string } | null) {
	return new Error(`${action}: ${error?.message ?? 'The database returned no result.'}`);
}

function resolveClient(client?: AutomationWorkerClient): AutomationWorkerClient {
	return client ?? (getOwnerSupabaseClient() as unknown as AutomationWorkerClient);
}

// Provider and database errors reach the ledger and the work item, so the text must never carry credentials,
// headers, or customer content. Truncate hard and keep only the message.
function safeMessage(error: unknown): string {
	const raw = error instanceof Error ? error.message : String(error ?? 'unknown error');
	return raw.slice(0, 500);
}

export async function drainAutomationEvents(
	client: AutomationWorkerClient,
	options: AutomationDrainOptions,
	deadline: number,
	now: () => number
): Promise<number> {
	const batchSize = options.intakeBatchSize ?? DEFAULT_INTAKE_BATCH_SIZE;
	const maxBatches = options.maxIntakeBatches ?? DEFAULT_MAX_INTAKE_BATCHES;
	let processed = 0;

	// Intake drains in strict arrival order, so it runs batch after batch rather than concurrently: two
	// parallel claims would still be correct (SKIP LOCKED) but would interleave the order Jafar asked to keep.
	for (let batch = 0; batch < maxBatches; batch += 1) {
		if (now() >= deadline) break;
		const result = await client.rpc('intake_automation_events', { p_batch_size: batchSize });
		if (result.error) throw rpcError('Could not take in automation events', result.error);
		const count = typeof result.data === 'number' ? result.data : 0;
		processed += count;
		if (count < batchSize) break;
	}

	return processed;
}

// Runs one email action effect: mint the customer link here (the app origin is not in the database), then let
// perform_automation_email_effect recheck, enqueue, and settle in one transaction. The link is minted before
// the settle decides to send; a link never used (a permanent skip) is just a discarded random token.
async function runEmailAction(
	client: AutomationWorkerClient,
	item: ClaimedWorkItem,
	createQuoteLink: () => QuoteAccessLink
): Promise<ActionEffectOutcome> {
	const link = createQuoteLink();
	const performed = await client.rpc('perform_automation_email_effect', {
		p_work_item_id: item.work_item_id,
		p_claim_token: item.claim_token,
		p_quote_url: link.url,
		p_quote_token_hash: link.tokenHash
	});
	if (performed.error) throw new Error(performed.error.message);
	return performed.data as ActionEffectOutcome;
}

// One claimed transition. Any failure is reported back through retry_automation_work_item so the row backs off
// and stays visible instead of silently waiting out its lease.
async function advanceOne(
	client: AutomationWorkerClient,
	item: ClaimedWorkItem,
	counts: AutomationDrainCounts,
	createQuoteLink: () => QuoteAccessLink
): Promise<void> {
	try {
		const advanced = await client.rpc('advance_automation_work_item', {
			p_work_item_id: item.work_item_id,
			p_claim_token: item.claim_token
		});
		if (advanced.error) throw new Error(advanced.error.message);
		const outcome = advanced.data as AdvanceOutcome;

		if (outcome === 'action_due') {
			// The effect settles the row itself. An infrastructure failure here (not a step outcome) falls to the
			// catch below, which backs the row off exactly as an advance failure would.
			const effect = await runEmailAction(client, item, createQuoteLink);
			if (effect === 'action_sent') counts.sent += 1;
			else if (effect === 'action_cancelled') counts.cancelled += 1;
			else if (effect === 'action_deferred') counts.retried += 1;
			// 'claim_lost' is another worker's row; it counts as nothing.
			return;
		}

		if (outcome === 'waiting') counts.waited += 1;
		else if (outcome === 'completed') counts.completed += 1;
		else if (outcome === 'action_not_available') counts.parked += 1;
		else if (
			outcome === 'enrollment_inactive' ||
			outcome === 'enrollment_expired' ||
			outcome === 'recipe_not_active'
		)
			counts.cancelled += 1;
		// 'claim_lost' is another worker's row; it counts as nothing.
	} catch (error) {
		const reported = await client.rpc('retry_automation_work_item', {
			p_work_item_id: item.work_item_id,
			p_claim_token: item.claim_token,
			p_error_code: 'advance_failed',
			p_error_message: safeMessage(error),
			p_permanent: false
		});
		// A failure to record the failure is an infrastructure problem, not a step outcome: let it surface so
		// the route reports an error rather than a clean wake.
		if (reported.error)
			throw rpcError('Could not record an automation step failure', reported.error);
		counts.retried += 1;
	}
}

// The work drain: claim a bounded fair batch, advance each item, repeat until the queue is idle, the claim cap
// is reached, or the time budget expires.
export async function drainAutomationWork(
	options: AutomationDrainOptions = {}
): Promise<AutomationDrainResult> {
	const client = resolveClient(options.client);
	const now = options.now ?? Date.now;
	const timeBudgetMs = Math.max(0, options.timeBudgetMs ?? DEFAULT_TIME_BUDGET_MS);
	const deadline = now() + timeBudgetMs;
	const batchSize = options.batchSize ?? DEFAULT_BATCH_SIZE;
	const maxClaims = Math.max(1, options.maxClaims ?? DEFAULT_MAX_CLAIMS);
	const createQuoteLink = options.createQuoteLink ?? createQuoteEmailAccessLink;

	const counts: AutomationDrainCounts = {
		eventsProcessed: 0,
		claimed: 0,
		waited: 0,
		completed: 0,
		sent: 0,
		cancelled: 0,
		parked: 0,
		retried: 0
	};

	// Intake first: an event that arrives with this wake should get its enrollment and its first work item
	// before the work drain looks for due rows, so one wake can carry a delivery all the way to its first step.
	counts.eventsProcessed = await drainAutomationEvents(client, options, deadline, now);

	let stoppedBy: AutomationDrainResult['stoppedBy'] = 'idle';

	for (;;) {
		if (counts.claimed >= maxClaims) {
			stoppedBy = 'max_claims';
			break;
		}
		if (now() >= deadline) {
			stoppedBy = 'time_budget';
			break;
		}

		const claimed = await client.rpc('claim_automation_work_items', {
			p_batch_size: Math.min(batchSize, maxClaims - counts.claimed),
			p_per_organization_cap: options.perOrganizationCap ?? DEFAULT_PER_ORGANIZATION_CAP,
			p_lease_seconds: options.leaseSeconds ?? DEFAULT_LEASE_SECONDS,
			p_worker: options.workerName ?? AUTOMATION_WORKER_NAME
		});
		if (claimed.error) throw rpcError('Could not claim automation work', claimed.error);

		const items = Array.isArray(claimed.data) ? (claimed.data as ClaimedWorkItem[]) : [];
		if (items.length === 0) {
			stoppedBy = 'idle';
			break;
		}
		counts.claimed += items.length;

		// Sequential inside a batch: every transition is a short database call, and the lease is generous
		// enough that ordering the batch costs nothing. 6D-3 introduces the network call that will make
		// bounded concurrency worth measuring here.
		for (const item of items) {
			await advanceOne(client, item, counts, createQuoteLink);
		}
	}

	return { ...counts, stoppedBy };
}

// The whole-route deadline is the hard backstop above the drain's own time budget, and sits under the 50s
// pg_net HTTP timeout. Unlike the email worker there is no lease to leave behind: a drain that overruns keeps
// its per-row claims, and those expire on their own.
const ROUTE_DEADLINE_MS = 40_000;

export type AutomationWakeOutcome = AutomationDrainResult['stoppedBy'] | 'route_deadline' | 'error';

export type MonitoredAutomationWakeResult = { outcome: AutomationWakeOutcome } & Partial<
	Omit<AutomationDrainResult, 'stoppedBy'>
>;

type MonitoredWakeOptions = AutomationDrainOptions & {
	wakeCorrelationId: string;
	routeDeadlineMs?: number;
	nowIso?: () => string;
};

// The ledger is monitoring, never a correctness boundary: a failed ledger write must not turn a wake that
// actually moved work into an HTTP error.
async function recordWakeResult(
	client: AutomationWorkerClient,
	args: {
		wakeCorrelationId: string;
		startedAt: string;
		finishedAt: string;
		outcome: AutomationWakeOutcome;
		counts?: AutomationDrainCounts;
	}
): Promise<void> {
	const { counts } = args;
	const recorded = await client.rpc('record_automation_worker_wake_result', {
		p_worker_name: AUTOMATION_WORKER_NAME,
		p_wake_correlation_id: args.wakeCorrelationId,
		p_started_at: args.startedAt,
		p_finished_at: args.finishedAt,
		p_route_outcome: args.outcome,
		p_events_processed: counts?.eventsProcessed ?? null,
		p_claimed: counts?.claimed ?? null,
		p_waited: counts?.waited ?? null,
		p_completed: counts?.completed ?? null,
		p_cancelled: counts?.cancelled ?? null,
		p_parked: counts?.parked ?? null,
		p_retried: counts?.retried ?? null
	});
	if (recorded.error)
		console.error('Could not record the automation worker wake result.', recorded.error);
}

// One monitored wake: run the bounded drain under a hard route deadline and record the attributable outcome.
export async function runMonitoredAutomationWake(
	options: MonitoredWakeOptions
): Promise<MonitoredAutomationWakeResult> {
	const client = resolveClient(options.client);
	const nowIso = options.nowIso ?? (() => new Date().toISOString());
	const startedAt = nowIso();
	const deadlineMs = options.routeDeadlineMs ?? ROUTE_DEADLINE_MS;

	let deadlineTimer: ReturnType<typeof setTimeout> | undefined;
	const drain = drainAutomationWork({ ...options, client });

	try {
		const raced = await Promise.race([
			drain.then((result) => ({ kind: 'done' as const, result })),
			new Promise<{ kind: 'deadline' }>((resolve) => {
				deadlineTimer = setTimeout(() => resolve({ kind: 'deadline' }), deadlineMs);
			})
		]);

		if (raced.kind === 'deadline') {
			// A stray later rejection must not surface as unhandled; the in-flight work keeps its row claims.
			drain.catch(() => {});
			await recordWakeResult(client, {
				wakeCorrelationId: options.wakeCorrelationId,
				startedAt,
				finishedAt: nowIso(),
				outcome: 'route_deadline'
			});
			return { outcome: 'route_deadline' };
		}

		const { stoppedBy, ...counts } = raced.result;
		await recordWakeResult(client, {
			wakeCorrelationId: options.wakeCorrelationId,
			startedAt,
			finishedAt: nowIso(),
			outcome: stoppedBy,
			counts
		});
		return { outcome: stoppedBy, ...counts };
	} catch (error) {
		await recordWakeResult(client, {
			wakeCorrelationId: options.wakeCorrelationId,
			startedAt,
			finishedAt: nowIso(),
			outcome: 'error'
		});
		throw error;
	} finally {
		if (deadlineTimer) clearTimeout(deadlineTimer);
	}
}
