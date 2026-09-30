<script lang="ts">
	import type {
		AccessExceptionsResponse,
		EntitlementAllowance,
		EntitlementCapability,
		PackageAllowanceSide,
		PackageException,
		PackageExceptionCommandInput
	} from '$lib/components/jafar/organization/types';
	import type { DateTimePickerValue } from '$lib/components/ui/date-time';
	import { createMutation, createQuery, useQueryClient } from '@tanstack/svelte-query';
	import adjustmentsIcon from '@tabler/icons/outline/adjustments-horizontal.svg?raw';
	import gaugeIcon from '@tabler/icons/outline/gauge.svg?raw';
	import toggleIcon from '@tabler/icons/outline/toggle-right.svg?raw';
	import Badge from '$lib/components/ui/Badge.svelte';
	import Banner from '$lib/components/ui/Banner.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import DateTimePicker from '$lib/components/ui/DateTimePicker.svelte';
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import SegmentedControl from '$lib/components/ui/SegmentedControl.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import Textarea from '$lib/components/ui/Textarea.svelte';
	import SectionBlock from '$lib/components/layout/SectionBlock.svelte';
	import DataTable, { type DataTableColumn } from '$lib/components/data-display/DataTable.svelte';
	import EmptyState from '$lib/components/data-display/EmptyState.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import {
		dateTimePickerValueFromDate,
		dateTimePickerValueFromLocalString,
		dateTimePickerValueToLocalString,
		localDateTimeToIso
	} from '$lib/components/ui/date-time';
	import { organizationExceptionsQuery } from '$lib/jafar/organization-exceptions-queries';
	import { jafarOrganizationExceptionsKey, jafarOrganizationsKey } from '$lib/jafar/query-keys';
	import { formatDateTime } from './format';

	// Package builder P8b: the Access tab's features and limits as they stand, and the temporary exceptions
	// that change them (plan § Assignment and changes). Every exception has a reason, a start, and an end;
	// ending one early keeps its record. The database refuses what cannot be excepted and says why.
	let { organizationId }: { organizationId: string } = $props();

	const queryClient = useQueryClient();
	const accessQuery = createQuery(() => organizationExceptionsQuery(organizationId));
	const capabilities = $derived(accessQuery.data?.entitlements.capabilities ?? []);
	const allowances = $derived(accessQuery.data?.entitlements.allowances ?? []);
	const exceptions = $derived(accessQuery.data?.exceptions ?? []);

	// Core features come with every package and planned ones are not built, so only extras take exceptions.
	const exceptable = $derived(capabilities.filter((row) => row.kind === 'extra'));

	function allowanceText(side: PackageAllowanceSide, unit: string, monthly: boolean) {
		if (side.state === 'unlimited') return 'Unlimited';
		if (side.state === 'not_included') return 'Not included';
		return `${(side.value ?? 0).toLocaleString('en-US')} ${unit}${monthly ? ' a month' : ''}`;
	}
	function exceptionChange(row: PackageException) {
		if (row.capability_key) return row.capability_state === 'on' ? 'Switched on' : 'Switched off';
		return allowanceText(
			{ state: row.allowance_state ?? 'not_included', value: row.allowance_value },
			row.unit ?? '',
			false
		);
	}
	const statusBadges = {
		active: { label: 'Running', tone: 'success' },
		scheduled: { label: 'Starts later', tone: 'informative' },
		ended: { label: 'Ended', tone: 'inactive' },
		cancelled: { label: 'Cancelled', tone: 'inactive' }
	} as const;

	const featureColumns: DataTableColumn[] = [
		{ key: 'feature', label: 'Feature' },
		{ key: 'package', label: 'In the package' },
		{ key: 'now', label: 'Now' },
		{ key: 'actions', label: '', align: 'end' }
	];
	const limitColumns: DataTableColumn[] = [
		{ key: 'limit', label: 'Limit' },
		{ key: 'package', label: 'Package' },
		{ key: 'now', label: 'Now' },
		{ key: 'in_use', label: 'In use', align: 'end' },
		{ key: 'actions', label: '', align: 'end' }
	];
	const exceptionColumns: DataTableColumn[] = [
		{ key: 'what', label: 'Feature or limit' },
		{ key: 'change', label: 'Change' },
		{ key: 'when', label: 'When' },
		{ key: 'status', label: 'Status' },
		{ key: 'actions', label: '', align: 'end' }
	];

	// Dialogs -------------------------------------------------------------------------------------------------
	type Target = `capability:${string}` | `allowance:${string}`;
	let dialog = $state<'add' | 'end' | null>(null);
	// One idempotency key per opening, so a retry after a dropped connection cannot record twice.
	let dialogKey = $state('');
	let dialogError = $state('');
	let fieldErrors = $state<Record<string, string>>({});
	let feedback = $state('');

	let target = $state<Target | ''>('');
	let capabilityState = $state<'on' | 'off'>('on');
	let allowanceState = $state<PackageAllowanceSide['state']>('numeric');
	// A number input binds a number once typed into, and text before that.
	let allowanceValue = $state<string | number | null>('');
	let startsAt = $state('');
	let endsAt = $state('');
	let reason = $state('');
	let ending = $state<PackageException | null>(null);

	const targetOptions = $derived([
		...exceptable.map((row) => ({
			value: `capability:${row.key}`,
			label: `Feature · ${row.label}`
		})),
		...allowances.map((row) => ({ value: `allowance:${row.key}`, label: `Limit · ${row.label}` }))
	]);
	const chosenCapability = $derived(
		target.startsWith('capability:')
			? (capabilities.find((row) => `capability:${row.key}` === target) ?? null)
			: null
	);
	const chosenAllowance = $derived(
		target.startsWith('allowance:')
			? (allowances.find((row) => `allowance:${row.key}` === target) ?? null)
			: null
	);

	function localValue(date: Date) {
		return dateTimePickerValueToLocalString(dateTimePickerValueFromDate(date));
	}
	function resetFeedback() {
		dialogKey = crypto.randomUUID();
		dialogError = '';
		fieldErrors = {};
		feedback = '';
	}
	function chooseTarget(value: string) {
		target = value as Target;
		const capability = capabilities.find((row) => `capability:${row.key}` === value);
		const allowance = allowances.find((row) => `allowance:${row.key}` === value);
		// Start from the opposite of what the customer has now; for a limit, from the package's own value.
		if (capability) capabilityState = capability.effective ? 'off' : 'on';
		if (allowance) {
			allowanceState = allowance.package.state === 'numeric' ? 'numeric' : allowance.package.state;
			allowanceValue = allowance.package.value?.toString() ?? '';
		}
	}
	function openAdd(preset?: Target) {
		resetFeedback();
		const now = new Date();
		startsAt = localValue(now);
		endsAt = localValue(new Date(now.getTime() + 30 * 24 * 60 * 60 * 1000));
		reason = '';
		target = '';
		if (preset) chooseTarget(preset);
		dialog = 'add';
	}
	function openEnd(row: PackageException) {
		resetFeedback();
		ending = row;
		reason = '';
		dialog = 'end';
	}
	function closeDialog() {
		dialog = null;
		ending = null;
	}

	class ExceptionError extends Error {
		fieldErrors: Record<string, string>;
		constructor(result: AccessExceptionsResponse) {
			super(result.error ?? 'The exception could not be recorded.');
			this.fieldErrors = result.field_errors ?? {};
		}
	}

	const exceptionMutation = createMutation<
		AccessExceptionsResponse,
		ExceptionError,
		PackageExceptionCommandInput & { idempotency_key: string }
	>(() => ({
		mutationFn: async (command) => {
			const response = await fetch(`/api/jafar/organizations/${organizationId}/exceptions`, {
				method: 'POST',
				headers: { 'content-type': 'application/json' },
				body: JSON.stringify(command)
			});
			const result = (await response.json()) as AccessExceptionsResponse;
			if (!response.ok) throw new ExceptionError(result);
			return result;
		},
		onMutate: () => {
			dialogError = '';
			fieldErrors = {};
		},
		onError: (error) => {
			dialogError = error.message;
			fieldErrors = error.fieldErrors;
		},
		onSuccess: (result, command) => {
			queryClient.setQueryData<AccessExceptionsResponse>(
				jafarOrganizationExceptionsKey(organizationId),
				{ exceptions: result.exceptions, entitlements: result.entitlements }
			);
			feedback =
				command.action === 'end'
					? 'Exception ended. It stays in the list.'
					: 'Exception added. The customer sees the change once it starts.';
			closeDialog();
			// Features and limits feed the page's access read, the other tabs, and the directory; this tab's
			// own answer came back with the command.
			void queryClient.invalidateQueries({
				queryKey: jafarOrganizationsKey,
				predicate: (query) =>
					!(query.queryKey[2] === organizationId && query.queryKey[3] === 'exceptions')
			});
		}
	}));

	function submitAdd(event: SubmitEvent) {
		event.preventDefault();
		const nextErrors: Record<string, string> = {};
		if (!target) nextErrors.key = 'Choose a feature or limit.';
		if (reason.trim().length < 3) nextErrors.reason = 'Enter a reason of at least 3 characters.';
		if (
			chosenAllowance &&
			allowanceState === 'numeric' &&
			String(allowanceValue ?? '').trim() === ''
		)
			nextErrors.allowance_value = 'Enter the limit.';
		if (!startsAt) nextErrors.starts_at = 'Choose when it starts.';
		if (!endsAt) nextErrors.ends_at = 'Choose when it ends.';
		fieldErrors = nextErrors;
		if (Object.keys(nextErrors).length) return;
		const [kind, ...rest] = target.split(':');
		exceptionMutation.mutate({
			action: 'add',
			idempotency_key: dialogKey,
			target: kind as 'capability' | 'allowance',
			key: rest.join(':'),
			capability_state: kind === 'capability' ? capabilityState : null,
			allowance_state: kind === 'allowance' ? allowanceState : null,
			allowance_value:
				kind === 'allowance' && allowanceState === 'numeric' ? Number(allowanceValue) : null,
			starts_at: localDateTimeToIso(startsAt),
			ends_at: localDateTimeToIso(endsAt),
			reason: reason.trim()
		});
	}
	function submitEnd(event: SubmitEvent) {
		event.preventDefault();
		if (!ending) return;
		if (reason.trim().length < 3) {
			fieldErrors = { reason: 'Enter a reason of at least 3 characters.' };
			return;
		}
		exceptionMutation.mutate({
			action: 'end',
			idempotency_key: dialogKey,
			exception_id: ending.id,
			reason: reason.trim()
		});
	}

	function capabilityNow(row: EntitlementCapability) {
		return row.effective ? 'On' : 'Off';
	}
	function allowanceNow(row: EntitlementAllowance) {
		return allowanceText(row.exception ?? row.package, row.unit, row.resets_monthly);
	}
</script>

{#if feedback}
	<Banner type="success">{feedback}</Banner>
{/if}

{#if accessQuery.isPending}
	<LoadingSkeleton variant="card" label="Loading features" />
	<LoadingSkeleton variant="card" label="Loading limits" />
{:else if accessQuery.isError}
	<Banner type="error">
		{accessQuery.error.message}
		<Button size="small" variant="secondary" onclick={() => accessQuery.refetch()}>Try again</Button
		>
	</Banner>
{:else}
	<SectionBlock
		title="Features"
		icon={toggleIcon}
		hint="What the package includes, and what an exception switches on or off for now. Features in every package cannot be excepted."
	>
		<DataTable
			caption="Features"
			columns={featureColumns}
			items={capabilities}
			rowId={(row) => row.key}
		>
			{#snippet row(row)}
				<td>
					<strong>{row.label}</strong>
					<span class="access-exceptions__secondary">{row.description}</span>
				</td>
				<td>
					{#if row.kind === 'core'}
						Every package
					{:else}
						{row.in_package ? 'Included' : 'Not included'}
						{#if row.kind === 'planned'}
							<span class="access-exceptions__secondary">Not built yet</span>
						{/if}
					{/if}
				</td>
				<td>
					<Badge status={row.effective ? 'success' : 'inactive'} size="small"
						>{capabilityNow(row)}</Badge
					>
					{#if row.exception}
						<span class="access-exceptions__secondary"
							>Exception until {formatDateTime(row.exception.ends_at)}</span
						>
					{/if}
				</td>
				<td class="align-end">
					{#if row.kind === 'extra' && !row.exception}
						<Button size="small" variant="tertiary" onclick={() => openAdd(`capability:${row.key}`)}
							>Add exception</Button
						>
					{/if}
				</td>
			{/snippet}
		</DataTable>
	</SectionBlock>

	<SectionBlock
		title="Limits"
		icon={gaugeIcon}
		hint="The package's limits, any exception running now, and what the customer uses. Email and chat counts reset every month."
	>
		<DataTable caption="Limits" columns={limitColumns} items={allowances} rowId={(row) => row.key}>
			{#snippet row(row)}
				<td><strong>{row.label}</strong></td>
				<td>{allowanceText(row.package, row.unit, row.resets_monthly)}</td>
				<td>
					{allowanceNow(row)}
					{#if row.exception}
						<span class="access-exceptions__secondary"
							>Exception until {formatDateTime(row.exception.ends_at)}</span
						>
					{/if}
				</td>
				<td class="align-end access-exceptions__number">{row.in_use ?? '—'}</td>
				<td class="align-end">
					{#if !row.exception}
						<Button size="small" variant="tertiary" onclick={() => openAdd(`allowance:${row.key}`)}
							>Add exception</Button
						>
					{/if}
				</td>
			{/snippet}
		</DataTable>
	</SectionBlock>

	<SectionBlock
		title="Exceptions"
		icon={adjustmentsIcon}
		hint="Temporary changes on top of the package. Each has a reason and an end date, and stays listed after it ends."
	>
		{#snippet actions()}
			<Button size="small" variant="secondary" onclick={() => openAdd()}>Add exception</Button>
		{/snippet}

		{#if exceptions.length === 0}
			<EmptyState
				title="No exceptions"
				description="This customer gets exactly what their package includes."
			/>
		{:else}
			<DataTable
				caption="Exceptions"
				columns={exceptionColumns}
				items={exceptions}
				rowId={(row) => row.id}
				isExpanded={() => true}
			>
				{#snippet row(row)}
					{@const badge = statusBadges[row.status]}
					<td><strong>{row.label}</strong></td>
					<td>{exceptionChange(row)}</td>
					<td class="access-exceptions__secondary">
						{formatDateTime(row.starts_at)} – {formatDateTime(row.ends_at)}
					</td>
					<td><Badge status={badge.tone} size="small">{badge.label}</Badge></td>
					<td class="align-end">
						{#if row.status === 'active' || row.status === 'scheduled'}
							<Button
								size="small"
								variant="tertiary"
								variation="destructive"
								onclick={() => openEnd(row)}
								>{row.status === 'scheduled' ? 'Cancel' : 'End early'}</Button
							>
						{/if}
					</td>
				{/snippet}
				{#snippet rowDetail(row)}
					<ul class="access-exceptions__trail">
						<li>{row.reason} — {row.actor_owner_email}</li>
						{#if row.ended_early_at}
							<li class="access-exceptions__trail-ended">
								Ended early {formatDateTime(row.ended_early_at)}: {row.end_reason}{row.ended_by_email
									? ` — ${row.ended_by_email}`
									: ''}
							</li>
						{/if}
					</ul>
				{/snippet}
			</DataTable>
		{/if}
	</SectionBlock>
{/if}

{#if dialog === 'add'}
	<Dialog open title="Add exception" onClose={closeDialog} initialFocusId="exception-target">
		<form class="access-exceptions__form" onsubmit={submitAdd} novalidate>
			<div>
				<Select
					id="exception-target"
					label="Feature or limit"
					placeholder="Choose a feature or limit"
					value={target}
					options={targetOptions}
					onchange={chooseTarget}
				/>
				{#if fieldErrors.key}<p class="access-exceptions__error">{fieldErrors.key}</p>{/if}
			</div>

			{#if chosenCapability}
				<SegmentedControl
					label="Switch it"
					fullWidth
					bind:value={() => capabilityState, (value) => (capabilityState = value as 'on' | 'off')}
					options={[
						{ value: 'on', label: 'On' },
						{ value: 'off', label: 'Off' }
					]}
				/>
				<p class="access-exceptions__hint">
					The package {chosenCapability.in_package ? 'includes' : 'does not include'} this; it is
					{chosenCapability.effective ? 'on' : 'off'} now.
				</p>
			{:else if chosenAllowance}
				<SegmentedControl
					label="New limit"
					fullWidth
					bind:value={
						() => allowanceState,
						(value) => (allowanceState = value as PackageAllowanceSide['state'])
					}
					options={[
						{ value: 'numeric', label: 'A number' },
						{ value: 'unlimited', label: 'Unlimited' },
						{ value: 'not_included', label: 'Not included' }
					]}
				/>
				{#if allowanceState === 'numeric'}
					<Input
						id="exception-value"
						label={`Number of ${chosenAllowance.unit}${chosenAllowance.resets_monthly ? ' a month' : ''}`}
						type="number"
						min="0"
						bind:value={allowanceValue}
						invalid={Boolean(fieldErrors.allowance_value)}
						errorMessage={fieldErrors.allowance_value}
					/>
				{/if}
				<p class="access-exceptions__hint">
					Package: {allowanceText(
						chosenAllowance.package,
						chosenAllowance.unit,
						chosenAllowance.resets_monthly
					)}{chosenAllowance.in_use !== null ? ` · ${chosenAllowance.in_use} in use now` : ''}.
				</p>
			{/if}

			<DateTimePicker
				id="exception-starts"
				dateLabel="Starts"
				timeLabel="Start time"
				required
				value={dateTimePickerValueFromLocalString(startsAt)}
				onchange={(value: DateTimePickerValue) =>
					(startsAt = dateTimePickerValueToLocalString(value))}
				invalid={Boolean(fieldErrors.starts_at)}
				errorMessage={fieldErrors.starts_at}
			/>
			<DateTimePicker
				id="exception-ends"
				dateLabel="Ends"
				timeLabel="End time"
				required
				value={dateTimePickerValueFromLocalString(endsAt)}
				onchange={(value: DateTimePickerValue) =>
					(endsAt = dateTimePickerValueToLocalString(value))}
				invalid={Boolean(fieldErrors.ends_at)}
				errorMessage={fieldErrors.ends_at}
			/>
			<Textarea
				id="exception-reason"
				label="Reason"
				rows={2}
				maxlength={1000}
				bind:value={reason}
				invalid={Boolean(fieldErrors.reason)}
				errorMessage={fieldErrors.reason}
			/>

			{#if dialogError}<p class="access-exceptions__error" role="alert">{dialogError}</p>{/if}
			<div class="access-exceptions__actions">
				<Button type="button" variant="secondary" variation="subtle" onclick={closeDialog}
					>Close</Button
				>
				<Button type="submit" loading={exceptionMutation.isPending}>Add exception</Button>
			</div>
		</form>
	</Dialog>
{:else if dialog === 'end' && ending}
	<Dialog
		open
		title={ending.status === 'scheduled' ? 'Cancel exception' : 'End exception early'}
		size="small"
		onClose={closeDialog}
		initialFocusId="exception-end-reason"
	>
		<form class="access-exceptions__form" onsubmit={submitEnd} novalidate>
			<p>
				<strong>{ending.label}</strong> goes back to the package's value now. The exception stays in the
				list with your reason.
			</p>
			<Textarea
				id="exception-end-reason"
				label="Reason"
				rows={2}
				maxlength={1000}
				bind:value={reason}
				invalid={Boolean(fieldErrors.reason)}
				errorMessage={fieldErrors.reason}
			/>
			{#if dialogError}<p class="access-exceptions__error" role="alert">{dialogError}</p>{/if}
			<div class="access-exceptions__actions">
				<Button type="button" variant="secondary" variation="subtle" onclick={closeDialog}
					>Keep it</Button
				>
				<Button type="submit" variation="destructive" loading={exceptionMutation.isPending}
					>{ending.status === 'scheduled' ? 'Cancel exception' : 'End now'}</Button
				>
			</div>
		</form>
	</Dialog>
{/if}

<style lang="scss">
	.access-exceptions__secondary {
		display: block;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}
	.access-exceptions__number {
		font-variant-numeric: tabular-nums;
	}
	.access-exceptions__form {
		display: grid;
		gap: var(--space-base);
	}
	.access-exceptions__form p {
		margin: 0;
	}
	.access-exceptions__hint {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}
	.access-exceptions__error {
		margin: var(--space-smaller) 0 0;
		color: var(--color-critical);
		font-size: var(--typography--fontSize-small);
	}
	.access-exceptions__actions {
		display: flex;
		justify-content: flex-end;
		gap: var(--space-small);
	}
	.access-exceptions__trail {
		display: grid;
		gap: var(--space-smaller);
		margin: 0;
		padding: 0 0 0 var(--space-base);
		border-left: var(--border-thick, 2px) solid var(--color-border);
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		list-style: none;
	}
	.access-exceptions__trail-ended {
		font-style: italic;
	}
</style>
