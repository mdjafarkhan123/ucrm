<script lang="ts">
	import type { Snippet } from 'svelte';
	import { Calendar } from 'bits-ui';
	import {
		type DateValue,
		type CalendarDate,
		today,
		getLocalTimeZone
	} from '@internationalized/date';
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Checkbox from '$lib/components/ui/Checkbox.svelte';
	import { calendarDateToString } from '$lib/components/ui/date-time';
	import calendarPlusIcon from '@tabler/icons/outline/calendar-plus.svg?raw';
	import calendarCheckIcon from '@tabler/icons/outline/calendar-check.svg?raw';
	import checkIcon from '@tabler/icons/outline/check.svg?raw';
	import chevronLeftIcon from '@tabler/icons/outline/chevron-left.svg?raw';
	import chevronRightIcon from '@tabler/icons/outline/chevron-right.svg?raw';

	// Jobber's "Create Visits" step: pick one or many days at once and get a visit for each, or tick
	// "Schedule later" to add a single visit with no date yet. This dialog only chooses which days — the
	// times, titles and people are set afterwards on each visit's own card. It owns no writing; it hands the
	// chosen days back and closes.
	let {
		open,
		onClose,
		onCreate,
		mode = 'multiple',
		notice
	}: {
		open: boolean;
		onClose: () => void;
		/** `dates` is empty when "Schedule later" is chosen — that means one dateless visit. */
		onCreate: (result: {
			dates: string[];
			scheduleLater: boolean;
		}) => void | boolean | Promise<void | boolean>;
		/** `single` picks exactly one day (Add one visit); `multiple` picks many (Add multiple visits). */
		mode?: 'single' | 'multiple';
		/** Client reminders Part 4: the "Notify customer" box, shown above the buttons. */
		notice?: Snippet;
	} = $props();

	let saving = $state(false);
	let createError = $state('');
	let picked = $state<DateValue[]>([]);
	let scheduleLater = $state(false);
	// Past days cannot be booked; the calendar opens on this month.
	const minValue = today(getLocalTimeZone());

	const canCreate = $derived(scheduleLater || picked.length > 0);

	// In single mode the calendar still lives on the multi-select primitive, so keep only the newest pick —
	// tapping a second day replaces the first rather than adding a second visit.
	$effect(() => {
		if (mode === 'single' && picked.length > 1) picked = [picked[picked.length - 1]];
	});

	const heading = $derived(mode === 'single' ? 'Add a visit' : 'Create visits');

	function reset() {
		picked = [];
		scheduleLater = false;
	}

	function cancel() {
		if (saving) return;
		reset();
		onClose();
	}

	async function create() {
		if (!canCreate || saving) return;
		saving = true;
		createError = '';
		const dates = scheduleLater
			? []
			: picked
					.map((value) => calendarDateToString(value as CalendarDate))
					.filter((value): value is string => Boolean(value))
					.sort();
		try {
			const result = await onCreate({ dates, scheduleLater });
			if (result !== false) reset();
		} catch (caught) {
			createError = caught instanceof Error ? caught.message : 'Those visits could not be added.';
		} finally {
			saving = false;
		}
	}
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
{#if open}
	<Dialog
		{open}
		title={heading}
		size="small"
		icon={calendarPlusIcon}
		iconTone="job"
		onClose={cancel}
	>
		<div class="create-visits">
			<p class="create-visits__hint">
				{#if mode === 'single'}
					Pick the day this visit happens. You can set the time and who is going next.
				{:else}
					Pick every day this job needs a visit. You can set the time and who is going on each one
					next.
				{/if}
			</p>

			<Calendar.Root
				class="create-visits__calendar"
				type="multiple"
				bind:value={picked}
				{minValue}
				weekdayFormat="short"
				disabled={scheduleLater || saving}
			>
				{#snippet children({ months, weekdays })}
					<Calendar.Header class="create-visits__cal-header">
						<Calendar.PrevButton class="create-visits__nav" aria-label="Previous month">
							{@html chevronLeftIcon}
						</Calendar.PrevButton>
						<Calendar.Heading class="create-visits__heading" />
						<Calendar.NextButton class="create-visits__nav" aria-label="Next month">
							{@html chevronRightIcon}
						</Calendar.NextButton>
					</Calendar.Header>

					{#each months as month (month.value.toString())}
						<Calendar.Grid class="create-visits__grid">
							<Calendar.GridHead>
								<Calendar.GridRow>
									{#each weekdays as weekday, weekdayIndex (weekday + '-' + weekdayIndex)}
										<Calendar.HeadCell class="create-visits__weekday">{weekday}</Calendar.HeadCell>
									{/each}
								</Calendar.GridRow>
							</Calendar.GridHead>
							<Calendar.GridBody>
								{#each month.weeks as week (week[0]?.toString() ?? 'week')}
									<Calendar.GridRow>
										{#each week as date (date.toString())}
											<Calendar.Cell {date} month={month.value}>
												<Calendar.Day>
													{#snippet children({ day })}
														<span class="create-visits__day">{day}</span>
													{/snippet}
												</Calendar.Day>
											</Calendar.Cell>
										{/each}
									</Calendar.GridRow>
								{/each}
							</Calendar.GridBody>
						</Calendar.Grid>
					{/each}
				{/snippet}
			</Calendar.Root>

			<Checkbox
				id="create-visits-schedule-later"
				label="Schedule later"
				description="Add one visit now and pick the day once you know it."
				disabled={saving}
				bind:checked={scheduleLater}
			/>

			{#if !scheduleLater && picked.length > 0}
				<p class="create-visits__count">
					<span aria-hidden="true">{@html calendarCheckIcon}</span>
					{picked.length}
					{picked.length === 1 ? 'visit' : 'visits'} will be added.
				</p>
			{/if}

			{@render notice?.()}

			{#if createError}<p class="create-visits__error" role="alert">{createError}</p>{/if}
		</div>
		{#snippet footer()}
			<div class="create-visits__actions">
				<Button variant="secondary" onclick={cancel} disabled={saving}>Cancel</Button>
				<Button onclick={create} disabled={!canCreate} loading={saving}
					>{@html checkIcon}Create</Button
				>
			</div>
		{/snippet}
	</Dialog>
{/if}

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.create-visits {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);

		&__hint {
			margin: 0;
			color: var(--color-text);
			font-size: var(--typography--fontSize-base);
			line-height: 1.5;
		}

		&__count {
			display: flex;
			align-items: center;
			gap: var(--space-small);
			:global(svg) {
				width: 16px;
				height: 16px;
				color: var(--color-job);
			}
			margin: 0;
			color: var(--color-heading);
			font-size: var(--typography--fontSize-label);
			font-weight: 600;
		}

		&__actions {
			display: flex;
			justify-content: flex-end;
			gap: var(--space-small);
			width: 100%;
		}

		:global(.create-visits__calendar) {
			width: 100%;
			box-sizing: border-box;
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-tile-large);
			padding: var(--space-slim);
		}

		:global(.create-visits__cal-header) {
			display: grid;
			grid-template-columns: 32px 1fr 32px;
			align-items: center;
			gap: var(--space-small);
			margin-bottom: var(--space-small);
			padding: var(--space-smaller);
			border-radius: var(--radius-small);
			background: var(--color-surface);
		}

		:global(.create-visits__nav) {
			display: grid;
			width: 32px;
			height: 32px;
			place-items: center;
			border: var(--border-base) solid var(--color-border--interactive);
			border-radius: var(--radius-base);
			color: var(--color-interactive--subtle);
			background: transparent;
			cursor: pointer;
			transition:
				color var(--timing-quick),
				background-color var(--timing-quick);

			&:hover {
				color: var(--color-heading);
				background: var(--color-surface--hover);
			}
			&:focus-visible {
				outline: none;
				box-shadow: var(--shadow-focus);
			}
		}

		:global(.create-visits__nav svg) {
			width: 20px;
			height: 20px;
		}

		:global(.create-visits__heading) {
			color: var(--color-heading);
			font-size: var(--typography--fontSize-base);
			font-weight: 600;
			text-align: center;
		}

		:global(.create-visits__grid) {
			width: 100%;
			border-collapse: separate;
			border-spacing: 0 6px;
		}

		:global(.create-visits__weekday) {
			padding-bottom: var(--space-small);
			text-transform: uppercase;
			letter-spacing: 0.6px;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			font-weight: 600;
			text-align: center;
		}

		:global(.create-visits__day) {
			display: grid;
			width: 36px;
			height: 36px;
			place-items: center;
			margin: 0 auto;
			border: var(--border-base) solid transparent;
			border-radius: var(--radius-circle);
			color: var(--color-text);
			font-size: var(--typography--fontSize-base);
			line-height: 1;
			cursor: pointer;
			transition:
				color var(--timing-quick),
				background-color var(--timing-quick),
				border-color var(--timing-quick);
		}

		:global([data-selected] .create-visits__day) {
			border-color: var(--color-interactive);
			color: var(--color-surface);
			background: var(--color-interactive);
			font-weight: 700;
		}

		:global([data-today]:not([data-selected]) .create-visits__day) {
			border-color: var(--color-interactive);
			color: var(--color-interactive--subtle);
			font-weight: 700;
		}

		:global([data-highlighted]:not([data-selected]) .create-visits__day),
		:global([data-focused]:not([data-selected]) .create-visits__day) {
			background: var(--color-surface--hover);
		}

		:global([data-outside-month] .create-visits__day) {
			visibility: hidden;
		}
		&__error {
			color: var(--color-critical--onSurface);
			font-size: var(--typography--fontSize-label);
		}
		:global([data-disabled] .create-visits__day),
		:global([data-outside-month] .create-visits__day),
		:global([data-unavailable] .create-visits__day) {
			color: var(--color-disabled);
			cursor: default;
			opacity: 0.55;
		}
	}
</style>
