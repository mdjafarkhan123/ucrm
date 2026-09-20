<script lang="ts">
	import type { CalendarDate } from '@internationalized/date';
	import { createMutation, createQuery, useQueryClient } from '@tanstack/svelte-query';
	import Badge from '$lib/components/ui/Badge.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import CalendarPicker from '$lib/components/ui/CalendarPicker.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import { calendarDateFromString, calendarDateToString } from '$lib/components/ui/date-time';

	type LimitState = 'unlimited' | 'not_included' | 'numeric';
	type OverrideState = LimitState | 'inherit';
	type Allowance = {
		effective: { state: LimitState; value: number | null; source: 'package' | 'override' };
		override: {
			limit_state: LimitState;
			limit_value: number | null;
			starts_at: string;
			expires_at: string | null;
			reason: string | null;
			actor_owner_email: string | null;
		} | null;
	};
	type AllowanceResponse = { allowance?: Allowance; error?: string };
	type MutationResponse = { error?: string; field_errors?: Record<string, string> };

	let { organizationId }: { organizationId: string } = $props();

	const queryClient = useQueryClient();
	const allowanceKey = $derived(['jafar', 'organizations', organizationId, 'marketing-allowance']);
	const allowanceQuery = createQuery<AllowanceResponse>(() => ({
		queryKey: allowanceKey,
		queryFn: async () => {
			const response = await fetch(
				`/api/jafar/organizations/${organizationId}/communications/marketing-allowance`
			);
			const result = (await response.json()) as AllowanceResponse;
			if (!response.ok) throw new Error(result.error ?? 'Marketing allowance could not be loaded.');
			return result;
		},
		staleTime: 30_000
	}));

	const stateOptions = [
		{ value: 'inherit', label: 'Inherit from package' },
		{ value: 'numeric', label: 'Set a numeric limit' },
		{ value: 'not_included', label: 'Not included' },
		{ value: 'unlimited', label: 'Unlimited' }
	];

	let editing = $state(false);
	let overrideState = $state<OverrideState>('inherit');
	let overrideValue = $state('');
	let expiresAt = $state('');
	let reason = $state('');
	let feedbackMessage = $state('');
	let feedbackError = $state('');
	let fieldErrors = $state<Record<string, string>>({});

	function formatValue(state: LimitState, value: number | null) {
		if (state === 'unlimited') return 'Unlimited marketing emails per month';
		if (state === 'numeric') return `${value ?? 0} marketing emails per month`;
		return 'Not set, Marketing cannot send';
	}

	function formatTime(value: string | null) {
		return value
			? new Date(value).toLocaleString('en-US', { dateStyle: 'medium', timeStyle: 'short' })
			: 'Not set';
	}

	function startEditing(allowance: Allowance, clear: boolean) {
		feedbackMessage = '';
		feedbackError = '';
		fieldErrors = {};
		editing = true;
		overrideState = clear ? 'inherit' : (allowance.override?.limit_state ?? 'inherit');
		overrideValue = clear ? '' : (allowance.override?.limit_value?.toString() ?? '');
		expiresAt =
			clear || !allowance.override?.expires_at ? '' : allowance.override.expires_at.slice(0, 10);
		reason = '';
	}

	function handleExpiresAtChange(value: CalendarDate | undefined) {
		expiresAt = calendarDateToString(value);
	}

	const allowanceMutation = createMutation<
		MutationResponse,
		Error,
		{
			override_state: OverrideState;
			limit_value: number | null;
			starts_at: string;
			expires_at: string | null;
			reason: string;
			idempotency_key: string;
		}
	>(() => ({
		mutationFn: async (body) => {
			const response = await fetch(
				`/api/jafar/organizations/${organizationId}/limit-overrides/marketing_email_recipients`,
				{
					method: 'PUT',
					headers: { 'content-type': 'application/json' },
					body: JSON.stringify(body)
				}
			);
			const result = (await response.json()) as MutationResponse;
			if (!response.ok) {
				fieldErrors = result.field_errors ?? {};
				throw new Error(result.error ?? 'The Marketing allowance exception could not be changed.');
			}
			return result;
		},
		onMutate: () => {
			feedbackError = '';
			fieldErrors = {};
		},
		onError: (error) => (feedbackError = error.message),
		onSuccess: async () => {
			editing = false;
			feedbackMessage = 'Marketing allowance exception updated.';
			await queryClient.invalidateQueries({ queryKey: allowanceKey });
		}
	}));

	function submit(event: SubmitEvent) {
		event.preventDefault();
		if (!reason.trim()) return;
		allowanceMutation.mutate({
			override_state: overrideState,
			limit_value: overrideState === 'numeric' ? Number(overrideValue) : null,
			starts_at: new Date().toISOString(),
			expires_at: expiresAt ? new Date(expiresAt).toISOString() : null,
			reason: reason.trim(),
			idempotency_key: crypto.randomUUID()
		});
	}
</script>

<div class="marketing-allowance-actions">
	<div>
		<h3>Marketing email allowance</h3>
		<p class="marketing-allowance-actions__hint">
			Monthly marketing emails, kept apart from quote and invoice email. Until this is set,
			Marketing cannot send for this organization.
		</p>
	</div>

	{#if feedbackMessage}<p class="marketing-allowance-actions__success" role="status">
			{feedbackMessage}
		</p>{/if}
	{#if feedbackError}<p class="marketing-allowance-actions__error" role="alert">
			{feedbackError}
		</p>{/if}

	{#if allowanceQuery.isPending}
		<LoadingSkeleton variant="table" label="Loading Marketing allowance" />
	{:else if allowanceQuery.isError}
		<ErrorState
			title="Marketing allowance could not be loaded"
			description={allowanceQuery.error instanceof Error
				? allowanceQuery.error.message
				: 'Marketing allowance could not be loaded. Try again.'}
			retry={() => allowanceQuery.refetch()}
		/>
	{:else if allowanceQuery.data?.allowance}
		{@const allowance = allowanceQuery.data.allowance}
		<div class="marketing-allowance-actions__summary">
			<p>{formatValue(allowance.effective.state, allowance.effective.value)}</p>
			<Badge status={allowance.effective.source === 'override' ? 'informative' : 'inactive'}>
				{allowance.effective.source === 'override' ? 'Exception' : 'Package default'}
			</Badge>
		</div>
		{#if allowance.override}
			<dl class="marketing-allowance-actions__details">
				<div>
					<dt>Stored exception</dt>
					<dd>
						{formatValue(allowance.override.limit_state, allowance.override.limit_value)} from {formatTime(
							allowance.override.starts_at
						)}{allowance.override.expires_at
							? ` until ${formatTime(allowance.override.expires_at)}`
							: ''}
					</dd>
				</div>
				<div>
					<dt>Author and reason</dt>
					<dd>
						{allowance.override.actor_owner_email ?? 'Not recorded'} · {allowance.override.reason ??
							'Not recorded'}
					</dd>
				</div>
			</dl>
		{/if}
		{#if editing}
			<form class="marketing-allowance-actions__form" onsubmit={submit}>
				<Select
					id="marketing-allowance-state"
					ariaLabel="Marketing allowance exception state"
					options={stateOptions}
					bind:value={overrideState}
				/>
				{#if overrideState === 'numeric'}
					<Input
						id="marketing-allowance-value"
						label="Marketing emails per month"
						type="number"
						min="0"
						bind:value={overrideValue}
						invalid={Boolean(fieldErrors.limit_value)}
						errorMessage={fieldErrors.limit_value}
					/>
				{/if}
				<CalendarPicker
					id="marketing-allowance-expiry"
					label="Expires (leave blank for permanent)"
					value={calendarDateFromString(expiresAt)}
					onchange={handleExpiresAtChange}
				/>
				<Input
					id="marketing-allowance-reason"
					label="Private reason"
					bind:value={reason}
					required
					invalid={Boolean(fieldErrors.reason)}
					errorMessage={fieldErrors.reason}
				/>
				<div class="marketing-allowance-actions__actions">
					<Button
						type="submit"
						loading={allowanceMutation.isPending}
						disabled={!reason.trim() || (overrideState === 'numeric' && !overrideValue)}
						>Save exception</Button
					>
					<Button
						type="button"
						variant="secondary"
						variation="subtle"
						onclick={() => (editing = false)}>Cancel</Button
					>
				</div>
			</form>
		{:else}
			<div class="marketing-allowance-actions__actions">
				<Button
					size="small"
					variant="secondary"
					variation="subtle"
					onclick={() => startEditing(allowance, false)}>Change exception</Button
				>
				{#if allowance.override}<Button
						size="small"
						variant="secondary"
						variation="subtle"
						onclick={() => startEditing(allowance, true)}>Clear exception</Button
					>{/if}
			</div>
		{/if}
	{/if}
</div>

<style lang="scss">
	.marketing-allowance-actions,
	.marketing-allowance-actions__form {
		display: grid;
		gap: var(--space-base);
	}
	.marketing-allowance-actions h3 {
		color: var(--color-heading);
		font-size: var(--typography--fontSize-large);
	}
	.marketing-allowance-actions__hint {
		margin-top: var(--space-small);
		color: var(--color-text--secondary);
		line-height: var(--typography--lineHeight-base);
	}
	.marketing-allowance-actions__success {
		color: var(--color-success--onSurface);
	}
	.marketing-allowance-actions__error {
		color: var(--color-critical);
		font-size: var(--typography--fontSize-small);
	}
	.marketing-allowance-actions__summary {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: var(--space-small);
		color: var(--color-text);
	}
	.marketing-allowance-actions__details {
		display: grid;
		grid-template-columns: repeat(2, minmax(0, 1fr));
		gap: var(--space-base);
		margin: 0;
		div {
			display: grid;
			gap: var(--space-smallest);
		}
		dt {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}
		dd {
			margin: 0;
			color: var(--color-text);
			font-size: var(--typography--fontSize-small);
			overflow-wrap: anywhere;
		}
	}
	.marketing-allowance-actions__actions {
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-small);
	}
	@media (max-width: 639px) {
		.marketing-allowance-actions__details {
			grid-template-columns: 1fr;
		}
	}
</style>
