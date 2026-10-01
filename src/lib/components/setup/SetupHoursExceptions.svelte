<script lang="ts">
	import { untrack } from 'svelte';
	import type { CalendarDate } from '@internationalized/date';
	import CalendarPicker from '$lib/components/ui/CalendarPicker.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import TimePicker from '$lib/components/ui/TimePicker.svelte';
	import Toggle from '$lib/components/ui/Toggle.svelte';
	import {
		calendarDateFromString,
		calendarDateToString,
		timeFromString,
		timeToString,
		type TimeRangeValue
	} from '$lib/components/ui/date-time';
	import {
		HOURS_EXCEPTION_NAME_MAX,
		HOURS_EXCEPTIONS_MAX,
		parseSetupHoursExceptions,
		type SetupHoursException
	} from '$lib/setup/hours';
	import plusIcon from '@tabler/icons/outline/plus.svg?raw';
	import trashIcon from '@tabler/icons/outline/trash.svg?raw';

	// The dated days that differ from the normal week — closed, or open at different times. Like the
	// weekly hours field it reads and writes the answer as JSON text and reports every edit.
	let {
		id,
		value = $bindable(''),
		onchange
	}: {
		id: string;
		value?: string;
		onchange: () => void;
	} = $props();

	type Row = {
		uid: number;
		date: CalendarDate | undefined;
		name: string;
		closed: boolean;
		period: TimeRangeValue;
	};

	let nextUid = 0;
	const defaultPeriod = (): TimeRangeValue => ({
		start: timeFromString('09:00'),
		end: timeFromString('13:00')
	});

	function toRow(exception: SetupHoursException): Row {
		return {
			uid: nextUid++,
			date: calendarDateFromString(exception.date),
			name: exception.name,
			closed: exception.closed,
			period: exception.closed
				? defaultPeriod()
				: { start: timeFromString(exception.opens), end: timeFromString(exception.closes) }
		};
	}

	let rows = $state<Row[]>(
		untrack(() => (value ? (parseSetupHoursExceptions(value).value ?? []) : []).map(toRow))
	);

	// A row is part of the answer once it has a date. One that is open but missing a time is still being
	// filled in, so it waits.
	function emit() {
		const answer: SetupHoursException[] = [];
		for (const row of rows) {
			if (!row.date) continue;
			const date = calendarDateToString(row.date);
			const name = row.name.trim();
			if (row.closed) {
				answer.push({ date, name, closed: true, opens: null, closes: null });
				continue;
			}
			const opens = timeToString(row.period.start);
			const closes = timeToString(row.period.end);
			if (!opens || !closes || opens === closes) continue;
			answer.push({ date, name, closed: false, opens, closes });
		}
		value = answer.length > 0 ? JSON.stringify(answer) : '';
		onchange();
	}

	function addRow() {
		if (rows.length >= HOURS_EXCEPTIONS_MAX) return;
		rows.push({ uid: nextUid++, date: undefined, name: '', closed: true, period: defaultPeriod() });
	}

	function removeRow(index: number) {
		rows.splice(index, 1);
		emit();
	}
</script>

<div class="setup-exceptions">
	{#each rows as row, index (row.uid)}
		<div class="setup-exceptions__row">
			<div class="setup-exceptions__main">
				<CalendarPicker
					id={`${id}-date-${row.uid}`}
					label="Date"
					bind:value={row.date}
					onchange={emit}
				/>
				<Input
					id={`${id}-name-${row.uid}`}
					label="What is it?"
					placeholder="Christmas Day"
					bind:value={row.name}
					maxlength={HOURS_EXCEPTION_NAME_MAX}
					oninput={emit}
				/>
				<button
					type="button"
					class="setup-exceptions__remove"
					aria-label={`Remove ${row.name.trim() || 'this date'}`}
					onclick={() => removeRow(index)}
					><!-- eslint-disable-next-line svelte/no-at-html-tags -->
					{@html trashIcon}</button
				>
			</div>
			<div class="setup-exceptions__hours">
				<Toggle
					id={`${id}-closed-${row.uid}`}
					label={row.closed ? 'Closed all day' : 'Open at different times'}
					checked={row.closed}
					onchange={(checked) => {
						row.closed = checked;
						emit();
					}}
				/>
				{#if !row.closed}
					<TimePicker bind:value={row.period} range label="Open on this day" onchange={emit} />
				{/if}
			</div>
		</div>
	{/each}

	{#if rows.length < HOURS_EXCEPTIONS_MAX}
		<button type="button" class="setup-exceptions__add" onclick={addRow}
			><!-- eslint-disable-next-line svelte/no-at-html-tags -->
			{@html plusIcon}
			{rows.length === 0 ? 'Add a date' : 'Add another date'}</button
		>
	{/if}
</div>

<style lang="scss">
	.setup-exceptions {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);
		min-width: 0;

		&__row {
			display: flex;
			flex-direction: column;
			gap: var(--space-base);
			min-width: 0;
			padding: var(--space-base);
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-base);
		}

		&__main {
			display: grid;
			grid-template-columns: minmax(0, 200px) minmax(0, 1fr) auto;
			align-items: end;
			gap: var(--space-small);
		}

		&__hours {
			display: flex;
			flex-wrap: wrap;
			align-items: center;
			gap: var(--space-base);
		}

		&__remove {
			display: grid;
			width: 40px;
			height: 40px;
			place-items: center;
			border: var(--border-base) solid var(--color-border--interactive);
			border-radius: var(--radius-base);
			color: var(--color-icon--secondary);
			background: var(--color-surface);

			&:hover {
				color: var(--color-critical--onSurface);
				background: var(--color-surface--hover);
			}

			&:focus-visible {
				outline: none;
				box-shadow: var(--shadow-focus);
			}

			:global(svg) {
				width: 18px;
				height: 18px;
			}
		}

		&__add {
			display: inline-flex;
			align-items: center;
			gap: var(--space-smaller);
			width: fit-content;
			padding: var(--space-small) var(--space-base);
			border: var(--border-base) dashed var(--color-border--interactive);
			border-radius: var(--radius-base);
			color: var(--color-interactive);
			background: transparent;
			font-size: var(--typography--fontSize-small);
			font-weight: 600;

			&:hover {
				background: var(--color-surface--hover);
			}

			&:focus-visible {
				outline: none;
				box-shadow: var(--shadow-focus);
			}

			:global(svg) {
				width: 14px;
				height: 14px;
			}
		}
	}

	@media (max-width: 600px) {
		.setup-exceptions__main {
			grid-template-columns: minmax(0, 1fr) auto;

			// The date and the remove button share the first line; the name takes the whole second one.
			:global(> :nth-child(2)) {
				grid-row: 2;
				grid-column: 1 / -1;
			}
		}
	}
</style>
