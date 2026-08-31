<script lang="ts">
	import type { CalendarDate } from '@internationalized/date';
	import { createMutation, createQuery, useQueryClient } from '@tanstack/svelte-query';
	import Badge from '$lib/components/ui/Badge.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import CalendarPicker from '$lib/components/ui/CalendarPicker.svelte';
	import ConfirmDialog from '$lib/components/ui/ConfirmDialog.svelte';
	import DateTimePicker from '$lib/components/ui/DateTimePicker.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import Textarea from '$lib/components/ui/Textarea.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import type { DateTimePickerValue } from '$lib/components/ui/date-time';
	import {
		calendarDateFromString,
		calendarDateToString,
		dateTimePickerValueFromDate,
		dateTimePickerValueFromLocalString,
		dateTimePickerValueToLocalString,
		localDateTimeToIso
	} from '$lib/components/ui/date-time';

	type LimitState = 'unlimited' | 'not_included' | 'numeric';
	type OverrideState = 'inherit' | LimitState;

	type AuthorityEvent = {
		id: string;
		axis: 'operational' | 'security';
		event_kind: string;
		reason: string;
		actor_owner_email: string;
		created_at: string;
	};
	type Authority = {
		operational_state: 'enabled' | 'disabled';
		security_state: 'active' | 'suspended';
		operational_reason: string | null;
		security_reason: string | null;
		operational_changed_at: string | null;
		security_changed_at: string | null;
		recent_events: AuthorityEvent[];
	};
	type LimitOverview = {
		limit_key: string;
		package_default: { state: LimitState; value: number | null };
		effective: {
			state: LimitState;
			value: number | null;
			is_unlimited: boolean;
			source: 'package' | 'override';
		};
		exception: null | {
			state: LimitState;
			value: number | null;
			is_unlimited: boolean;
			is_active: boolean;
			reason: string | null;
			actor_owner_email: string | null;
			starts_at: string;
			expires_at: string | null;
		};
	};
	type AuthorityResponse = { authority?: Authority; limits?: LimitOverview[]; error?: string };
	type MutationResponse = { error?: string };
	type PendingAction = {
		axis: 'operational' | 'security';
		engage: boolean;
	} | null;

	let { organizationId }: { organizationId: string } = $props();

	const queryClient = useQueryClient();
	const toast = getToastManager();
	const authorityKey = $derived(['jafar', 'organizations', organizationId, 'automation-authority']);
	const endpoint = $derived(
		`/api/jafar/organizations/${organizationId}/automation/automation-authority`
	);

	const LIMIT_LABELS: Record<string, string> = {
		automation_active_recipes: 'Active recipes',
		automation_max_conditions_per_recipe: 'Conditions per recipe',
		automation_max_steps_per_recipe: 'Steps per recipe',
		automation_max_customer_messages_per_enrollment: 'Customer messages per enrollment',
		automation_min_customer_message_spacing_minutes: 'Minimum message spacing (minutes)',
		automation_max_delay_days: 'Maximum delay (days)',
		automation_max_enrollment_duration_days: 'Maximum enrollment duration (days)'
	};
	const LIMIT_OVERRIDE_STATE_OPTIONS = [
		{ value: 'inherit', label: 'Inherit from package' },
		{ value: 'numeric', label: 'Set a numeric limit' },
		{ value: 'not_included', label: 'Not included' },
		{ value: 'unlimited', label: 'Unlimited' }
	];

	const authorityQuery = createQuery<AuthorityResponse>(() => ({
		queryKey: authorityKey,
		queryFn: async () => {
			const response = await fetch(endpoint);
			const result = (await response.json()) as AuthorityResponse;
			if (!response.ok)
				throw new Error(result.error ?? 'Automation authority could not be loaded.');
			return result;
		},
		staleTime: 15_000
	}));

	// Effective authority collapses two independent axes: a security suspension outranks an operational
	// disable, which outranks the healthy default.
	const effectiveState = $derived.by(() => {
		const authority = authorityQuery.data?.authority;
		if (!authority) return null;
		if (authority.security_state === 'suspended')
			return { label: 'Security suspended', tone: 'critical' as const };
		if (authority.operational_state === 'disabled')
			return { label: 'Operationally disabled', tone: 'warning' as const };
		return { label: 'Enabled', tone: 'success' as const };
	});

	function formatDateTime(value: string | null) {
		if (!value) return 'Not recorded';
		return new Intl.DateTimeFormat(undefined, { dateStyle: 'medium', timeStyle: 'short' }).format(
			new Date(value)
		);
	}
	function formatLimit(state: LimitState, value: number | null) {
		if (state === 'unlimited') return 'Unlimited';
		if (state === 'numeric') return value === null ? '—' : String(value);
		return 'Not included';
	}
	function localDateTimeValue(value: Date) {
		return dateTimePickerValueToLocalString(dateTimePickerValueFromDate(value));
	}

	// Authority change ------------------------------------------------------------------------------
	let pendingAction = $state<PendingAction>(null);
	let reason = $state('');
	const reasonValid = $derived(reason.trim().length >= 3);

	function openAction(action: Exclude<PendingAction, null>) {
		pendingAction = action;
		reason = '';
	}
	function closeAction() {
		if (authorityMutation.isPending) return;
		pendingAction = null;
		reason = '';
	}

	const authorityMutation = createMutation<AuthorityResponse, Error, Record<string, unknown>>(
		() => ({
			mutationFn: async (body) => {
				const response = await fetch(endpoint, {
					method: 'POST',
					headers: { 'content-type': 'application/json' },
					body: JSON.stringify(body)
				});
				const result = (await response.json()) as AuthorityResponse;
				if (!response.ok)
					throw new Error(result.error ?? 'Automation authority could not be changed.');
				return result;
			},
			onSuccess: async (_result, variables) => {
				pendingAction = null;
				reason = '';
				const axis = variables.axis;
				const engage = variables.engage;
				toast.success(
					axis === 'security'
						? engage
							? 'Automation is suspended for this organization.'
							: 'The Automation security suspension was lifted.'
						: engage
							? 'Automation is operationally disabled for this organization.'
							: 'Automation was operationally re-enabled.'
				);
				await queryClient.invalidateQueries({ queryKey: authorityKey });
			},
			onError: (error) => toast.error(error.message)
		})
	);

	function confirmAction() {
		if (!pendingAction || !reasonValid || authorityMutation.isPending) return;
		authorityMutation.mutate({
			axis: pendingAction.axis,
			engage: pendingAction.engage,
			reason: reason.trim(),
			idempotency_key: crypto.randomUUID()
		});
	}

	const dialogTitle = $derived(
		pendingAction === null
			? 'Automation authority'
			: pendingAction.axis === 'security'
				? pendingAction.engage
					? 'Suspend Automation'
					: 'Lift Automation suspension'
				: pendingAction.engage
					? 'Operationally disable Automation'
					: 'Re-enable Automation'
	);
	const dialogBody = $derived(
		pendingAction === null
			? ''
			: pendingAction.axis === 'security'
				? pendingAction.engage
					? 'Every authoring, activation, enrollment, and customer effect fails closed immediately. Definitions and history stay readable. Use this for a security or abuse investigation.'
					: 'Automation writes become available again for this organization, unless an operational disable is still in place.'
				: pendingAction.engage
					? 'New enrollment and customer effects stop immediately while definitions and history stay readable. Use this for a temporary operational hold.'
					: 'Automation writes become available again for this organization, unless a security suspension is still in place.'
	);

	// Limit exceptions ------------------------------------------------------------------------------
	let editingLimitKey = $state<string | null>(null);
	let overrideState = $state<OverrideState>('numeric');
	let overrideValue = $state('');
	let overrideStartsAt = $state('');
	let overrideExpiry = $state('');
	let overrideReason = $state('');

	function startEditingLimit(row: LimitOverview) {
		editingLimitKey = row.limit_key;
		overrideState = row.exception ? row.exception.state : 'numeric';
		overrideValue = row.exception?.value?.toString() ?? '';
		overrideStartsAt = localDateTimeValue(new Date());
		overrideExpiry = '';
		overrideReason = '';
	}
	function startClearingLimit(row: LimitOverview) {
		editingLimitKey = row.limit_key;
		overrideState = 'inherit';
		overrideValue = '';
		overrideStartsAt = localDateTimeValue(new Date());
		overrideExpiry = '';
		overrideReason = '';
	}
	function cancelEditingLimit() {
		if (limitMutation.isPending) return;
		editingLimitKey = null;
	}
	function handleStartsAtChange(value: DateTimePickerValue) {
		overrideStartsAt = dateTimePickerValueToLocalString(value);
	}
	function handleExpiryChange(value: CalendarDate | undefined) {
		overrideExpiry = calendarDateToString(value);
	}

	const limitMutation = createMutation<
		MutationResponse,
		Error,
		{
			limitKey: string;
			override_state: OverrideState;
			limit_value: number | null;
			starts_at: string;
			expires_at: string | null;
			reason: string;
			idempotency_key: string;
		}
	>(() => ({
		mutationFn: async (input) => {
			const response = await fetch(
				`/api/jafar/organizations/${organizationId}/limit-overrides/${input.limitKey}`,
				{
					method: 'PUT',
					headers: { 'content-type': 'application/json' },
					body: JSON.stringify({
						override_state: input.override_state,
						limit_value: input.limit_value,
						starts_at: input.starts_at,
						expires_at: input.expires_at,
						reason: input.reason,
						idempotency_key: input.idempotency_key
					})
				}
			);
			const result = (await response.json()) as MutationResponse;
			if (!response.ok)
				throw new Error(result.error ?? 'The limit exception could not be changed.');
			return result;
		},
		onSuccess: async () => {
			editingLimitKey = null;
			toast.success('Automation limit exception updated.');
			await queryClient.invalidateQueries({ queryKey: authorityKey });
			await queryClient.invalidateQueries({
				queryKey: ['jafar', 'organizations', organizationId]
			});
		},
		onError: (error) => toast.error(error.message)
	}));

	function submitLimitOverride(event: SubmitEvent) {
		event.preventDefault();
		if (!editingLimitKey || !overrideReason.trim() || !overrideStartsAt) return;
		limitMutation.mutate({
			limitKey: editingLimitKey,
			override_state: overrideState,
			limit_value: overrideState === 'numeric' ? Number(overrideValue) : null,
			starts_at: localDateTimeToIso(overrideStartsAt),
			expires_at: overrideExpiry ? new Date(overrideExpiry).toISOString() : null,
			reason: overrideReason.trim(),
			idempotency_key: crypto.randomUUID()
		});
	}
</script>

<div class="automation-authority">
	<div class="automation-authority__heading">
		<div>
			<h3>Automation authority and limits</h3>
			<p>
				Operational disable and security suspension are independent holds. Either one fails every
				authoring, activation, enrollment, and customer effect closed while definitions and history
				stay readable.
			</p>
		</div>
		{#if effectiveState}
			<Badge status={effectiveState.tone}>{effectiveState.label}</Badge>
		{/if}
	</div>

	{#if authorityQuery.isPending}
		<LoadingSkeleton variant="table" label="Loading Automation authority" />
	{:else if authorityQuery.isError}
		<ErrorState
			title="Automation authority could not be loaded"
			description={authorityQuery.error instanceof Error
				? authorityQuery.error.message
				: 'Try again.'}
			retry={() => authorityQuery.refetch()}
		/>
	{:else}
		{@const authority = authorityQuery.data?.authority}
		{@const limits = authorityQuery.data?.limits ?? []}
		<div class="automation-authority__axes">
			<div class="automation-authority__axis">
				<div class="automation-authority__axis-copy">
					<div>
						<strong>Operational state</strong>
						<Badge status={authority?.operational_state === 'disabled' ? 'warning' : 'success'}>
							{authority?.operational_state === 'disabled' ? 'Disabled' : 'Enabled'}
						</Badge>
					</div>
					{#if authority?.operational_state === 'disabled'}
						<small
							>{authority.operational_reason} · {formatDateTime(
								authority.operational_changed_at
							)}</small
						>
					{/if}
				</div>
				{#if authority?.operational_state === 'disabled'}
					<Button
						size="small"
						variant="secondary"
						variation="subtle"
						onclick={() => openAction({ axis: 'operational', engage: false })}
					>
						Re-enable
					</Button>
				{:else}
					<Button
						size="small"
						variant="secondary"
						variation="destructive"
						onclick={() => openAction({ axis: 'operational', engage: true })}
					>
						Operationally disable
					</Button>
				{/if}
			</div>

			<div class="automation-authority__axis">
				<div class="automation-authority__axis-copy">
					<div>
						<strong>Security state</strong>
						<Badge status={authority?.security_state === 'suspended' ? 'critical' : 'success'}>
							{authority?.security_state === 'suspended' ? 'Suspended' : 'Active'}
						</Badge>
					</div>
					{#if authority?.security_state === 'suspended'}
						<small
							>{authority.security_reason} · {formatDateTime(authority.security_changed_at)}</small
						>
					{/if}
				</div>
				{#if authority?.security_state === 'suspended'}
					<Button
						size="small"
						variant="secondary"
						variation="subtle"
						onclick={() => openAction({ axis: 'security', engage: false })}
					>
						Lift suspension
					</Button>
				{:else}
					<Button
						size="small"
						variant="secondary"
						variation="destructive"
						onclick={() => openAction({ axis: 'security', engage: true })}
					>
						Suspend Automation
					</Button>
				{/if}
			</div>
		</div>

		<div class="automation-authority__limits">
			<h4>Effective limits and exceptions</h4>
			<div class="automation-authority__table-wrap">
				<table>
					<thead>
						<tr>
							<th scope="col">Limit</th>
							<th scope="col">Package default</th>
							<th scope="col">Effective</th>
							<th scope="col">Exception</th>
							<th scope="col"></th>
						</tr>
					</thead>
					<tbody>
						{#each limits as row (row.limit_key)}
							<tr>
								<td>{LIMIT_LABELS[row.limit_key] ?? row.limit_key}</td>
								<td>{formatLimit(row.package_default.state, row.package_default.value)}</td>
								<td>
									{formatLimit(row.effective.state, row.effective.value)}
									<Badge status={row.effective.source === 'override' ? 'informative' : 'inactive'}>
										{row.effective.source === 'override' ? 'Exception' : 'Package default'}
									</Badge>
								</td>
								<td>
									{#if row.exception}
										<span class="automation-authority__exception">
											{formatLimit(row.exception.state, row.exception.value)}
											{#if !row.exception.is_active}<Badge status="inactive"
													>Scheduled/expired</Badge
												>{/if}
											<small
												>{row.exception.reason ?? '—'} · {row.exception.actor_owner_email ??
													'Unknown'} ·
												{formatDateTime(row.exception.starts_at)}{row.exception.expires_at
													? ` → ${formatDateTime(row.exception.expires_at)}`
													: ''}</small
											>
										</span>
									{:else}
										None
									{/if}
								</td>
								<td>
									<div class="automation-authority__row-actions">
										<Button
											size="small"
											variant="secondary"
											variation="subtle"
											onclick={() => startEditingLimit(row)}>Change</Button
										>
										{#if row.exception}
											<Button
												size="small"
												variant="secondary"
												variation="subtle"
												onclick={() => startClearingLimit(row)}>Clear</Button
											>
										{/if}
									</div>
								</td>
							</tr>
						{/each}
					</tbody>
				</table>
			</div>

			{#if editingLimitKey}
				<form onsubmit={submitLimitOverride} class="automation-authority__form">
					<p><strong>{LIMIT_LABELS[editingLimitKey] ?? editingLimitKey}</strong></p>
					<Select
						id="automation-limit-override-state"
						ariaLabel="Automation limit exception state"
						options={LIMIT_OVERRIDE_STATE_OPTIONS}
						bind:value={overrideState}
					/>
					{#if overrideState === 'numeric'}
						<Input
							id="automation-limit-override-value"
							label="Limit value"
							type="number"
							min="0"
							bind:value={overrideValue}
						/>
					{/if}
					<CalendarPicker
						id="automation-limit-override-expiry"
						label="Expires (leave blank for permanent)"
						value={calendarDateFromString(overrideExpiry)}
						onchange={handleExpiryChange}
					/>
					<DateTimePicker
						id="automation-limit-override-starts-at"
						dateLabel="Starts at date"
						timeLabel="Starts at time"
						value={dateTimePickerValueFromLocalString(overrideStartsAt)}
						required
						onchange={handleStartsAtChange}
					/>
					<Input
						id="automation-limit-override-reason"
						label="Private reason"
						bind:value={overrideReason}
					/>
					<div class="automation-authority__form-actions">
						<Button type="submit" loading={limitMutation.isPending}>Save exception</Button>
						<Button
							type="button"
							variant="secondary"
							variation="subtle"
							onclick={cancelEditingLimit}>Cancel</Button
						>
					</div>
				</form>
			{/if}
		</div>

		{#if (authority?.recent_events.length ?? 0) > 0}
			<div class="automation-authority__history">
				<h4>Recent authority changes</h4>
				<ul>
					{#each authority?.recent_events ?? [] as historyEvent (historyEvent.id)}
						<li>
							<div>
								<strong>{historyEvent.axis === 'security' ? 'Security' : 'Operational'}</strong>
								<span>{historyEvent.reason}</span>
							</div>
							<small
								>{historyEvent.actor_owner_email} · {formatDateTime(historyEvent.created_at)}</small
							>
						</li>
					{/each}
				</ul>
			</div>
		{/if}
	{/if}
</div>

<ConfirmDialog
	open={Boolean(pendingAction)}
	title={dialogTitle}
	tone={pendingAction?.engage ? 'critical' : 'success'}
	confirmLabel={dialogTitle}
	destructive={pendingAction?.engage ?? false}
	loading={authorityMutation.isPending}
	confirmDisabled={!reasonValid || authorityMutation.isPending}
	onConfirm={confirmAction}
	onClose={closeAction}
>
	<p>{dialogBody}</p>
	<Textarea
		id="automation-authority-reason"
		label="Reason (kept in the owner audit log)"
		bind:value={reason}
		rows={3}
		maxlength={500}
		required
	/>
</ConfirmDialog>

<style lang="scss">
	.automation-authority {
		display: grid;
		gap: var(--space-base);
	}
	.automation-authority__heading {
		display: flex;
		align-items: flex-start;
		justify-content: space-between;
		gap: var(--space-base);
	}
	.automation-authority__heading h3,
	.automation-authority__limits h4,
	.automation-authority__history h4 {
		color: var(--color-heading);
		font-size: var(--typography--fontSize-large);
	}
	.automation-authority__heading p {
		margin-top: var(--space-small);
		color: var(--color-text--secondary);
		line-height: var(--typography--lineHeight-base);
	}
	.automation-authority__axes {
		display: grid;
		grid-template-columns: 1fr 1fr;
		gap: var(--space-base);
	}
	.automation-authority__axis {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-base);
		padding: var(--space-base);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
	}
	.automation-authority__axis-copy {
		display: grid;
		gap: var(--space-smallest);
		min-width: 0;
	}
	.automation-authority__axis-copy > div {
		display: flex;
		align-items: center;
		flex-wrap: wrap;
		gap: var(--space-small);
	}
	.automation-authority__limits {
		display: grid;
		gap: var(--space-small);
		padding-top: var(--space-small);
		border-top: var(--border-base) solid var(--color-border);
	}
	.automation-authority__table-wrap {
		overflow-x: auto;
	}
	.automation-authority__limits table {
		width: 100%;
		border-collapse: collapse;
	}
	.automation-authority__limits th,
	.automation-authority__limits td {
		padding: var(--space-small);
		text-align: left;
		vertical-align: top;
		border-bottom: var(--border-base) solid var(--color-border);
	}
	.automation-authority__limits th {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}
	.automation-authority__exception {
		display: grid;
		gap: var(--space-smallest);
	}
	.automation-authority__row-actions {
		display: flex;
		gap: var(--space-small);
	}
	.automation-authority__form {
		display: grid;
		gap: var(--space-small);
		padding: var(--space-base);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface--background--subtle);
	}
	.automation-authority__form-actions {
		display: flex;
		gap: var(--space-small);
	}
	.automation-authority small {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}
	.automation-authority__history ul {
		display: grid;
		gap: var(--space-small);
		margin: 0;
		padding: 0;
		list-style: none;
	}
	.automation-authority__history li {
		display: flex;
		align-items: baseline;
		justify-content: space-between;
		gap: var(--space-base);
		padding: var(--space-small) 0;
		border-bottom: var(--border-base) solid var(--color-border);
	}
	.automation-authority__history li div {
		display: grid;
		gap: var(--space-smallest);
		min-width: 0;
	}
	@media (max-width: 639px) {
		.automation-authority__heading,
		.automation-authority__axis,
		.automation-authority__history li {
			align-items: stretch;
			flex-direction: column;
		}
		.automation-authority__axes {
			grid-template-columns: 1fr;
		}
	}
</style>
