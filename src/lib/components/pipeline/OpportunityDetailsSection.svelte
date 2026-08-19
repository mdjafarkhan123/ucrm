<script lang="ts">
	import { createMutation, useQueryClient } from '@tanstack/svelte-query';
	import { CalendarDate } from '@internationalized/date';
	import Avatar from '$lib/components/ui/Avatar.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import CalendarPicker from '$lib/components/ui/CalendarPicker.svelte';
	import PencilButton from '$lib/components/ui/PencilButton.svelte';
	import OpportunityOwnerField from './OpportunityOwnerField.svelte';
	import { followUp, formatMoney, type BoardFormatting } from '$lib/pipeline/money';
	import {
		invalidatePipeline,
		updateOpportunityExpectedClose,
		updateOpportunityNextFollowUp,
		updateOpportunityValue,
		type OpportunityCard
	} from '$lib/pipeline/api';
	import xIcon from '@tabler/icons/outline/x.svg?raw';

	// The Brief's Opportunity details block: salesperson, estimated value, expected close, and next
	// follow-up, each editable in place. The parent keys this component by `opportunity.id` — switching
	// cards remounts it, which is what resets a mid-edit row rather than an effect syncing local state to
	// a prop.
	let {
		opportunity,
		formatting,
		canEdit,
		onUpdate
	}: {
		opportunity: OpportunityCard;
		formatting: BoardFormatting | null;
		canEdit: boolean;
		// Patches the Brief's own held copy of the card. `invalidatePipeline` refreshes the board behind
		// it, but the Brief is a snapshot from the moment it was opened — nothing else refetches it into
		// view, so a successful edit has to be reflected here directly.
		onUpdate: (patch: Partial<OpportunityCard>) => void;
	} = $props();

	// Absent, not null, for a member who may not see money — one row fewer for them, not a blank one.
	const canViewValue = $derived('estimated_value' in opportunity);
	const amount = $derived(formatting ? formatMoney(opportunity.estimated_value, formatting) : null);
	const chase = $derived(formatting ? followUp(opportunity.next_follow_up_on, formatting) : null);
	const closeOn = $derived(formatting ? followUp(opportunity.expected_close_on, formatting) : null);

	const queryClient = useQueryClient();

	// Which one row, if any, is open for editing. Only one at a time — opening a second field closes the
	// first rather than staging two drafts nobody asked to compare.
	let editingField = $state<'value' | 'expectedClose' | 'nextFollowUp' | null>(null);
	let valueDraft = $state('');
	let valueError = $state('');
	let expectedCloseError = $state('');
	let nextFollowUpError = $state('');

	const valueMutation = createMutation(() => ({
		mutationFn: (next: number | null) => updateOpportunityValue(opportunity.id, next),
		onSuccess: (result) => {
			invalidatePipeline(queryClient);
			onUpdate({ estimated_value: result.estimated_value });
			editingField = null;
		},
		// Kept inline rather than a toast — the checklist calls for the field to show its own failure so
		// the value being retried stays visible next to the message that explains it.
		onError: (error: Error) => {
			valueError = error.message;
		}
	}));

	const expectedCloseMutation = createMutation(() => ({
		mutationFn: (next: string | null) => updateOpportunityExpectedClose(opportunity.id, next),
		onSuccess: (result) => {
			invalidatePipeline(queryClient);
			onUpdate({ expected_close_on: result.expected_close_on });
			editingField = null;
		},
		onError: (error: Error) => {
			expectedCloseError = error.message;
		}
	}));

	const nextFollowUpMutation = createMutation(() => ({
		mutationFn: (next: string | null) => updateOpportunityNextFollowUp(opportunity.id, next),
		onSuccess: (result) => {
			invalidatePipeline(queryClient);
			onUpdate({ next_follow_up_on: result.next_follow_up_on });
			editingField = null;
		},
		onError: (error: Error) => {
			nextFollowUpError = error.message;
		}
	}));

	function startEditingValue() {
		valueDraft = opportunity.estimated_value != null ? String(opportunity.estimated_value) : '';
		valueError = '';
		editingField = 'value';
	}

	// Blur commits, matching the rest of the app's click-away-to-save inline editors. Escape reverts
	// without saving, same as any other cancel.
	function commitValue() {
		if (editingField !== 'value') return;
		const trimmed = valueDraft.trim();
		if (trimmed === '') {
			valueMutation.mutate(null);
			return;
		}
		const parsed = Number(trimmed);
		if (!Number.isFinite(parsed) || parsed < 0) {
			valueError = 'Enter a valid amount, 0 or more.';
			return;
		}
		valueMutation.mutate(parsed);
	}
	function handleValueKeydown(event: KeyboardEvent) {
		if (event.key === 'Enter') {
			event.preventDefault();
			commitValue();
		} else if (event.key === 'Escape') {
			event.preventDefault();
			editingField = null;
			valueError = '';
		}
	}

	// The pickers speak CalendarDate; the database speaks `2026-08-19`, same conversion `BoardControls`
	// uses for the filter bar's date range.
	function toCalendarDate(day: string | null | undefined) {
		if (!day) return undefined;
		const [year, month, date] = day.split('-').map(Number);
		return new CalendarDate(year, month, date);
	}
	function toDay(value: CalendarDate | undefined) {
		if (!value) return null;
		return `${value.year}-${String(value.month).padStart(2, '0')}-${String(value.day).padStart(2, '0')}`;
	}

	function commitExpectedClose(value: CalendarDate | undefined) {
		expectedCloseError = '';
		expectedCloseMutation.mutate(toDay(value));
	}
	function clearExpectedClose() {
		expectedCloseError = '';
		expectedCloseMutation.mutate(null);
	}
	function commitNextFollowUp(value: CalendarDate | undefined) {
		nextFollowUpError = '';
		nextFollowUpMutation.mutate(toDay(value));
	}
	function clearNextFollowUp() {
		nextFollowUpError = '';
		nextFollowUpMutation.mutate(null);
	}
</script>

<section class="brief__details" aria-labelledby="brief-details-heading">
	<h3 id="brief-details-heading" class="brief__details-heading">Opportunity details</h3>
	<dl class="brief__list">
		<div class="brief__row">
			<dt>Salesperson</dt>
			<dd>
				{#if canEdit}
					<OpportunityOwnerField
						opportunityId={opportunity.id}
						ownerName={opportunity.owner?.full_name ?? 'Unassigned'}
						{canEdit}
						triggerClass="brief__owner-trigger"
						align="end"
						onAssigned={(owner) => onUpdate({ owner })}
					>
						{#snippet trigger()}
							{#if opportunity.owner}
								<Avatar
									id={opportunity.owner.id}
									name={opportunity.owner.full_name}
									src={opportunity.owner.avatar_url}
									size="small"
								/>
								{opportunity.owner.full_name ?? 'No longer on the team'}
							{:else}
								<span class="brief__blank">Unassigned</span>
							{/if}
						{/snippet}
					</OpportunityOwnerField>
				{:else if opportunity.owner}
					<span class="brief__owner">
						<Avatar
							id={opportunity.owner.id}
							name={opportunity.owner.full_name}
							src={opportunity.owner.avatar_url}
							size="small"
						/>
						{opportunity.owner.full_name ?? 'No longer on the team'}
					</span>
				{:else}
					<span class="brief__blank">Unassigned</span>
				{/if}
			</dd>
		</div>
		{#if canViewValue}
			<div class="brief__row">
				<dt>Estimated value</dt>
				<dd>
					{#if editingField === 'value'}
						<div class="brief__editor">
							<Input
								id="brief-value-input"
								type="text"
								inputmode="decimal"
								size="small"
								aria-label="Estimated value"
								bind:value={valueDraft}
								invalid={Boolean(valueError)}
								errorMessage={valueError}
								disabled={valueMutation.isPending}
								onblur={commitValue}
								onkeydown={handleValueKeydown}
							/>
						</div>
					{:else}
						<span class="brief__value-row">
							{#if amount}
								{amount}
							{:else}
								<span class="brief__blank">Not estimated yet</span>
							{/if}
							{#if canEdit}
								<PencilButton label="Edit estimated value" onclick={startEditingValue} />
							{/if}
						</span>
					{/if}
				</dd>
			</div>
		{/if}
		<div class="brief__row">
			<dt>Expected close</dt>
			<dd>
				{#if editingField === 'expectedClose'}
					<div class="brief__editor brief__editor--date">
						<CalendarPicker
							id="brief-expected-close-input"
							label="Expected close"
							value={toCalendarDate(opportunity.expected_close_on)}
							invalid={Boolean(expectedCloseError)}
							errorMessage={expectedCloseError}
							disabled={expectedCloseMutation.isPending}
							onchange={commitExpectedClose}
						/>
						{#if opportunity.expected_close_on}
							<button
								type="button"
								class="brief__editor-clear"
								disabled={expectedCloseMutation.isPending}
								onclick={clearExpectedClose}
							>
								Clear
							</button>
						{/if}
						<button
							type="button"
							class="brief__editor-cancel"
							aria-label="Close expected close editor"
							onclick={() => (editingField = null)}
						>
							<!-- eslint-disable-next-line svelte/no-at-html-tags -->
							{@html xIcon}
						</button>
					</div>
				{:else}
					<span class="brief__value-row">
						{#if closeOn}{closeOn.label}{:else}<span class="brief__blank">No date set</span>{/if}
						{#if canEdit}
							<PencilButton
								label="Edit expected close date"
								onclick={() => {
									expectedCloseError = '';
									editingField = 'expectedClose';
								}}
							/>
						{/if}
					</span>
				{/if}
			</dd>
		</div>
		<div class="brief__row">
			<dt>Next follow-up</dt>
			<dd>
				{#if editingField === 'nextFollowUp'}
					<div class="brief__editor brief__editor--date">
						<CalendarPicker
							id="brief-next-follow-up-input"
							label="Next follow-up"
							value={toCalendarDate(opportunity.next_follow_up_on)}
							invalid={Boolean(nextFollowUpError)}
							errorMessage={nextFollowUpError}
							disabled={nextFollowUpMutation.isPending}
							onchange={commitNextFollowUp}
						/>
						{#if opportunity.next_follow_up_on}
							<button
								type="button"
								class="brief__editor-clear"
								disabled={nextFollowUpMutation.isPending}
								onclick={clearNextFollowUp}
							>
								Clear
							</button>
						{/if}
						<button
							type="button"
							class="brief__editor-cancel"
							aria-label="Close next follow-up editor"
							onclick={() => (editingField = null)}
						>
							<!-- eslint-disable-next-line svelte/no-at-html-tags -->
							{@html xIcon}
						</button>
					</div>
				{:else}
					<span class="brief__value-row">
						{#if chase}
							<span class={chase.overdue ? 'brief__overdue' : ''}>
								{chase.label}
								{#if chase.overdue}<span class="brief__overdue-word">Overdue</span>{/if}
							</span>
						{:else}
							<span class="brief__blank">No follow-up set</span>
						{/if}
						{#if canEdit}
							<PencilButton
								label="Edit next follow-up date"
								onclick={() => {
									nextFollowUpError = '';
									editingField = 'nextFollowUp';
								}}
							/>
						{/if}
					</span>
				{/if}
			</dd>
		</div>
	</dl>
</section>

<style lang="scss">
	.brief__details {
		display: flex;
		flex-direction: column;
		gap: var(--space-small);
	}
	.brief__details-heading {
		color: var(--color-heading);
		font-size: var(--typography--fontSize-small);
		font-weight: 700;
		text-transform: uppercase;
		letter-spacing: 0.04em;
	}
	.brief__list {
		display: flex;
		flex-direction: column;
		gap: var(--space-small);
	}
	.brief__row {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-base);

		dt {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}
		dd {
			color: var(--color-text);
			font-size: var(--typography--fontSize-small);
			font-weight: 600;
			text-align: right;
		}
	}
	.brief__owner {
		display: inline-flex;
		align-items: center;
		gap: var(--space-small);
	}
	:global(.brief__owner-trigger) {
		display: inline-flex;
		align-items: center;
		gap: var(--space-small);
		padding: 4px 6px;
		margin: -4px -6px;
		border: 0;
		border-radius: var(--radius-base);
		color: var(--color-text);
		background: transparent;
		font-size: var(--typography--fontSize-small);
		font-weight: 600;
		cursor: pointer;
		transition: background var(--timing-quick);

		&:hover {
			background: var(--color-surface--hover);
		}
		&:focus-visible {
			outline: none;
			box-shadow: var(--shadow-focus);
		}
	}
	.brief__value-row {
		display: inline-flex;
		align-items: center;
		gap: var(--space-small);
	}
	.brief__editor {
		display: inline-flex;
		align-items: center;
		gap: var(--space-smallest);
		max-width: 220px;
	}
	.brief__editor--date {
		flex-wrap: wrap;
		justify-content: flex-end;
	}
	.brief__editor-clear {
		flex: 0 0 auto;
		padding: 0 var(--space-smallest);
		border: 0;
		background: transparent;
		color: var(--color-interactive);
		font-size: var(--typography--fontSize-small);
		font-weight: 400;
		cursor: pointer;

		&:hover {
			color: var(--color-interactive--hover);
			text-decoration: underline;
		}
	}
	.brief__editor-cancel {
		display: inline-grid;
		flex: 0 0 auto;
		width: 28px;
		height: 28px;
		place-items: center;
		border: 0;
		border-radius: var(--radius-base);
		color: var(--color-icon--secondary);
		background: transparent;
		cursor: pointer;
		transition: all var(--timing-base) ease-out;

		&:hover {
			color: var(--color-icon);
			background: var(--color-surface--hover);
		}
		&:focus-visible {
			outline: none;
			box-shadow: var(--shadow-focus);
		}

		:global(svg) {
			display: block;
			width: 16px;
			height: 16px;
		}
	}
	.brief__blank {
		color: var(--color-text--secondary);
		font-weight: 400;
	}
	.brief__overdue {
		color: var(--color-critical--onSurface);
	}
	.brief__overdue-word {
		text-transform: uppercase;
		&::before {
			content: '· ';
		}
		font-size: var(--typography--fontSize-smaller);
		letter-spacing: 0.04em;
	}
</style>
