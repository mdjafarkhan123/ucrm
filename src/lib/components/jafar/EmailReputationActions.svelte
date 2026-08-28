<script lang="ts">
	import { createMutation, createQuery, useQueryClient } from '@tanstack/svelte-query';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import Badge from '$lib/components/ui/Badge.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Checkbox from '$lib/components/ui/Checkbox.svelte';
	import ConfirmDialog from '$lib/components/ui/ConfirmDialog.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import Textarea from '$lib/components/ui/Textarea.svelte';

	type Metric = {
		signal: 'complaint' | 'hard_bounce' | 'unsubscribe';
		window_key: 'rolling_24h' | 'rolling_7d';
		accepted_recipients: number;
		event_count: number;
		rate: number | null;
		warn_rate: number;
		pause_rate: number;
		min_sample_recipients: number;
		min_event_count: number | null;
		status: 'ok' | 'warn' | 'pause';
	};
	type Override = {
		id: string;
		signal: Metric['signal'];
		window_key: Metric['window_key'];
		warn_rate: number | null;
		pause_rate: number | null;
		reason: string;
	};
	type Reputation = {
		metrics: Metric[];
		overrides: Override[];
		reputation_pause: {
			id: string;
			reason: string;
			engaged_at: string;
			evidence: Record<string, unknown> | null;
		} | null;
		state: { worst_status: 'ok' | 'warn' | 'pause'; evaluated_at: string } | null;
	};
	type ReputationResponse = { reputation: Reputation; error?: string };

	let { organizationId }: { organizationId: string } = $props();

	const queryClient = useQueryClient();
	const toast = getToastManager();
	const reputationKey = $derived(['jafar', 'organizations', organizationId, 'email-reputation']);
	const endpoint = $derived(`/api/jafar/organizations/${organizationId}/communications/reputation`);

	const reputationQuery = createQuery<ReputationResponse>(() => ({
		queryKey: reputationKey,
		queryFn: async () => {
			const response = await fetch(endpoint);
			const result = (await response.json()) as ReputationResponse;
			if (!response.ok)
				throw new Error(result.error ?? 'The email reputation could not be loaded.');
			return result;
		},
		staleTime: 30_000
	}));

	const reputation = $derived(reputationQuery.data?.reputation ?? null);
	const metrics = $derived(reputation?.metrics ?? []);
	const worstStatus = $derived(reputation?.state?.worst_status ?? 'ok');
	const autoPause = $derived(reputation?.reputation_pause ?? null);

	const signalLabels: Record<Metric['signal'], string> = {
		complaint: 'Spam complaints',
		hard_bounce: 'Hard bounces',
		unsubscribe: 'Unsubscribes'
	};
	const windowLabels: Record<Metric['window_key'], string> = {
		rolling_24h: 'Last 24 hours',
		rolling_7d: 'Last 7 days'
	};
	const statusTone = { ok: 'success', warn: 'warning', pause: 'critical' } as const;
	const statusLabel = { ok: 'Healthy', warn: 'Watch', pause: 'Over the limit' } as const;

	function overrideFor(metric: Metric) {
		return reputation?.overrides.find(
			(entry) => entry.signal === metric.signal && entry.window_key === metric.window_key
		);
	}

	function formatRate(value: number | null) {
		return value === null ? '—' : `${Number(value).toFixed(2)}%`;
	}

	function formatDateTime(value: string) {
		return new Intl.DateTimeFormat(undefined, { dateStyle: 'medium', timeStyle: 'short' }).format(
			new Date(value)
		);
	}

	// --- Tightening a single threshold for this organization ------------------------------------

	let overrideMetric = $state<Metric | null>(null);
	let overrideWarn = $state('');
	let overridePause = $state('');
	let overrideReason = $state('');
	const overrideReasonValid = $derived(overrideReason.trim().length >= 3);

	function openOverride(metric: Metric) {
		const existing = overrideFor(metric);
		overrideMetric = metric;
		overrideWarn = existing?.warn_rate === undefined ? '' : String(existing?.warn_rate ?? '');
		overridePause = existing?.pause_rate === undefined ? '' : String(existing?.pause_rate ?? '');
		overrideReason = '';
	}

	function closeOverride() {
		overrideMetric = null;
		overrideReason = '';
	}

	// `<Input type="number">` can hand back either a string or a coerced number depending on how the
	// binding resolves, so normalise whatever comes in.
	function numberOrNull(value: string | number | null | undefined) {
		if (value === null || value === undefined) return null;
		const trimmed = String(value).trim();
		if (trimmed === '') return null;
		const parsed = Number(trimmed);
		return Number.isFinite(parsed) ? parsed : null;
	}

	const overrideMutation = createMutation<ReputationResponse, Error, void>(() => ({
		mutationFn: async () => {
			const metric = overrideMetric;
			if (!metric) throw new Error('Choose a threshold to change.');
			const response = await fetch(endpoint, {
				method: 'POST',
				headers: { 'content-type': 'application/json' },
				body: JSON.stringify({
					signal: metric.signal,
					window_key: metric.window_key,
					warn_rate: numberOrNull(overrideWarn),
					pause_rate: numberOrNull(overridePause),
					reason: overrideReason.trim()
				})
			});
			const result = (await response.json()) as ReputationResponse;
			if (!response.ok)
				throw new Error(result.error ?? 'The reputation override could not be changed.');
			return result;
		},
		onSuccess: (data) => {
			closeOverride();
			queryClient.setQueryData<ReputationResponse>(reputationKey, data);
			toast.success('The reputation limit for this organization is saved.');
		},
		onError: (error) => toast.error(error.message)
	}));

	// --- Resuming the automatic pause ------------------------------------------------------------

	let resumeOpen = $state(false);
	let resumeReason = $state('');
	let resumeConfirmed = $state(false);
	const resumeReasonValid = $derived(resumeReason.trim().length >= 3);

	const resumeMutation = createMutation<ReputationResponse & { result?: unknown }, Error, void>(
		() => ({
			mutationFn: async () => {
				const response = await fetch(`${endpoint}/resume`, {
					method: 'POST',
					headers: { 'content-type': 'application/json' },
					body: JSON.stringify({
						reason: resumeReason.trim(),
						confirm_remediation: resumeConfirmed
					})
				});
				const result = (await response.json()) as ReputationResponse;
				if (!response.ok)
					throw new Error(result.error ?? 'The automatic pause could not be resumed.');
				return result;
			},
			onSuccess: async (data) => {
				resumeOpen = false;
				resumeReason = '';
				resumeConfirmed = false;
				queryClient.setQueryData<ReputationResponse>(reputationKey, {
					reputation: data.reputation
				});
				toast.success('Optional email has resumed for this organization.');
				await queryClient.invalidateQueries({
					queryKey: ['jafar', 'communications', 'email-reputation']
				});
			},
			onError: (error) => toast.error(error.message)
		})
	);
</script>

<div class="email-reputation">
	<div class="email-reputation__heading">
		<div>
			<h3>Sending reputation</h3>
			<p>
				How this organization's recipients are reacting. If complaints or bounces cross the limit,
				marketing-style follow-ups pause on their own — quotes, invoices, and replies keep going.
			</p>
		</div>
		{#if !reputationQuery.isPending && !reputationQuery.isError}
			<Badge status={statusTone[worstStatus]}>{statusLabel[worstStatus]}</Badge>
		{/if}
	</div>

	{#if reputationQuery.isPending}
		<LoadingSkeleton variant="table" rows={3} label="Loading sending reputation" />
	{:else if reputationQuery.isError}
		<ErrorState
			title="Sending reputation could not be loaded"
			description={reputationQuery.error instanceof Error
				? reputationQuery.error.message
				: 'Try again.'}
			retry={() => reputationQuery.refetch()}
		/>
	{:else if reputation}
		{#if autoPause}
			<div class="email-reputation__pause">
				<p class="email-reputation__pause-reason">{autoPause.reason}</p>
				<p class="email-reputation__pause-meta">
					Paused automatically on {formatDateTime(autoPause.engaged_at)}. Only you can resume it.
				</p>
				<div class="email-reputation__actions">
					<Button
						size="small"
						variant="secondary"
						variation="subtle"
						onclick={() => {
							resumeOpen = true;
							resumeReason = '';
							resumeConfirmed = false;
						}}
					>
						Resume optional email
					</Button>
				</div>
			</div>
		{/if}

		<div class="email-reputation__table-wrap">
			<table class="email-reputation__table">
				<thead>
					<tr>
						<th scope="col">Signal</th>
						<th scope="col">Window</th>
						<th scope="col">Rate</th>
						<th scope="col">Warn at</th>
						<th scope="col">Pause at</th>
						<th scope="col">Status</th>
						<th scope="col"><span class="email-reputation__sr-only">Change limit</span></th>
					</tr>
				</thead>
				<tbody>
					{#each metrics as metric (metric.signal + metric.window_key)}
						<tr>
							<th scope="row">{signalLabels[metric.signal]}</th>
							<td>{windowLabels[metric.window_key]}</td>
							<td>
								{formatRate(metric.rate)}
								<span class="email-reputation__sample">
									{metric.event_count} of {metric.accepted_recipients}
								</span>
							</td>
							<td>{formatRate(metric.warn_rate)}</td>
							<td>
								{formatRate(metric.pause_rate)}
								{#if overrideFor(metric)}
									<span class="email-reputation__sample">Tightened for this organization</span>
								{/if}
							</td>
							<td>
								<Badge status={statusTone[metric.status]}>{statusLabel[metric.status]}</Badge>
							</td>
							<td class="email-reputation__row-action">
								<Button
									size="small"
									variant="secondary"
									variation="subtle"
									onclick={() => openOverride(metric)}
								>
									Change limit
								</Button>
							</td>
						</tr>
					{/each}
				</tbody>
			</table>
		</div>
	{/if}
</div>

<ConfirmDialog
	open={overrideMetric !== null}
	title="Tighten this organization's limit"
	confirmLabel="Save limit"
	loading={overrideMutation.isPending}
	confirmDisabled={!overrideReasonValid || overrideMutation.isPending}
	onConfirm={() => {
		if (overrideReasonValid) overrideMutation.mutate();
	}}
	onClose={closeOverride}
>
	<p>
		A limit here can only be stricter than the platform limit, never looser. Leave a box empty to
		follow the platform figure; empty both to remove this organization's limit entirely.
	</p>
	<div class="email-reputation__fields">
		<Input
			id="reputation-override-warn"
			label="Warn at (%)"
			type="number"
			step="0.01"
			min="0"
			bind:value={overrideWarn}
		/>
		<Input
			id="reputation-override-pause"
			label="Pause at (%)"
			type="number"
			step="0.01"
			min="0"
			bind:value={overridePause}
		/>
	</div>
	<Textarea
		id="reputation-override-reason"
		label="Reason (kept in the owner audit log)"
		bind:value={overrideReason}
		rows={3}
		maxlength={500}
		required
	/>
</ConfirmDialog>

<ConfirmDialog
	open={resumeOpen}
	title="Resume optional email"
	tone="success"
	confirmLabel="Resume optional email"
	loading={resumeMutation.isPending}
	confirmDisabled={!resumeReasonValid || resumeMutation.isPending}
	onConfirm={() => {
		if (resumeReasonValid) resumeMutation.mutate();
	}}
	onClose={() => {
		resumeOpen = false;
		resumeReason = '';
		resumeConfirmed = false;
	}}
>
	<p>
		Optional follow-ups start flowing again on the outbox worker's next run. Anything that has been
		waiting more than 24 hours is cancelled rather than sent late.
	</p>
	<Checkbox
		id="reputation-resume-confirm"
		label="I have reviewed what this organization fixed"
		description="Required while the rate is still at or above the pause limit."
		bind:checked={resumeConfirmed}
	/>
	<Textarea
		id="reputation-resume-reason"
		label="Reason (kept in the owner audit log)"
		bind:value={resumeReason}
		rows={3}
		maxlength={500}
		required
	/>
</ConfirmDialog>

<style lang="scss">
	.email-reputation {
		display: grid;
		gap: var(--space-base);
	}

	.email-reputation__heading {
		display: flex;
		align-items: flex-start;
		justify-content: space-between;
		gap: var(--space-base);

		h3 {
			color: var(--color-heading);
			font-size: var(--typography--fontSize-large);
		}

		p {
			margin-top: var(--space-small);
			color: var(--color-text--secondary);
			line-height: var(--typography--lineHeight-base);
		}
	}

	.email-reputation__pause {
		display: grid;
		gap: var(--space-small);
		padding: var(--space-base);
		border: var(--border-base) solid var(--color-border);
		border-left: var(--border-thick) solid var(--color-critical);
		border-radius: var(--radius-base);
		background: var(--color-surface--background);
	}

	.email-reputation__pause-reason {
		color: var(--color-text);
		line-height: var(--typography--lineHeight-base);
	}

	.email-reputation__pause-meta {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}

	.email-reputation__actions {
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-small);
	}

	.email-reputation__table-wrap {
		overflow-x: auto;
	}

	.email-reputation__table {
		width: 100%;
		border-collapse: collapse;
		font-size: var(--typography--fontSize-small);

		th,
		td {
			padding: var(--space-small) var(--space-smaller);
			border-bottom: var(--border-base) solid var(--color-border);
			text-align: left;
			vertical-align: top;
		}

		thead th {
			color: var(--color-text--secondary);
			font-weight: var(--typography--fontWeight-semibold);
			white-space: nowrap;
		}

		tbody th {
			color: var(--color-text);
			font-weight: var(--typography--fontWeight-semibold);
		}

		tbody td {
			color: var(--color-text);
		}
	}

	.email-reputation__sample {
		display: block;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-smaller);
	}

	.email-reputation__row-action {
		text-align: right;
		white-space: nowrap;
	}

	.email-reputation__fields {
		display: grid;
		grid-template-columns: repeat(2, minmax(0, 1fr));
		gap: var(--space-base);
	}

	.email-reputation__sr-only {
		position: absolute;
		width: 1px;
		height: 1px;
		overflow: hidden;
		clip-path: inset(50%);
		white-space: nowrap;
	}

	@media (max-width: 639px) {
		.email-reputation__heading {
			flex-direction: column;
		}

		.email-reputation__fields {
			grid-template-columns: 1fr;
		}
	}
</style>
