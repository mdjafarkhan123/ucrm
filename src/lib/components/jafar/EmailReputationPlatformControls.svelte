<script lang="ts">
	import { createMutation, createQuery, useQueryClient } from '@tanstack/svelte-query';
	import { resolve } from '$app/paths';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import Badge from '$lib/components/ui/Badge.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Card from '$lib/components/ui/Card.svelte';
	import Checkbox from '$lib/components/ui/Checkbox.svelte';
	import ConfirmDialog from '$lib/components/ui/ConfirmDialog.svelte';
	import EmptyState from '$lib/components/data-display/EmptyState.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import Textarea from '$lib/components/ui/Textarea.svelte';

	type Signal = 'complaint' | 'hard_bounce' | 'unsubscribe';
	type WindowKey = 'rolling_24h' | 'rolling_7d';

	type Threshold = {
		id: string;
		signal: Signal;
		window_key: WindowKey;
		window_hours: number;
		warn_rate: number;
		pause_rate: number;
		min_sample_recipients: number;
		min_event_count: number | null;
		reason: string;
		actor_owner_email: string;
		effective_from: string;
	};
	type AttentionOrg = {
		organization_id: string;
		organization_name: string;
		worst_status: 'ok' | 'warn' | 'pause';
		evaluated_at: string;
		last_breach_at: string | null;
		reputation_pause_id: string | null;
	};
	type Overview = {
		platform_thresholds: Threshold[];
		attention_total: number;
		attention_limit: number;
		attention: AttentionOrg[];
	};
	type OverviewResponse = { overview: Overview; error?: string };
	type ChangeResponse = OverviewResponse & {
		result?: { organization_overrides_affected?: number };
	};

	const queryClient = useQueryClient();
	const toast = getToastManager();
	const overviewKey = ['jafar', 'communications', 'email-reputation'] as const;

	const overviewQuery = createQuery<OverviewResponse>(() => ({
		queryKey: overviewKey,
		queryFn: async () => {
			const response = await fetch('/api/jafar/communications/email-reputation');
			const result = (await response.json()) as OverviewResponse;
			if (!response.ok)
				throw new Error(result.error ?? 'The email reputation overview could not be loaded.');
			return result;
		},
		staleTime: 30_000
	}));

	const overview = $derived(overviewQuery.data?.overview ?? null);
	const thresholds = $derived(overview?.platform_thresholds ?? []);
	const attention = $derived(overview?.attention ?? []);
	const attentionTotal = $derived(overview?.attention_total ?? 0);
	const attentionCapped = $derived(attentionTotal > attention.length);

	const signalLabels: Record<Signal, string> = {
		complaint: 'Spam complaints',
		hard_bounce: 'Hard bounces',
		unsubscribe: 'Unsubscribes'
	};
	const windowLabels: Record<WindowKey, string> = {
		rolling_24h: 'Last 24 hours',
		rolling_7d: 'Last 7 days'
	};
	const statusTone = { ok: 'success', warn: 'warning', pause: 'critical' } as const;
	const statusLabel = { ok: 'Healthy', warn: 'Watch', pause: 'Over the limit' } as const;

	function formatRate(value: number | null) {
		return value === null ? '—' : `${Number(value).toFixed(2)}%`;
	}
	function formatCount(value: number | null) {
		return value === null ? '—' : new Intl.NumberFormat().format(value);
	}
	function formatDateTime(value: string) {
		return new Intl.DateTimeFormat(undefined, { dateStyle: 'medium', timeStyle: 'short' }).format(
			new Date(value)
		);
	}

	// --- Changing a platform threshold ----------------------------------------------------------

	let changeTarget = $state<Threshold | null>(null);
	let warnRate = $state('');
	let pauseRate = $state('');
	let minSample = $state('');
	let minEvent = $state('');
	let windowHours = $state('');
	let reason = $state('');
	let confirmed = $state(false);

	const reasonValid = $derived(reason.trim().length >= 3);

	function openChange(threshold: Threshold) {
		changeTarget = threshold;
		warnRate = String(Number(threshold.warn_rate));
		pauseRate = String(Number(threshold.pause_rate));
		minSample = String(threshold.min_sample_recipients);
		minEvent = threshold.min_event_count === null ? '' : String(threshold.min_event_count);
		windowHours = String(threshold.window_hours);
		reason = '';
		confirmed = false;
	}
	function closeChange() {
		changeTarget = null;
		reason = '';
		confirmed = false;
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

	const overrideMutation = createMutation<ChangeResponse, Error, void>(() => ({
		mutationFn: async () => {
			const target = changeTarget;
			if (!target) throw new Error('Choose a threshold to change.');
			const response = await fetch('/api/jafar/communications/email-reputation', {
				method: 'POST',
				headers: { 'content-type': 'application/json' },
				body: JSON.stringify({
					signal: target.signal,
					window_key: target.window_key,
					window_hours: numberOrNull(windowHours),
					warn_rate: numberOrNull(warnRate),
					pause_rate: numberOrNull(pauseRate),
					min_sample_recipients: numberOrNull(minSample),
					min_event_count: numberOrNull(minEvent),
					reason: reason.trim(),
					confirm_platform_change: confirmed
				})
			});
			const result = (await response.json()) as ChangeResponse;
			if (!response.ok)
				throw new Error(result.error ?? 'The platform threshold could not be changed.');
			return result;
		},
		onSuccess: (data) => {
			closeChange();
			if (data.overview)
				queryClient.setQueryData<OverviewResponse>(overviewKey, { overview: data.overview });
			const affected = data.result?.organization_overrides_affected ?? 0;
			toast.success(
				affected === 0
					? 'The platform reputation limit is saved.'
					: `The platform reputation limit is saved. ${affected} organization override${
							affected === 1 ? '' : 's'
						} now sit under a lower ceiling.`
			);
			void queryClient.invalidateQueries({
				predicate: (query) =>
					query.queryKey[0] === 'jafar' &&
					query.queryKey[1] === 'organizations' &&
					query.queryKey[3] === 'email-reputation'
			});
		},
		onError: (error) => toast.error(error.message)
	}));

	const canSubmit = $derived(reasonValid && confirmed && !overrideMutation.isPending);
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<div class="reputation-controls">
	<Card class="reputation-controls__card">
		<div class="reputation-controls__head">
			<h2>Delivery reputation limits</h2>
			<p>
				Every organization is measured against these rates. Crossing a pause limit pauses that
				organization's marketing-style follow-ups on its own — quotes, invoices, and replies keep
				going. A limit set here is the ceiling; an organization can be held to something stricter
				from its own page, never looser.
			</p>
		</div>

		{#if overviewQuery.isPending}
			<LoadingSkeleton variant="table" rows={6} label="Loading reputation limits" />
		{:else if overviewQuery.isError}
			<ErrorState
				title="Reputation limits could not be loaded"
				description={overviewQuery.error instanceof Error
					? overviewQuery.error.message
					: 'Try again.'}
				retry={() => overviewQuery.refetch()}
			/>
		{:else if overview}
			<div class="reputation-controls__table-wrap">
				<table class="reputation-controls__table">
					<thead>
						<tr>
							<th scope="col">Signal</th>
							<th scope="col">Window</th>
							<th scope="col">Warn at</th>
							<th scope="col">Pause at</th>
							<th scope="col">Min sample</th>
							<th scope="col">Early trigger</th>
							<th scope="col"><span class="reputation-controls__sr-only">Change limit</span></th>
						</tr>
					</thead>
					<tbody>
						{#each thresholds as threshold (threshold.id)}
							<tr>
								<th scope="row">{signalLabels[threshold.signal]}</th>
								<td>{windowLabels[threshold.window_key]}</td>
								<td>{formatRate(threshold.warn_rate)}</td>
								<td>{formatRate(threshold.pause_rate)}</td>
								<td>{formatCount(threshold.min_sample_recipients)} recipients</td>
								<td>
									{threshold.min_event_count === null
										? 'None'
										: `${formatCount(threshold.min_event_count)} events`}
								</td>
								<td class="reputation-controls__row-action">
									<Button
										size="small"
										variant="secondary"
										variation="subtle"
										onclick={() => openChange(threshold)}
									>
										Change
									</Button>
								</td>
							</tr>
						{/each}
					</tbody>
				</table>
			</div>
		{/if}
	</Card>

	{#if overview}
		<Card class="reputation-controls__card">
			<div class="reputation-controls__head">
				<h2>Organizations to watch</h2>
				<p>
					{#if attentionTotal === 0}
						Every organization's delivery reputation is within its limits.
					{:else if attentionCapped}
						Showing the {attention.length} most urgent of {formatCount(attentionTotal)}. Worst
						first.
					{:else}
						{formatCount(attentionTotal)} organization{attentionTotal === 1 ? ' is' : 's are'} at a warning
						or over a pause limit right now.
					{/if}
				</p>
			</div>

			{#if attention.length === 0}
				<EmptyState
					title="Nothing needs a look"
					description="No organization is at a warning or over a pause limit."
				/>
			{:else}
				<div class="reputation-controls__table-wrap">
					<table class="reputation-controls__table">
						<thead>
							<tr>
								<th scope="col">Organization</th>
								<th scope="col">Status</th>
								<th scope="col">Auto-pause</th>
								<th scope="col">Last checked</th>
							</tr>
						</thead>
						<tbody>
							{#each attention as org (org.organization_id)}
								<tr>
									<th scope="row">
										<a href={resolve(`/jafar/organizations/${org.organization_id}`)}>
											{org.organization_name}
										</a>
									</th>
									<td>
										<Badge status={statusTone[org.worst_status]}>
											{statusLabel[org.worst_status]}
										</Badge>
									</td>
									<td>{org.reputation_pause_id ? 'Optional email paused' : '—'}</td>
									<td>{formatDateTime(org.evaluated_at)}</td>
								</tr>
							{/each}
						</tbody>
					</table>
				</div>
			{/if}
		</Card>
	{/if}
</div>
<!-- eslint-enable svelte/no-at-html-tags -->

<ConfirmDialog
	open={changeTarget !== null}
	title="Change the platform reputation limit"
	tone="critical"
	confirmLabel="Save limit"
	loading={overrideMutation.isPending}
	confirmDisabled={!canSubmit}
	onConfirm={() => {
		if (canSubmit) overrideMutation.mutate();
	}}
	onClose={closeChange}
>
	<p>
		{#if changeTarget}
			This is the safety ceiling for <strong>{signalLabels[changeTarget.signal]}</strong> over
			{windowLabels[changeTarget.window_key].toLowerCase()}, applied to every organization. Any
			organization already held to a stricter figure keeps it.
		{/if}
	</p>
	<div class="reputation-controls__fields">
		<Input
			id="reputation-platform-warn"
			label="Warn at (%)"
			type="number"
			step="0.01"
			min="0"
			bind:value={warnRate}
		/>
		<Input
			id="reputation-platform-pause"
			label="Pause at (%)"
			type="number"
			step="0.01"
			min="0"
			bind:value={pauseRate}
		/>
		<Input
			id="reputation-platform-sample"
			label="Min sample (recipients)"
			type="number"
			step="1"
			min="0"
			bind:value={minSample}
		/>
		<Input
			id="reputation-platform-event"
			label="Early trigger (events)"
			type="number"
			step="1"
			min="1"
			bind:value={minEvent}
		/>
		<Input
			id="reputation-platform-window"
			label="Window (hours)"
			type="number"
			step="1"
			min="1"
			bind:value={windowHours}
		/>
	</div>
	<Checkbox
		id="reputation-platform-confirm"
		label="I understand this changes the ceiling for every organization"
		bind:checked={confirmed}
	/>
	<Textarea
		id="reputation-platform-reason"
		label="Reason (kept in the owner audit log)"
		bind:value={reason}
		rows={3}
		maxlength={500}
		required
	/>
</ConfirmDialog>

<style lang="scss">
	.reputation-controls {
		display: grid;
		gap: var(--space-large);
	}

	.reputation-controls :global(.reputation-controls__card) {
		display: grid;
		gap: var(--space-base);
	}

	.reputation-controls h2 {
		margin: 0;
		color: var(--color-heading);
		font-size: var(--typography--fontSize-largest);
		line-height: var(--typography--lineHeight-tightest);
	}

	.reputation-controls__head p {
		margin: var(--space-small) 0 0;
		max-width: 70ch;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		line-height: var(--typography--lineHeight-base);
	}

	.reputation-controls__table-wrap {
		overflow-x: auto;
	}

	.reputation-controls__table {
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
		}

		thead th {
			color: var(--color-text--secondary);
			font-weight: 700;
			white-space: nowrap;
		}

		tbody th {
			color: var(--color-heading);
			font-weight: 700;
		}

		tbody a {
			color: var(--color-interactive);
			text-decoration: none;

			&:hover {
				text-decoration: underline;
			}
		}

		tbody tr:last-child th,
		tbody tr:last-child td {
			border-bottom: 0;
		}
	}

	.reputation-controls__row-action {
		text-align: right;
		white-space: nowrap;
	}

	.reputation-controls__fields {
		display: grid;
		grid-template-columns: repeat(2, minmax(0, 1fr));
		gap: var(--space-base);
		margin-bottom: var(--space-base);
	}

	.reputation-controls__sr-only {
		position: absolute;
		width: 1px;
		height: 1px;
		padding: 0;
		margin: -1px;
		overflow: hidden;
		clip: rect(0, 0, 0, 0);
		white-space: nowrap;
		border: 0;
	}

	@media (max-width: 639px) {
		.reputation-controls__fields {
			grid-template-columns: 1fr;
		}
	}
</style>
