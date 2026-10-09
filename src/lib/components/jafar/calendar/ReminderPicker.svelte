<script lang="ts">
	import { Time } from '@internationalized/date';
	import Button from '$lib/components/ui/Button.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import TimePickerField from '$lib/components/ui/TimePickerField.svelte';
	import {
		MAX_DAYS_BEFORE,
		MAX_MINUTES_BEFORE,
		MAX_REMINDERS,
		reminderLabel,
		type DayReminder,
		type ReminderChannel,
		type ReminderRule,
		type TimedReminder
	} from '$lib/jafar/calendar';
	import plusIcon from '@tabler/icons/outline/plus.svg?raw';
	import xIcon from '@tabler/icons/outline/x.svg?raw';
	import bellIcon from '@tabler/icons/outline/bell.svg?raw';

	// Jafar business management C2: how many reminders a call or a next action has and when each comes, as Google
	// Calendar's notification rows do -- "Email · 1 · day before". `timed` items (a call, a follow-up with a time)
	// count back from their start; a day-only follow-up counts days back to a time of day. `value` null follows
	// the defaults from My preferences, shown in words with a Change button; `defaults` seeds the rows then.
	// With `allowDefaults` off (My preferences itself) the rows are always shown.

	let {
		id,
		value = $bindable(),
		timed,
		defaults,
		allowDefaults = true,
		label = 'Reminders'
	}: {
		id: string;
		value: ReminderRule[] | null;
		timed: boolean;
		defaults: ReminderRule[];
		allowDefaults?: boolean;
		label?: string;
	} = $props();

	const CHANNELS = [
		{ value: 'in_app', label: 'Alert' },
		{ value: 'email', label: 'Email' }
	];

	const UNITS = [
		{ value: 'minute', label: 'minutes', minutes: 1 },
		{ value: 'hour', label: 'hours', minutes: 60 },
		{ value: 'day', label: 'days', minutes: 24 * 60 },
		{ value: 'week', label: 'weeks', minutes: 7 * 24 * 60 }
	];

	// Defaults of the wrong shape (a timed list for a day-only item) are not offered; the rows start empty.
	const fitting = (rules: ReminderRule[]) =>
		rules.filter((rule) => 'minutes_before' in rule === timed);

	const rows = $derived(value === null ? null : fitting(value));

	/** The largest unit that divides evenly, so 1440 minutes reads "1 day". */
	function splitMinutes(minutes: number) {
		const unit =
			[...UNITS].reverse().find((candidate) => minutes % candidate.minutes === 0 && minutes > 0) ??
			UNITS[0];
		return { amount: minutes / unit.minutes, unit: unit.value };
	}

	function unitMinutes(unit: string) {
		return UNITS.find((candidate) => candidate.value === unit)?.minutes ?? 1;
	}

	function replace(index: number, rule: ReminderRule) {
		if (!rows) return;
		value = rows.map((current, position) => (position === index ? rule : current));
	}

	function remove(index: number) {
		if (!rows) return;
		value = rows.filter((_, position) => position !== index);
	}

	function add() {
		const base = rows ?? [];
		const next: ReminderRule = timed
			? { channel: 'in_app', minutes_before: 15 }
			: { channel: 'in_app', days_before: 0, at: '09:00' };
		value = [...base, next];
	}

	function customise() {
		value = fitting(defaults).map((rule) => ({ ...rule }));
	}

	function setChannel(index: number, rule: ReminderRule, channel: string) {
		replace(index, { ...rule, channel: channel as ReminderChannel });
	}

	function setTimedAmount(index: number, rule: TimedReminder, raw: string) {
		const amount = Number(raw);
		if (!Number.isInteger(amount) || amount < 0) return;
		const { unit } = splitMinutes(rule.minutes_before);
		replace(index, {
			...rule,
			minutes_before: Math.min(MAX_MINUTES_BEFORE, amount * unitMinutes(unit))
		});
	}

	function setTimedUnit(index: number, rule: TimedReminder, unit: string) {
		const { amount } = splitMinutes(rule.minutes_before);
		replace(index, {
			...rule,
			minutes_before: Math.min(MAX_MINUTES_BEFORE, Math.max(amount, 1) * unitMinutes(unit))
		});
	}

	function setDays(index: number, rule: DayReminder, raw: string) {
		const days = Number(raw);
		if (!Number.isInteger(days) || days < 0) return;
		replace(index, { ...rule, days_before: Math.min(MAX_DAYS_BEFORE, days) });
	}

	function setAt(index: number, rule: DayReminder, time: Time | undefined) {
		if (!time) return;
		const at = `${String(time.hour).padStart(2, '0')}:${String(time.minute).padStart(2, '0')}`;
		replace(index, { ...rule, at });
	}

	const DAY_CHOICES = [0, 1, 2, 3, 4, 5, 6, 7, 14, 21, MAX_DAYS_BEFORE];

	/** "On the day", "1 day before" ... plus the saved one if it is not a usual choice. */
	function dayOptions(current: number) {
		const choices = DAY_CHOICES.includes(current)
			? DAY_CHOICES
			: [...DAY_CHOICES, current].sort((a, b) => a - b);
		return choices.map((days) => ({
			value: String(days),
			label: days === 0 ? 'On the day' : `${days} day${days === 1 ? '' : 's'} before`
		}));
	}

	function timeOf(at: string) {
		const [hour, minute] = at.split(':').map(Number);
		return new Time(hour, minute);
	}

	const defaultWords = $derived(
		fitting(defaults).length ? fitting(defaults).map(reminderLabel).join(' · ') : 'No reminders'
	);
</script>

<!-- The icons are Tabler SVG files imported at build time, not user content. -->
<!-- eslint-disable svelte/no-at-html-tags -->
<fieldset class="reminder-picker" aria-describedby="{id}-hint">
	<legend class="reminder-picker__label">{label}</legend>

	{#if rows === null}
		<div class="reminder-picker__defaults">
			<span class="reminder-picker__bell" aria-hidden="true">{@html bellIcon}</span>
			<p class="reminder-picker__summary" id="{id}-hint">
				<span class="reminder-picker__muted">My defaults:</span>
				{defaultWords}
			</p>
			<Button variant="tertiary" size="small" onclick={customise}>Change</Button>
		</div>
	{:else}
		{#if rows.length === 0}
			<p class="reminder-picker__muted" id="{id}-hint">No reminders.</p>
		{:else}
			<p class="reminder-picker__sr" id="{id}-hint">
				{rows.length} reminder{rows.length === 1 ? '' : 's'}
			</p>
		{/if}
		<ul class="reminder-picker__rows">
			{#each rows as rule, index (index)}
				<li class="reminder-picker__row">
					<Select
						id="{id}-channel-{index}"
						class="reminder-picker__select"
						ariaLabel="Reminder {index + 1}: alert or email"
						options={CHANNELS}
						value={rule.channel}
						fitOptions
						onchange={(channel) => setChannel(index, rule, channel)}
					/>
					<div class="reminder-picker__when">
						{#if 'minutes_before' in rule}
							{@const split = splitMinutes(rule.minutes_before)}
							{#if rule.minutes_before === 0}
								<span class="reminder-picker__words">at the time</span>
								<button
									type="button"
									class="reminder-picker__link"
									onclick={() => replace(index, { ...rule, minutes_before: 15 })}
									>set earlier</button
								>
							{:else}
								<input
									class="reminder-picker__amount"
									type="number"
									inputmode="numeric"
									min="0"
									aria-label="Reminder {index + 1}: how many"
									value={split.amount}
									oninput={(event) => setTimedAmount(index, rule, event.currentTarget.value)}
								/>
								<Select
									id="{id}-unit-{index}"
									class="reminder-picker__select"
									ariaLabel="Reminder {index + 1}: unit"
									options={UNITS.map(({ value, label }) => ({ value, label }))}
									value={split.unit}
									fitOptions
									onchange={(unit) => setTimedUnit(index, rule, unit)}
								/>
								<span class="reminder-picker__words">before</span>
							{/if}
						{:else}
							<Select
								id="{id}-days-{index}"
								class="reminder-picker__select"
								ariaLabel="Reminder {index + 1}: which day"
								options={dayOptions(rule.days_before)}
								value={String(rule.days_before)}
								fitOptions
								onchange={(days) => setDays(index, rule, days)}
							/>
							<span class="reminder-picker__words">at</span>
							<div class="reminder-picker__time">
								<TimePickerField
									id="{id}-at-{index}"
									label="Reminder {index + 1}: time of day"
									hideLabel
									value={timeOf(rule.at)}
									onchange={(time) => setAt(index, rule, time)}
								/>
							</div>
						{/if}
					</div>
					<button
						type="button"
						class="reminder-picker__remove"
						aria-label="Remove reminder {index + 1}"
						onclick={() => remove(index)}>{@html xIcon}</button
					>
				</li>
			{/each}
		</ul>
		<div class="reminder-picker__actions">
			{#if rows.length < MAX_REMINDERS}
				<Button variant="tertiary" size="small" onclick={add}>
					<span class="reminder-picker__icon" aria-hidden="true">{@html plusIcon}</span>Add reminder
				</Button>
			{/if}
			{#if allowDefaults}
				<button type="button" class="reminder-picker__link" onclick={() => (value = null)}>
					Use my defaults
				</button>
			{/if}
		</div>
	{/if}
</fieldset>

<style lang="scss">
	.reminder-picker {
		// Rows lay out by the picker's own width, so a narrow dialog and a phone behave alike.
		container-type: inline-size;
		display: flex;
		flex-direction: column;
		gap: var(--space-small);
		min-width: 0;
		margin: 0;
		padding: 0;
		border: 0;

		&__label {
			margin-bottom: var(--space-small);
			padding: 0;
			color: var(--color-text);
			font-size: var(--typography--fontSize-base);
			font-weight: 600;
		}

		&__defaults {
			display: flex;
			align-items: center;
			gap: var(--space-small);
			padding: var(--space-slim) var(--space-base);
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-base);
			background: var(--color-surface--background);
		}

		&__bell,
		&__icon {
			display: inline-grid;
			flex: none;
			place-items: center;
			color: var(--color-text--secondary);

			:global(svg) {
				width: 18px;
				height: 18px;
			}
		}

		&__summary {
			flex: 1;
			min-width: 0;
			margin: 0;
			font-size: var(--typography--fontSize-small);
			overflow-wrap: anywhere;
		}

		&__muted {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__sr {
			position: absolute;
			width: 1px;
			height: 1px;
			overflow: hidden;
			clip-path: inset(50%);
			white-space: nowrap;
		}

		&__rows {
			display: flex;
			flex-direction: column;
			gap: var(--space-small);
			margin: 0;
			padding: 0;
			list-style: none;
		}

		&__row {
			display: flex;
			flex-wrap: wrap;
			align-items: center;
			gap: var(--space-small);
		}

		// Select fills its container by default; in a row each sizes to its words.
		&__row :global(.reminder-picker__select) {
			flex: none;
			width: auto;
			min-width: 112px;
		}

		&__when {
			display: flex;
			flex-wrap: wrap;
			align-items: center;
			gap: var(--space-small);
			min-width: 0;
		}

		&__amount {
			width: 64px;
			height: 40px;
			padding: 0 var(--space-small);
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-base);
			background: var(--color-surface);
			color: var(--color-text);
			font: inherit;
			text-align: center;

			&:focus-visible {
				border-color: var(--color-interactive);
				outline: none;
				box-shadow: var(--shadow-focus);
			}
		}

		&__words {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__time {
			width: 152px;
		}

		&__remove {
			display: inline-grid;
			width: 32px;
			height: 32px;
			margin-left: auto;
			place-items: center;
			border: 0;
			border-radius: var(--radius-base);
			background: transparent;
			color: var(--color-text--secondary);
			cursor: pointer;

			:global(svg) {
				width: 18px;
				height: 18px;
			}

			&:hover {
				background: var(--color-surface--hover);
				color: var(--color-text);
			}

			&:focus-visible {
				outline: none;
				box-shadow: var(--shadow-focus);
			}
		}

		&__actions {
			display: flex;
			flex-wrap: wrap;
			align-items: center;
			gap: var(--space-base);
		}

		&__link {
			padding: 0;
			border: 0;
			background: none;
			color: var(--color-interactive);
			font: inherit;
			font-size: var(--typography--fontSize-small);
			cursor: pointer;

			&:hover {
				text-decoration: underline;
			}

			&:focus-visible {
				border-radius: var(--radius-small, 4px);
				outline: none;
				box-shadow: var(--shadow-focus);
			}
		}
	}

	// Narrow: the channel and its remove button on one line, when it comes on the next.
	@container (max-width: 479px) {
		.reminder-picker__row {
			padding-bottom: var(--space-small);
			border-bottom: var(--border-base) solid var(--color-border);
		}

		.reminder-picker__row > :global(.reminder-picker__select) {
			flex: 1;
		}

		.reminder-picker__when {
			order: 3;
			flex-basis: 100%;
		}

		.reminder-picker__remove {
			order: 2;
		}
	}
</style>
