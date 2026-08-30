<script lang="ts">
	import alertIcon from '@tabler/icons/outline/alert-triangle.svg?raw';
	import checkIcon from '@tabler/icons/outline/circle-check.svg?raw';
	import clockIcon from '@tabler/icons/outline/clock.svg?raw';
	import refreshIcon from '@tabler/icons/outline/refresh.svg?raw';
	import Badge from '$lib/components/ui/Badge.svelte';
	import Card from '$lib/components/ui/Card.svelte';
	import EmptyState from '$lib/components/data-display/EmptyState.svelte';
	import KpiCard from '$lib/components/data-display/KpiCard.svelte';

	type WorkerJob = { active: boolean; schedule: string } | null;
	type WorkerLastRun = {
		status: string | null;
		ran_at: string | null;
		finished_at: string | null;
	} | null;
	type WorkerWake = {
		dispatched_at: string;
		finished_at: string | null;
		route_outcome: string | null;
		claimed: number | null;
		submitted: number | null;
		retried: number | null;
		submission_unknown: number | null;
		http_status: number | null;
		http_timed_out: boolean | null;
		http_error: string | null;
	};
	export type WorkerHealth = {
		worker_name: string;
		job_name: string;
		warn_oldest_due_seconds: number;
		critical_oldest_due_seconds: number;
		job: WorkerJob;
		last_run: WorkerLastRun;
		last_successful_drain_at: string | null;
		recent_wakes: WorkerWake[];
		recent_failed_wakes: number;
		due_count: number;
		oldest_due_age_seconds: number | null;
		processing_count: number;
		oldest_claim_age_seconds: number | null;
		submission_unknown_count: number;
		recent_capped_wakes: number;
	};

	let { workerHealth }: { workerHealth: WorkerHealth | null } = $props();

	const installed = $derived(Boolean(workerHealth?.job));
	const jobActive = $derived(workerHealth?.job?.active === true);

	// Overall drain status. Cron running is never shown as success on its own — the badge follows the actual
	// worker outcomes (real HTTP results, oldest-due age, unknown provider outcomes), per the A1 plan.
	type StatusTone = 'success' | 'warning' | 'critical' | 'inactive' | 'informative';
	const status = $derived.by((): { label: string; tone: StatusTone; note: string } => {
		const w = workerHealth;
		if (!w || !w.job) {
			return {
				label: 'Not installed',
				tone: 'inactive',
				note: 'The once-a-minute wake job is not scheduled yet.'
			};
		}
		if (!w.job.active) {
			return {
				label: 'Paused',
				tone: 'warning',
				note: 'The wake job is installed but switched off — nothing is draining automatically.'
			};
		}
		if (w.recent_failed_wakes >= 2) {
			return {
				label: 'Not responding',
				tone: 'critical',
				note: 'The last wakes did not reach the worker or came back with an error. Check the app and tunnel.'
			};
		}
		const age = w.oldest_due_age_seconds ?? 0;
		if (w.due_count > 0 && age >= w.critical_oldest_due_seconds) {
			return {
				label: 'Falling behind',
				tone: 'critical',
				note: 'Email has been waiting longer than the critical threshold.'
			};
		}
		if (w.due_count > 0 && age >= w.warn_oldest_due_seconds) {
			return {
				label: 'Slow',
				tone: 'warning',
				note: 'Email is waiting longer than expected but under the critical threshold.'
			};
		}
		if (!w.last_successful_drain_at && w.recent_wakes.length === 0) {
			return {
				label: 'Waiting for first run',
				tone: 'informative',
				note: 'The job is on. No wake has been recorded yet.'
			};
		}
		return { label: 'Running', tone: 'success', note: 'Email is draining on schedule.' };
	});

	const outcomeLabels: Record<string, string> = {
		idle: 'Idle — nothing due',
		max_claims: 'Stopped at claim cap',
		time_budget: 'Stopped at time budget',
		already_running: 'Skipped — already running',
		route_deadline: 'Hit route deadline',
		error: 'Error'
	};
	function outcomeLabel(value: string | null) {
		if (!value) return 'Unknown';
		return outcomeLabels[value] ?? value;
	}
	function outcomeIsClean(w: WorkerWake) {
		const okStatus = w.http_status !== null && w.http_status >= 200 && w.http_status <= 299;
		return okStatus && w.route_outcome !== null && w.route_outcome !== 'error' && !w.http_timed_out;
	}

	function formatDateTime(value: string | null) {
		if (!value) return '—';
		return new Intl.DateTimeFormat(undefined, { dateStyle: 'medium', timeStyle: 'short' }).format(
			new Date(value)
		);
	}
	function formatRelative(value: string | null) {
		if (!value) return 'Never';
		const seconds = Math.round((Date.now() - new Date(value).getTime()) / 1000);
		if (seconds < 45) return 'Just now';
		if (seconds < 90) return '1 min ago';
		if (seconds < 3600) return `${Math.round(seconds / 60)} min ago`;
		if (seconds < 5400) return '1 hr ago';
		if (seconds < 86400) return `${Math.round(seconds / 3600)} hr ago`;
		return `${Math.round(seconds / 86400)} days ago`;
	}
	function formatDuration(seconds: number | null) {
		if (seconds === null) return '—';
		if (seconds < 60) return `${seconds}s`;
		const mins = Math.floor(seconds / 60);
		if (mins < 60) {
			const rem = seconds % 60;
			return rem === 0 ? `${mins}m` : `${mins}m ${rem}s`;
		}
		const hrs = Math.floor(mins / 60);
		const remMins = mins % 60;
		return remMins === 0 ? `${hrs}h` : `${hrs}h ${remMins}m`;
	}
	function formatHttp(w: WorkerWake) {
		if (w.http_timed_out) return 'Timed out';
		if (w.http_status !== null) return String(w.http_status);
		if (w.http_error) return 'Error';
		return '—';
	}

	// KPI tones mirror the Badge tone but use KpiCard's own scale.
	type KpiTone = 'default' | 'success' | 'warning' | 'informative' | 'critical';
	const dueTone = $derived.by((): KpiTone => {
		const w = workerHealth;
		if (!w || w.due_count === 0) return 'default';
		const age = w.oldest_due_age_seconds ?? 0;
		if (age >= w.critical_oldest_due_seconds) return 'critical';
		if (age >= w.warn_oldest_due_seconds) return 'warning';
		return 'informative';
	});
	const statusKpiTone = $derived.by((): KpiTone => {
		const t = status.tone;
		return t === 'inactive' ? 'default' : t;
	});
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<div class="worker-health">
	<Card class="worker-health__card">
		<div class="worker-health__head">
			<div>
				<h2>Automatic outbox drain</h2>
				<p>
					A once-a-minute wake keeps operational email — quotes, invoices, receipts, replies —
					moving out of the outbox on its own. This shows whether that wake is actually reaching the
					worker and clearing the queue, not just whether the schedule fired.
				</p>
			</div>
			<Badge status={status.tone === 'inactive' ? 'inactive' : status.tone}>{status.label}</Badge>
		</div>

		{#if !workerHealth}
			<EmptyState
				title="Drain health is unavailable"
				description="The worker health check did not return. Reload to try again."
			/>
		{:else}
			<p class="worker-health__status-note">{status.note}</p>

			<section class="worker-health__summary" aria-label="Automatic drain summary">
				<KpiCard
					label="Auto-drain"
					value={status.label}
					note={installed
						? jobActive
							? (workerHealth.job?.schedule ?? 'Scheduled')
							: 'Switched off'
						: 'Not scheduled yet'}
					icon={refreshIcon}
					tone={statusKpiTone}
					variant="compact"
				/>
				<KpiCard
					label="Waiting to send"
					value={String(workerHealth.due_count)}
					note={workerHealth.due_count > 0
						? `Oldest ${formatDuration(workerHealth.oldest_due_age_seconds)}`
						: 'Queue is clear'}
					icon={clockIcon}
					tone={dueTone}
					variant="compact"
				/>
				<KpiCard
					label="Last cleared"
					value={formatRelative(workerHealth.last_successful_drain_at)}
					note={workerHealth.last_successful_drain_at
						? formatDateTime(workerHealth.last_successful_drain_at)
						: 'No successful drain yet'}
					icon={checkIcon}
					tone={workerHealth.last_successful_drain_at ? 'success' : 'default'}
					variant="compact"
				/>
				<KpiCard
					label="Needs review"
					value={String(workerHealth.submission_unknown_count)}
					note="Unknown provider outcome"
					icon={alertIcon}
					tone={workerHealth.submission_unknown_count > 0 ? 'warning' : 'default'}
					variant="compact"
				/>
			</section>

			<dl class="worker-health__detail">
				<div>
					<dt>Schedule job</dt>
					<dd>
						{#if installed}
							<Badge status={jobActive ? 'success' : 'inactive'} size="small">
								{jobActive ? 'Active' : 'Inactive'}
							</Badge>
							<span class="worker-health__mono">{workerHealth.job?.schedule}</span>
						{:else}
							Not installed
						{/if}
					</dd>
				</div>
				<div>
					<dt>Last scheduled run</dt>
					<dd>
						{#if workerHealth.last_run}
							{workerHealth.last_run.status ?? 'unknown'} · {formatRelative(
								workerHealth.last_run.ran_at
							)}
						{:else}
							—
						{/if}
					</dd>
				</div>
				<div>
					<dt>Being sent now</dt>
					<dd>
						{workerHealth.processing_count}
						{#if workerHealth.processing_count > 0}
							· oldest {formatDuration(workerHealth.oldest_claim_age_seconds)}
						{/if}
					</dd>
				</div>
			</dl>

			{#if workerHealth.recent_capped_wakes > 0}
				<p class="worker-health__pressure">
					{workerHealth.recent_capped_wakes} of the last 10 wakes hit the claim cap or time budget. If
					this keeps up, measure before raising the limits — it is not an automatic signal to add concurrency.
				</p>
			{/if}

			{#if workerHealth.recent_wakes.length === 0}
				<EmptyState
					title="No wakes recorded yet"
					description="Once the job runs, each wake and its real result will appear here."
				/>
			{:else}
				<div class="worker-health__table-wrap">
					<table class="worker-health__table">
						<thead>
							<tr>
								<th scope="col">When</th>
								<th scope="col">Result</th>
								<th scope="col">HTTP</th>
								<th scope="col">Claimed</th>
								<th scope="col">Sent</th>
								<th scope="col">Retried</th>
								<th scope="col">Unknown</th>
							</tr>
						</thead>
						<tbody>
							{#each workerHealth.recent_wakes as wake (wake.dispatched_at)}
								<tr>
									<th scope="row" title={formatDateTime(wake.dispatched_at)}>
										{formatRelative(wake.dispatched_at)}
									</th>
									<td>{outcomeLabel(wake.route_outcome)}</td>
									<td>
										<span
											class="worker-health__http"
											class:worker-health__http--bad={!outcomeIsClean(wake)}
											title={wake.http_error ?? undefined}
										>
											{formatHttp(wake)}
										</span>
									</td>
									<td>{wake.claimed ?? '—'}</td>
									<td>{wake.submitted ?? '—'}</td>
									<td>{wake.retried ?? '—'}</td>
									<td>{wake.submission_unknown ?? '—'}</td>
								</tr>
							{/each}
						</tbody>
					</table>
				</div>
			{/if}
		{/if}
	</Card>
</div>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.worker-health :global(.worker-health__card) {
		display: grid;
		gap: var(--space-base);
	}

	.worker-health h2 {
		margin: 0;
		color: var(--color-heading);
		font-size: var(--typography--fontSize-largest);
		line-height: var(--typography--lineHeight-tightest);
	}

	.worker-health__head {
		display: flex;
		align-items: flex-start;
		justify-content: space-between;
		gap: var(--space-base);

		p {
			margin: var(--space-small) 0 0;
			max-width: 70ch;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			line-height: var(--typography--lineHeight-base);
		}
	}

	.worker-health__status-note {
		margin: 0;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		line-height: var(--typography--lineHeight-base);
	}

	.worker-health__summary {
		display: grid;
		grid-template-columns: repeat(4, minmax(0, 1fr));
		gap: var(--space-base);
	}

	.worker-health__detail {
		display: grid;
		grid-template-columns: repeat(3, minmax(0, 1fr));
		gap: var(--space-base);
		margin: 0;

		> div {
			display: grid;
			gap: var(--space-smallest);
		}

		dt {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		dd {
			display: flex;
			align-items: center;
			gap: var(--space-small);
			margin: 0;
			color: var(--color-text);
			font-size: var(--typography--fontSize-small);
			overflow-wrap: anywhere;
		}
	}

	.worker-health__mono {
		font-family: var(--typography--fontFamily-mono, monospace);
	}

	.worker-health__pressure {
		margin: 0;
		padding: var(--space-base);
		border: var(--border-base) solid var(--color-warning--onSurface);
		border-radius: var(--radius-base);
		background: var(--color-warning--surface);
		color: var(--color-warning--onSurface);
		font-size: var(--typography--fontSize-small);
		line-height: var(--typography--lineHeight-base);
	}

	.worker-health__table-wrap {
		overflow-x: auto;
	}

	.worker-health__table {
		width: 100%;
		min-width: 640px;
		border-collapse: collapse;
		color: var(--color-text);
		font-size: var(--typography--fontSize-small);

		th,
		td {
			padding: var(--space-base);
			border-bottom: var(--border-base) solid var(--color-border);
			text-align: left;
			vertical-align: top;
			white-space: nowrap;
		}

		thead th {
			color: var(--color-text--secondary);
			font-weight: 700;
		}

		tbody th {
			color: var(--color-heading);
			font-weight: 700;
		}

		tbody tr:last-child th,
		tbody tr:last-child td {
			border-bottom: 0;
		}
	}

	.worker-health__http--bad {
		color: var(--color-critical--onSurface);
		font-weight: 700;
	}

	@media (max-width: 1200px) {
		.worker-health__summary {
			grid-template-columns: repeat(2, minmax(0, 1fr));
		}
	}

	@media (max-width: 900px) {
		.worker-health__detail {
			grid-template-columns: 1fr;
		}
	}

	@media (max-width: 639px) {
		.worker-health__summary {
			grid-template-columns: 1fr;
		}

		.worker-health__head {
			flex-direction: column;
		}
	}
</style>
