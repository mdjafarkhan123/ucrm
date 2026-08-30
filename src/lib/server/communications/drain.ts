// Bounded competing-consumer drain shared by the email and forward workers. The approved A1 architecture
// (docs/research/communications-a1-delivery-architecture.md) is: quarantine stale claims once per wake, then
// run a small fixed number of asynchronous claim/send/finalize slots until the queue is idle, a maximum claim
// count is reached, or a time budget expires. The time budget must stay below the route's HTTP timeout, which
// must stay below the wake interval, so routine invocations never overlap. Postgres remains the sole owner of
// eligibility, retry timing, and history; this runner only bounds how much a single wake attempts.

export type DrainSubmissionOutcome = 'submitted' | 'retry' | 'cancelled' | 'submission_unknown';

// A single claim/send/finalize attempt reports either that the queue had nothing claimable ('idle') or the
// finalized provider outcome for the one row it processed.
export type DrainProcessResult = { status: 'idle' } | { status: DrainSubmissionOutcome };

export type BoundedDrainOptions = {
	concurrency?: number;
	maxClaims?: number;
	timeBudgetMs?: number;
	// Injectable clock so the time-budget bound is testable without real waiting.
	now?: () => number;
};

export type BoundedDrainResult = {
	staleClaimsQuarantined: number;
	claimed: number;
	submitted: number;
	retried: number;
	cancelled: number;
	submissionUnknown: number;
	stoppedBy: 'idle' | 'max_claims' | 'time_budget';
};

// Conservative defaults to verify, not capacity claims. Concurrency starts small because more slots only make
// larger provider bursts and more simultaneous database/R2 work until measurement justifies raising it. The
// budget leaves head-room under the route's HTTP timeout even if a slot's final send runs to its own abort.
const DEFAULT_CONCURRENCY = 2;
const DEFAULT_MAX_CLAIMS = 50;
const DEFAULT_TIME_BUDGET_MS = 20_000;

export async function runBoundedDrain(
	quarantine: () => Promise<number>,
	processOne: () => Promise<DrainProcessResult>,
	options: BoundedDrainOptions = {}
): Promise<BoundedDrainResult> {
	const concurrency = Math.max(1, Math.floor(options.concurrency ?? DEFAULT_CONCURRENCY));
	const maxClaims = Math.max(1, Math.floor(options.maxClaims ?? DEFAULT_MAX_CLAIMS));
	const timeBudgetMs = Math.max(0, options.timeBudgetMs ?? DEFAULT_TIME_BUDGET_MS);
	const now = options.now ?? Date.now;
	const deadline = now() + timeBudgetMs;

	// Quarantine runs exactly once per wake, before any slot claims, so an abandoned prior claim is released
	// back to the queue and this drain can pick it up.
	const staleClaimsQuarantined = await quarantine();

	const result: BoundedDrainResult = {
		staleClaimsQuarantined,
		claimed: 0,
		submitted: 0,
		retried: 0,
		cancelled: 0,
		submissionUnknown: 0,
		stoppedBy: 'idle'
	};

	// The first slot to stop records why; the rest observe it and exit. 'idle' is the default terminal reason
	// and only a bound that trips first overrides it.
	let stopped: 'idle' | 'max_claims' | 'time_budget' | null = null;

	// Reserve a claim slot before hitting the database. Reserving here (rather than counting after) keeps the
	// total claims across all slots exactly bounded by maxClaims instead of overshooting by up to
	// concurrency-1, and there is no await between the check and the increment so the count stays consistent.
	function reserve(): 'max_claims' | 'time_budget' | null {
		if (result.claimed >= maxClaims) return 'max_claims';
		if (now() >= deadline) return 'time_budget';
		result.claimed += 1;
		return null;
	}

	async function slot(): Promise<void> {
		while (stopped === null) {
			const blocked = reserve();
			if (blocked) {
				stopped ??= blocked;
				return;
			}

			let outcome: DrainProcessResult;
			try {
				outcome = await processOne();
			} catch (error) {
				// The reservation never produced a real send; release it so counts stay truthful, then let the
				// infrastructure error surface to the caller (the route turns it into a 500).
				result.claimed -= 1;
				throw error;
			}

			if (outcome.status === 'idle') {
				// Nothing was claimable: release the reservation and mark the queue drained.
				result.claimed -= 1;
				stopped ??= 'idle';
				return;
			}

			if (outcome.status === 'submitted') result.submitted += 1;
			else if (outcome.status === 'retry') result.retried += 1;
			else if (outcome.status === 'cancelled') result.cancelled += 1;
			else result.submissionUnknown += 1;
		}
	}

	await Promise.all(Array.from({ length: concurrency }, () => slot()));
	result.stoppedBy = stopped ?? 'idle';
	return result;
}
