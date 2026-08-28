<script lang="ts">
	import { createMutation, createQuery, useQueryClient } from '@tanstack/svelte-query';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Card from '$lib/components/ui/Card.svelte';
	import Checkbox from '$lib/components/ui/Checkbox.svelte';
	import ConfirmDialog from '$lib/components/ui/ConfirmDialog.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import Textarea from '$lib/components/ui/Textarea.svelte';

	type StageKey = 'days_1_3' | 'days_4_7' | 'days_8_14';

	type WarmupStage = {
		id: string;
		stage_key: StageKey;
		daily_ceiling: number;
		reason: string;
		actor_owner_email: string;
		effective_from: string;
	};
	type ShortTermRate = {
		id: string;
		window_minutes: number;
		max_recipients: number;
		reason: string;
		actor_owner_email: string;
		effective_from: string;
	};
	type ProviderCapacity = {
		capacity: number | null;
		reserve_percent: number;
		reserve_recipients: number | null;
		reason: string;
		actor_owner_email: string;
		effective_from: string;
		period_start: string;
		period_end: string;
		period_accepted: number;
		period_reserved: number;
	};
	type Overview = {
		warmup_stages: WarmupStage[];
		short_term: ShortTermRate | null;
		provider_capacity: ProviderCapacity | null;
		domains_warming_up: number;
	};
	type OverviewResponse = { overview: Overview; error?: string };

	const queryClient = useQueryClient();
	const toast = getToastManager();
	const overviewKey = ['jafar', 'communications', 'email-sending-capacity'] as const;

	const overviewQuery = createQuery<OverviewResponse>(() => ({
		queryKey: overviewKey,
		queryFn: async () => {
			const response = await fetch('/api/jafar/communications/email-sending-capacity');
			const result = (await response.json()) as OverviewResponse;
			if (!response.ok)
				throw new Error(result.error ?? 'The email sending-capacity overview could not be loaded.');
			return result;
		},
		staleTime: 30_000
	}));

	const overview = $derived(overviewQuery.data?.overview ?? null);
	const warmupStages = $derived(overview?.warmup_stages ?? []);
	const shortTerm = $derived(overview?.short_term ?? null);
	const providerCapacity = $derived(overview?.provider_capacity ?? null);
	const periodUsed = $derived(
		(providerCapacity?.period_accepted ?? 0) + (providerCapacity?.period_reserved ?? 0)
	);
	const domainsWarmingUp = $derived(overview?.domains_warming_up ?? 0);

	const stageLabels: Record<StageKey, string> = {
		days_1_3: 'Days 1 to 3',
		days_4_7: 'Days 4 to 7',
		days_8_14: 'Days 8 to 14'
	};

	function formatCount(value: number) {
		return new Intl.NumberFormat().format(value);
	}

	// --- Changing a setting -------------------------------------------------------------------------

	type WarmupChange = { kind: 'warmup'; stage: WarmupStage };
	type ShortTermChange = { kind: 'short_term'; rate: ShortTermRate };
	type ProviderCapacityChange = { kind: 'provider_capacity'; current: ProviderCapacity };
	let changeTarget = $state<WarmupChange | ShortTermChange | ProviderCapacityChange | null>(null);

	let ceiling = $state('');
	let windowMinutes = $state('');
	let maxRecipients = $state('');
	let capacity = $state('');
	let reservePercent = $state('');
	let reason = $state('');
	let confirmed = $state(false);

	const reasonValid = $derived(reason.trim().length >= 3);

	function openWarmup(stage: WarmupStage) {
		changeTarget = { kind: 'warmup', stage };
		ceiling = String(stage.daily_ceiling);
		reason = '';
		confirmed = false;
	}
	function openShortTerm(rate: ShortTermRate) {
		changeTarget = { kind: 'short_term', rate };
		windowMinutes = String(rate.window_minutes);
		maxRecipients = String(rate.max_recipients);
		reason = '';
		confirmed = false;
	}
	function openProviderCapacity(current: ProviderCapacity) {
		changeTarget = { kind: 'provider_capacity', current };
		capacity = current.capacity === null ? '' : String(current.capacity);
		reservePercent = String(current.reserve_percent);
		reason = '';
		confirmed = false;
	}
	function closeChange() {
		changeTarget = null;
		reason = '';
		confirmed = false;
	}

	// `<Input type="number">` can hand back a string or a coerced number depending on the binding, so
	// normalise whatever comes in.
	function numberOrNull(value: string | number | null | undefined) {
		if (value === null || value === undefined) return null;
		const trimmed = String(value).trim();
		if (trimmed === '') return null;
		const next = Number(trimmed);
		return Number.isFinite(next) ? next : null;
	}

	const changeMutation = createMutation<OverviewResponse, Error, void>(() => ({
		mutationFn: async () => {
			const target = changeTarget;
			if (!target) throw new Error('Choose a setting to change.');
			let payload: Record<string, unknown>;
			if (target.kind === 'warmup') {
				payload = {
					kind: 'warmup',
					stage_key: target.stage.stage_key,
					daily_ceiling: numberOrNull(ceiling),
					reason: reason.trim(),
					confirm_platform_change: confirmed
				};
			} else if (target.kind === 'short_term') {
				payload = {
					kind: 'short_term',
					window_minutes: numberOrNull(windowMinutes),
					max_recipients: numberOrNull(maxRecipients),
					reason: reason.trim(),
					confirm_platform_change: confirmed
				};
			} else {
				payload = {
					kind: 'provider_capacity',
					capacity: numberOrNull(capacity),
					reserve_percent: numberOrNull(reservePercent),
					reason: reason.trim(),
					confirm_platform_change: confirmed
				};
			}
			const response = await fetch('/api/jafar/communications/email-sending-capacity', {
				method: 'POST',
				headers: { 'content-type': 'application/json' },
				body: JSON.stringify(payload)
			});
			const result = (await response.json()) as OverviewResponse;
			if (!response.ok)
				throw new Error(result.error ?? 'The sending-capacity setting could not be changed.');
			return result;
		},
		onSuccess: (data) => {
			closeChange();
			if (data.overview)
				queryClient.setQueryData<OverviewResponse>(overviewKey, { overview: data.overview });
			toast.success('The sending-capacity setting is saved.');
		},
		onError: (error) => toast.error(error.message)
	}));

	const reserveValid = $derived.by(() => {
		if (changeTarget?.kind !== 'provider_capacity') return true;
		const parsed = numberOrNull(reservePercent);
		return parsed !== null && Number.isInteger(parsed) && parsed >= 0 && parsed <= 100;
	});
	const canSubmit = $derived(reasonValid && reserveValid && confirmed && !changeMutation.isPending);
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<Card class="sending-capacity__card">
	<div class="sending-capacity__head">
		<h2>Sending capacity limits</h2>
		<p>
			A newly verified sending domain is held to a staged daily ceiling for its first two weeks, and
			every organization is held to a short-term recipient rate. Email over either limit waits and
			is retried &mdash; it is never dropped. These figures apply to every organization.
		</p>
	</div>

	{#if overviewQuery.isPending}
		<LoadingSkeleton variant="table" rows={4} label="Loading sending-capacity limits" />
	{:else if overviewQuery.isError}
		<ErrorState
			title="Sending-capacity limits could not be loaded"
			description={overviewQuery.error instanceof Error
				? overviewQuery.error.message
				: 'Try again.'}
			retry={() => overviewQuery.refetch()}
		/>
	{:else if overview}
		<div class="sending-capacity__section">
			<div class="sending-capacity__section-head">
				<h3>Domain warm-up</h3>
				<p>
					{domainsWarmingUp === 0
						? 'No sending domain is in warm-up right now.'
						: `${formatCount(domainsWarmingUp)} sending domain${
								domainsWarmingUp === 1 ? ' is' : 's are'
							} in warm-up right now.`}
				</p>
			</div>
			<div class="sending-capacity__table-wrap">
				<table class="sending-capacity__table">
					<thead>
						<tr>
							<th scope="col">Stage</th>
							<th scope="col">Accepted recipients per day</th>
							<th scope="col"><span class="sending-capacity__sr-only">Change ceiling</span></th>
						</tr>
					</thead>
					<tbody>
						{#each warmupStages as stage (stage.id)}
							<tr>
								<th scope="row">{stageLabels[stage.stage_key]}</th>
								<td>{formatCount(stage.daily_ceiling)}</td>
								<td class="sending-capacity__row-action">
									<Button
										size="small"
										variant="secondary"
										variation="subtle"
										onclick={() => openWarmup(stage)}
									>
										Change
									</Button>
								</td>
							</tr>
						{/each}
						<tr>
							<th scope="row">After day 14</th>
							<td>Organization limits</td>
							<td></td>
						</tr>
					</tbody>
				</table>
			</div>
		</div>

		{#if shortTerm}
			<div class="sending-capacity__section">
				<div class="sending-capacity__section-head">
					<h3>Short-term rate</h3>
					<p>The most recipients one organization can have accepted inside a rolling window.</p>
				</div>
				<div class="sending-capacity__table-wrap">
					<table class="sending-capacity__table">
						<thead>
							<tr>
								<th scope="col">Recipients</th>
								<th scope="col">Window</th>
								<th scope="col"><span class="sending-capacity__sr-only">Change rate</span></th>
							</tr>
						</thead>
						<tbody>
							<tr>
								<th scope="row">{formatCount(shortTerm.max_recipients)}</th>
								<td>{formatCount(shortTerm.window_minutes)} minutes</td>
								<td class="sending-capacity__row-action">
									<Button
										size="small"
										variant="secondary"
										variation="subtle"
										onclick={() => openShortTerm(shortTerm)}
									>
										Change
									</Button>
								</td>
							</tr>
						</tbody>
					</table>
				</div>
			</div>
		{/if}

		{#if providerCapacity}
			<div class="sending-capacity__section">
				<div class="sending-capacity__section-head">
					<h3>Provider period capacity</h3>
					<p>
						The most recipients the email provider will accept across every organization in a
						calendar month. A share is reserved so requested quotes, invoices, receipts and replies
						still send once ordinary email has filled the month. Email over the line waits &mdash;
						it is never dropped.
					</p>
				</div>
				<div class="sending-capacity__table-wrap">
					<table class="sending-capacity__table">
						<thead>
							<tr>
								<th scope="col">Setting</th>
								<th scope="col">Value</th>
								<th scope="col"><span class="sending-capacity__sr-only">Change capacity</span></th>
							</tr>
						</thead>
						<tbody>
							<tr>
								<th scope="row">Monthly capacity</th>
								<td>
									{providerCapacity.capacity === null
										? 'No limit set'
										: `${formatCount(providerCapacity.capacity)} recipients`}
								</td>
								<td class="sending-capacity__row-action" rowspan="3">
									<Button
										size="small"
										variant="secondary"
										variation="subtle"
										onclick={() => openProviderCapacity(providerCapacity)}
									>
										Change
									</Button>
								</td>
							</tr>
							<tr>
								<th scope="row">Reserved for essential email</th>
								<td>
									{providerCapacity.reserve_percent}%{providerCapacity.reserve_recipients === null
										? ''
										: ` (${formatCount(providerCapacity.reserve_recipients)} recipients)`}
								</td>
							</tr>
							<tr>
								<th scope="row">Used this month</th>
								<td>
									{formatCount(periodUsed)}{providerCapacity.capacity === null
										? ''
										: ` of ${formatCount(providerCapacity.capacity)}`}
								</td>
							</tr>
						</tbody>
					</table>
				</div>
			</div>
		{/if}
	{/if}
</Card>
<!-- eslint-enable svelte/no-at-html-tags -->

<ConfirmDialog
	open={changeTarget !== null}
	title={changeTarget?.kind === 'warmup'
		? 'Change a warm-up ceiling'
		: changeTarget?.kind === 'provider_capacity'
			? 'Change the provider period capacity'
			: 'Change the short-term rate'}
	tone="critical"
	confirmLabel="Save limit"
	loading={changeMutation.isPending}
	confirmDisabled={!canSubmit}
	onConfirm={() => {
		if (canSubmit) changeMutation.mutate();
	}}
	onClose={closeChange}
>
	{#if changeTarget?.kind === 'warmup'}
		<p>
			This is the daily ceiling for a sending domain that is
			<strong>{stageLabels[changeTarget.stage.stage_key].toLowerCase()}</strong> past verification, applied
			to every organization.
		</p>
		<div class="sending-capacity__fields">
			<Input
				id="warmup-ceiling"
				label="Accepted recipients per day"
				type="number"
				step="1"
				min="0"
				bind:value={ceiling}
			/>
		</div>
	{:else if changeTarget?.kind === 'short_term'}
		<p>
			This is the short-term sending rate applied to every organization. Email over it waits for the
			window to clear.
		</p>
		<div class="sending-capacity__fields">
			<Input
				id="short-term-recipients"
				label="Recipients"
				type="number"
				step="1"
				min="1"
				bind:value={maxRecipients}
			/>
			<Input
				id="short-term-window"
				label="Window (minutes)"
				type="number"
				step="1"
				min="1"
				bind:value={windowMinutes}
			/>
		</div>
	{:else if changeTarget?.kind === 'provider_capacity'}
		<p>
			This is the monthly recipient capacity for the whole platform, and the share of it held back
			for essential contractor and system email. Leave the capacity blank to turn the limit off.
		</p>
		<div class="sending-capacity__fields">
			<Input
				id="provider-capacity"
				label="Monthly capacity (recipients)"
				type="number"
				step="1"
				min="1"
				placeholder="No limit"
				bind:value={capacity}
			/>
			<Input
				id="provider-reserve"
				label="Reserved for essential (%)"
				type="number"
				step="1"
				min="0"
				max="100"
				bind:value={reservePercent}
			/>
		</div>
	{/if}
	<Checkbox
		id="sending-capacity-confirm"
		label="I understand this changes the limit for every organization"
		bind:checked={confirmed}
	/>
	<Textarea
		id="sending-capacity-reason"
		label="Reason (kept in the owner audit log)"
		bind:value={reason}
		rows={3}
		maxlength={500}
		required
	/>
</ConfirmDialog>

<style lang="scss">
	:global(.sending-capacity__card) {
		display: grid;
		gap: var(--space-large);
	}

	h2 {
		margin: 0;
		color: var(--color-heading);
		font-size: var(--typography--fontSize-largest);
		line-height: var(--typography--lineHeight-tightest);
	}

	h3 {
		margin: 0;
		color: var(--color-heading);
		font-size: var(--typography--fontSize-large);
		line-height: var(--typography--lineHeight-tightest);
	}

	.sending-capacity__head p,
	.sending-capacity__section-head p {
		margin: var(--space-small) 0 0;
		max-width: 70ch;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		line-height: var(--typography--lineHeight-base);
	}

	.sending-capacity__section {
		display: grid;
		gap: var(--space-base);
	}

	.sending-capacity__table-wrap {
		overflow-x: auto;
	}

	.sending-capacity__table {
		width: 100%;
		min-width: 480px;
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

		tbody tr:last-child th,
		tbody tr:last-child td {
			border-bottom: 0;
		}
	}

	.sending-capacity__row-action {
		text-align: right;
		white-space: nowrap;
	}

	.sending-capacity__fields {
		display: grid;
		grid-template-columns: repeat(2, minmax(0, 1fr));
		gap: var(--space-base);
		margin-bottom: var(--space-base);
	}

	.sending-capacity__sr-only {
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
		.sending-capacity__fields {
			grid-template-columns: 1fr;
		}
	}
</style>
