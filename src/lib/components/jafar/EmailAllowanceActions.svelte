<script lang="ts">
	import type { CalendarDate } from '@internationalized/date';
	import { createMutation, createQuery, useQueryClient } from '@tanstack/svelte-query';
	import Badge from '$lib/components/ui/Badge.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import CalendarPicker from '$lib/components/ui/CalendarPicker.svelte';
	import DateTimePicker from '$lib/components/ui/DateTimePicker.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import type { DateTimePickerValue } from '$lib/components/ui/date-time';
	import {
		calendarDateFromString,
		calendarDateToString,
		dateTimePickerValueFromDate,
		dateTimePickerValueFromLocalString,
		dateTimePickerValueToLocalString,
		localDateTimeToIso
	} from '$lib/components/ui/date-time';

	type AllowanceKey = 'operational_email_recipients' | 'essential_email_recipients';
	type Allowance = {
		limit_key: AllowanceKey;
		period_id: string | null;
		period_starts_at: string | null;
		period_ends_at: string | null;
		effective_state: 'unlimited' | 'not_included' | 'numeric' | null;
		effective_value: number | null;
		effective_source: 'package' | 'override';
		fallback_state: 'unlimited' | 'not_included' | 'numeric' | null;
		fallback_value: number | null;
		override_state: 'unlimited' | 'not_included' | 'numeric' | null;
		override_value: number | null;
		override_starts_at: string | null;
		override_expires_at: string | null;
		override_reason: string | null;
		override_author_email: string | null;
	};
	type AllowanceResponse = { allowances?: Allowance[]; error?: string };
	type MutationResponse = { error?: string; field_errors?: Record<string, string> };

	let { organizationId }: { organizationId: string } = $props();

	const queryClient = useQueryClient();
	const allowanceKey = $derived(['jafar', 'organizations', organizationId, 'email-allowances']);
	const allowancesQuery = createQuery<AllowanceResponse>(() => ({
		queryKey: allowanceKey,
		queryFn: async () => {
			const response = await fetch(
				`/api/jafar/organizations/${organizationId}/communications/email-allowances`
			);
			const result = (await response.json()) as AllowanceResponse;
			if (!response.ok) throw new Error(result.error ?? 'Email allowances could not be loaded.');
			return result;
		},
		staleTime: 30_000
	}));

	const labels: Record<AllowanceKey, { title: string; description: string; unit: string }> = {
		operational_email_recipients: {
			title: 'Operational email allowance',
			description: 'Optional operational email can use this package capacity.',
			unit: 'recipients'
		},
		essential_email_recipients: {
			title: 'Protected essential reserve',
			description:
				'Requested quotes, invoices, receipts, security notices, and direct replies use this reserve.',
			unit: 'recipients'
		}
	};
	const stateOptions = [
		{ value: 'inherit', label: 'Inherit from package' },
		{ value: 'numeric', label: 'Set a numeric limit' },
		{ value: 'not_included', label: 'Not included' },
		{ value: 'unlimited', label: 'Unlimited' }
	];

	let editingKey = $state<AllowanceKey | null>(null);
	let overrideState = $state<'inherit' | 'unlimited' | 'not_included' | 'numeric'>('inherit');
	let overrideValue = $state('');
	let startsAt = $state('');
	let expiresAt = $state('');
	let reason = $state('');
	let feedbackMessage = $state('');
	let feedbackError = $state('');
	let fieldErrors = $state<Record<string, string>>({});

	function formatValue(state: Allowance['effective_state'], value: number | null) {
		if (state === 'unlimited') return 'Unlimited recipients';
		if (state === 'numeric') return `${value ?? 0} recipients`;
		if (state === 'not_included') return 'Not included';
		return 'Not configured';
	}

	function formatTime(value: string | null) {
		return value
			? new Date(value).toLocaleString('en-US', { dateStyle: 'medium', timeStyle: 'short' })
			: 'Not set';
	}

	function localDateTimeValue(value: Date) {
		return dateTimePickerValueToLocalString(dateTimePickerValueFromDate(value));
	}

	function startEditing(allowance: Allowance) {
		feedbackMessage = '';
		feedbackError = '';
		fieldErrors = {};
		editingKey = allowance.limit_key;
		overrideState = allowance.override_state ?? 'inherit';
		overrideValue = allowance.override_value?.toString() ?? '';
		startsAt = allowance.override_starts_at
			? allowance.override_starts_at.slice(0, 16)
			: localDateTimeValue(new Date());
		expiresAt = allowance.override_expires_at ? allowance.override_expires_at.slice(0, 10) : '';
		reason = '';
	}

	function handleStartsAtChange(value: DateTimePickerValue) {
		startsAt = dateTimePickerValueToLocalString(value);
	}

	function handleExpiresAtChange(value: CalendarDate | undefined) {
		expiresAt = calendarDateToString(value);
	}

	const allowanceMutation = createMutation<
		MutationResponse,
		Error,
		{
			limitKey: AllowanceKey;
			override_state: 'inherit' | 'unlimited' | 'not_included' | 'numeric';
			limit_value: number | null;
			starts_at: string;
			expires_at: string | null;
			reason: string;
			idempotency_key: string;
		}
	>(() => ({
		mutationFn: async ({ limitKey, ...body }) => {
			const response = await fetch(
				`/api/jafar/organizations/${organizationId}/limit-overrides/${limitKey}`,
				{
					method: 'PUT',
					headers: { 'content-type': 'application/json' },
					body: JSON.stringify(body)
				}
			);
			const result = (await response.json()) as MutationResponse;
			if (!response.ok) {
				fieldErrors = result.field_errors ?? {};
				throw new Error(result.error ?? 'The email allowance exception could not be changed.');
			}
			return result;
		},
		onMutate: () => {
			feedbackError = '';
			fieldErrors = {};
		},
		onError: (error) => (feedbackError = error.message),
		onSuccess: async () => {
			editingKey = null;
			feedbackMessage = 'Email allowance exception updated.';
			await queryClient.invalidateQueries({ queryKey: allowanceKey });
		}
	}));

	function submit(event: SubmitEvent) {
		event.preventDefault();
		if (!editingKey || !startsAt || !reason.trim()) return;
		allowanceMutation.mutate({
			limitKey: editingKey,
			override_state: overrideState,
			limit_value: overrideState === 'numeric' ? Number(overrideValue) : null,
			starts_at: localDateTimeToIso(startsAt),
			expires_at: expiresAt ? new Date(expiresAt).toISOString() : null,
			reason: reason.trim(),
			idempotency_key: crypto.randomUUID()
		});
	}
</script>

<div class="email-allowance-actions">
	<div class="email-allowance-actions__heading">
		<div>
			<h3>Email allowance authority</h3>
			<p>These values control package capacity only. The email delivery worker remains disabled.</p>
		</div>
	</div>

	{#if feedbackMessage}<p class="email-allowance-actions__success" role="status">
			{feedbackMessage}
		</p>{/if}
	{#if feedbackError}<p class="email-allowance-actions__error" role="alert">{feedbackError}</p>{/if}

	{#if allowancesQuery.isPending}
		<LoadingSkeleton variant="table" label="Loading email allowance authority" />
	{:else if allowancesQuery.isError}
		<ErrorState
			title="Email allowances could not be loaded"
			description={allowancesQuery.error instanceof Error
				? allowancesQuery.error.message
				: 'Email allowances could not be loaded. Try again.'}
			retry={() => allowancesQuery.refetch()}
		/>
	{:else}
		{#each allowancesQuery.data?.allowances ?? [] as allowance (allowance.limit_key)}
			<section
				class="email-allowance-actions__allowance"
				aria-labelledby={`allowance-${allowance.limit_key}`}
			>
				<div class="email-allowance-actions__allowance-heading">
					<div>
						<h4 id={`allowance-${allowance.limit_key}`}>{labels[allowance.limit_key].title}</h4>
						<p>{labels[allowance.limit_key].description}</p>
					</div>
					<Badge status={allowance.effective_source === 'override' ? 'informative' : 'inactive'}>
						{allowance.effective_source === 'override' ? 'Exception' : 'Package default'}
					</Badge>
				</div>
				<dl>
					<div>
						<dt>Effective value</dt>
						<dd>{formatValue(allowance.effective_state, allowance.effective_value)}</dd>
					</div>
					<div>
						<dt>Package fallback</dt>
						<dd>{formatValue(allowance.fallback_state, allowance.fallback_value)}</dd>
					</div>
					<div>
						<dt>Current period</dt>
						<dd>
							{allowance.period_id
								? `${formatTime(allowance.period_starts_at)} to ${formatTime(allowance.period_ends_at)}`
								: 'Not opened — sending stays fail-closed'}
						</dd>
					</div>
					{#if allowance.override_state}
						<div>
							<dt>Stored exception</dt>
							<dd>
								{formatValue(allowance.override_state, allowance.override_value)} from {formatTime(
									allowance.override_starts_at
								)}{allowance.override_expires_at
									? ` until ${formatTime(allowance.override_expires_at)}`
									: ''}
							</dd>
						</div>
						<div>
							<dt>Author and reason</dt>
							<dd>
								{allowance.override_author_email ?? 'Not recorded'} · {allowance.override_reason ??
									'Not recorded'}
							</dd>
						</div>
					{/if}
				</dl>
				{#if editingKey === allowance.limit_key}
					<form class="email-allowance-actions__form" onsubmit={submit}>
						<Select
							id={`allowance-state-${allowance.limit_key}`}
							ariaLabel="Allowance exception state"
							options={stateOptions}
							bind:value={overrideState}
						/>
						{#if overrideState === 'numeric'}
							<Input
								id={`allowance-value-${allowance.limit_key}`}
								label="Recipient allowance"
								type="number"
								min="0"
								bind:value={overrideValue}
								invalid={Boolean(fieldErrors.limit_value)}
								errorMessage={fieldErrors.limit_value}
							/>
						{/if}
						<DateTimePicker
							id={`allowance-start-${allowance.limit_key}`}
							dateLabel="Starts at date"
							timeLabel="Starts at time"
							value={dateTimePickerValueFromLocalString(startsAt)}
							required
							onchange={handleStartsAtChange}
						/>
						<CalendarPicker
							id={`allowance-expiry-${allowance.limit_key}`}
							label="Expires (leave blank for permanent)"
							value={calendarDateFromString(expiresAt)}
							onchange={handleExpiresAtChange}
						/>
						<Input
							id={`allowance-reason-${allowance.limit_key}`}
							label="Private reason"
							bind:value={reason}
							required
							invalid={Boolean(fieldErrors.reason)}
							errorMessage={fieldErrors.reason}
						/>
						<div class="email-allowance-actions__actions">
							<Button
								type="submit"
								loading={allowanceMutation.isPending}
								disabled={!reason.trim() ||
									!startsAt ||
									(overrideState === 'numeric' && !overrideValue)}>Save exception</Button
							>
							<Button
								type="button"
								variant="secondary"
								variation="subtle"
								onclick={() => (editingKey = null)}>Cancel</Button
							>
						</div>
					</form>
				{:else}
					<div class="email-allowance-actions__actions">
						<Button
							size="small"
							variant="secondary"
							variation="subtle"
							onclick={() => startEditing(allowance)}>Change exception</Button
						>
						{#if allowance.override_state}<Button
								size="small"
								variant="secondary"
								variation="subtle"
								onclick={() =>
									startEditing({
										...allowance,
										override_state: null,
										override_value: null,
										override_starts_at: null,
										override_expires_at: null
									})}>Clear exception</Button
							>{/if}
					</div>
				{/if}
			</section>
		{/each}
	{/if}
</div>

<style lang="scss">
	.email-allowance-actions,
	.email-allowance-actions__form {
		display: grid;
		gap: var(--space-base);
	}
	.email-allowance-actions__heading h3,
	.email-allowance-actions__allowance h4 {
		color: var(--color-heading);
		font-size: var(--typography--fontSize-large);
	}
	.email-allowance-actions__heading p,
	.email-allowance-actions__allowance-heading p {
		margin-top: var(--space-small);
		color: var(--color-text--secondary);
		line-height: var(--typography--lineHeight-base);
	}
	.email-allowance-actions__success {
		color: var(--color-success--onSurface);
	}
	.email-allowance-actions__error {
		color: var(--color-critical);
		font-size: var(--typography--fontSize-small);
	}
	.email-allowance-actions__allowance {
		display: grid;
		gap: var(--space-base);
		padding: var(--space-base);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface--background);
	}
	.email-allowance-actions__allowance-heading {
		display: flex;
		align-items: flex-start;
		justify-content: space-between;
		gap: var(--space-base);
	}
	.email-allowance-actions__allowance dl {
		display: grid;
		grid-template-columns: repeat(2, minmax(0, 1fr));
		gap: var(--space-base);
		margin: 0;
	}
	.email-allowance-actions__allowance dl > div {
		display: grid;
		gap: var(--space-smallest);
	}
	.email-allowance-actions__allowance dt {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}
	.email-allowance-actions__allowance dd {
		margin: 0;
		color: var(--color-text);
		font-size: var(--typography--fontSize-small);
		overflow-wrap: anywhere;
	}
	.email-allowance-actions__actions {
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-small);
	}
	@media (max-width: 639px) {
		.email-allowance-actions__allowance-heading {
			flex-direction: column;
		}
		.email-allowance-actions__allowance dl {
			grid-template-columns: 1fr;
		}
	}
</style>
