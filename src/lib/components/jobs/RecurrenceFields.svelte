<script lang="ts">
	import { createQuery } from '@tanstack/svelte-query';
	import Select from '$lib/components/ui/Select.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import Checkbox from '$lib/components/ui/Checkbox.svelte';
	import SegmentedControl from '$lib/components/ui/SegmentedControl.svelte';
	import DateTimePicker from '$lib/components/ui/DateTimePicker.svelte';
	import {
		calendarDateFromString,
		calendarDateToString,
		emptyDateTimePickerValue,
		timeToString,
		type DateTimePickerValue
	} from '$lib/components/ui/date-time';
	import {
		previewJobRecurrence,
		jobRecurrencePreviewKey,
		type JobRecurrenceInput
	} from '$lib/jobs/api';

	// How a recurring job repeats, laid out the way Jobber's New Job page asks it: when the schedule starts,
	// how often it repeats, and when it stops — with a live count of the visits the rule makes sitting above
	// the end controls, so nobody saves a five-year contract by accident.
	//
	// The count is not worked out here. It comes from the server, which shares its date maths with the command
	// that writes the visits, so the number on screen is the number that gets written. Doing the arithmetic
	// twice — once in the browser to look fast, once in the database to be right — is how this feature usually
	// breaks.
	//
	// One deliberate difference from Jobber: their "Custom schedule…" opens a modal. Ours reveals the same
	// fields underneath the picker instead, which is the same decision with one less click.
	let {
		rule = $bindable(),
		asNeeded = $bindable(false),
		locale = 'en-US',
		disabled = false
	}: {
		rule: JobRecurrenceInput;
		asNeeded?: boolean;
		locale?: string;
		disabled?: boolean;
	} = $props();

	const WEEKDAY_LABELS = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];
	const WEEKDAY_NAMES = [
		'Sunday',
		'Monday',
		'Tuesday',
		'Wednesday',
		'Thursday',
		'Friday',
		'Saturday'
	];
	const ORDINAL_LABELS = ['1st', '2nd', '3rd', '4th', 'Last'];

	// The start date drives the whole control: it seeds the picker, names the presets, and anchors the count.
	let startValue = $state<DateTimePickerValue>(
		rule.start_date
			? {
					date: calendarDateFromString(rule.start_date),
					startTime: undefined,
					endTime: undefined
				}
			: emptyDateTimePickerValue()
	);
	let endValue = $state<DateTimePickerValue>({
		date: calendarDateFromString(rule.end_date),
		startTime: undefined,
		endTime: undefined
	});
	let anytime = $state(rule.all_day);
	/** Which row of the Repeats picker is showing: a preset, "as needed", or the custom fields. */
	let repeatChoice = $state('weekly');

	const startDate = $derived(calendarDateToString(startValue.date));
	const startWeekday = $derived(
		startDate ? new Date(`${startDate}T00:00:00`).getDay() : new Date().getDay()
	);
	const startDayOfMonth = $derived(startDate ? Number(startDate.slice(8, 10)) : 1);

	// Jobber's five one-line presets, named after the day the schedule starts on so the choice reads as a
	// sentence rather than a setting. Anything else is Custom.
	const repeatOptions = $derived([
		{ value: 'daily', label: 'Daily' },
		{ value: 'weekly', label: `Weekly on ${WEEKDAY_NAMES[startWeekday]}s` },
		{ value: 'biweekly', label: `Every 2 weeks on ${WEEKDAY_NAMES[startWeekday]}s` },
		{ value: 'monthly', label: `Monthly on the ${ordinalDay(startDayOfMonth)}` },
		{ value: 'as_needed', label: "As needed — we won't prompt you" },
		{ value: 'custom', label: 'Custom schedule…' }
	]);

	function ordinalDay(day: number) {
		if (day > 3 && day < 21) return `${day}th`;
		const tail = ['th', 'st', 'nd', 'rd'][day % 10] ?? 'th';
		return `${day}${tail}`;
	}

	// Picking a preset writes the whole rule at once, so the fields underneath and the count above can never
	// describe a different schedule from the one named in the picker.
	function chooseRepeat(choice: string) {
		repeatChoice = choice;
		asNeeded = choice === 'as_needed';
		if (asNeeded) return;

		if (choice === 'daily') {
			rule = { ...rule, frequency: 'daily', interval_count: 1, weekdays: [], monthly_mode: null };
		} else if (choice === 'weekly' || choice === 'biweekly') {
			rule = {
				...rule,
				frequency: 'weekly',
				interval_count: choice === 'biweekly' ? 2 : 1,
				weekdays: [startWeekday],
				monthly_mode: null
			};
		} else if (choice === 'monthly') {
			rule = {
				...rule,
				frequency: 'monthly',
				interval_count: 1,
				weekdays: [],
				monthly_mode: 'day_of_month',
				month_day: startDayOfMonth,
				ordinal_week: null,
				ordinal_weekday: null
			};
		}
		// "Custom" keeps whatever the rule already says and simply reveals the fields.
	}

	function toggleWeekday(day: number, checked: boolean) {
		const next = checked
			? [...rule.weekdays, day].sort((a, b) => a - b)
			: rule.weekdays.filter((entry) => entry !== day);
		rule = { ...rule, weekdays: next };
	}

	function chooseCustomUnit(unit: string) {
		if (unit === 'weekly') {
			rule = {
				...rule,
				frequency: 'weekly',
				weekdays: rule.weekdays.length > 0 ? rule.weekdays : [startWeekday],
				monthly_mode: null
			};
		} else if (unit === 'monthly') {
			rule = {
				...rule,
				frequency: 'monthly',
				weekdays: [],
				monthly_mode: rule.monthly_mode ?? 'day_of_month',
				month_day: rule.month_day ?? startDayOfMonth
			};
		} else {
			rule = {
				...rule,
				frequency: unit as JobRecurrenceInput['frequency'],
				weekdays: [],
				monthly_mode: null
			};
		}
	}

	function chooseMonthlyMode(mode: string) {
		rule =
			mode === 'day_of_week'
				? {
						...rule,
						monthly_mode: 'day_of_week',
						month_day: null,
						ordinal_week: rule.ordinal_week ?? Math.min(Math.ceil(startDayOfMonth / 7), 5),
						ordinal_weekday: rule.ordinal_weekday ?? startWeekday
					}
				: {
						...rule,
						monthly_mode: mode as 'day_of_month' | 'last_day',
						month_day: mode === 'day_of_month' ? (rule.month_day ?? startDayOfMonth) : null,
						ordinal_week: null,
						ordinal_weekday: null
					};
	}

	// The start date, its times and the anytime tick belong to the schedule, not to one visit, so they are
	// mirrored back onto the rule whenever the picker moves. The end date only applies in "Ends on" mode —
	// mirroring it unconditionally left a stale "" behind after switching to "Ends after", which fails the
	// server's date format check before its "only required for Ends on" rule ever gets a say.
	$effect(() => {
		const day = calendarDateToString(startValue.date);
		const start = anytime ? null : timeToString(startValue.startTime) || null;
		const end = anytime ? null : timeToString(startValue.endTime) || null;
		const chosenEnd = rule.end_mode === 'on' ? calendarDateToString(endValue.date) || null : null;
		if (
			rule.start_date === (day ?? '') &&
			rule.start_time === start &&
			rule.end_time === end &&
			rule.all_day === anytime &&
			rule.end_date === chosenEnd
		) {
			return;
		}
		rule = {
			...rule,
			start_date: day ?? '',
			start_time: start,
			end_time: end,
			all_day: anytime,
			end_date: chosenEnd
		};
	});

	// The count is asked for a beat after typing stops, so dragging the "ends after" stepper from 6 to 16 is
	// one question rather than ten. TanStack keeps every answer, so stepping back to 6 is instant.
	let settledRule = $state<JobRecurrenceInput | null>(null);
	$effect(() => {
		const snapshot = JSON.stringify(rule);
		const timer = setTimeout(() => {
			settledRule = JSON.parse(snapshot) as JobRecurrenceInput;
		}, 300);
		return () => clearTimeout(timer);
	});

	// Nothing is asked until the rule could actually produce a schedule; a half-filled form should not draw a
	// red error at someone who is still typing.
	const askable = $derived(
		!asNeeded &&
			settledRule !== null &&
			Boolean(settledRule.start_date) &&
			(settledRule.frequency !== 'weekly' || settledRule.weekdays.length > 0) &&
			(settledRule.frequency !== 'monthly' || Boolean(settledRule.monthly_mode)) &&
			(settledRule.end_mode === 'after'
				? Boolean(settledRule.duration_count)
				: Boolean(settledRule.end_date))
	);

	const previewQuery = createQuery(() => ({
		queryKey: jobRecurrencePreviewKey(settledRule ?? rule),
		queryFn: () => previewJobRecurrence(settledRule as JobRecurrenceInput),
		enabled: askable,
		staleTime: 5 * 60 * 1000
	}));

	const dateFormat = $derived(
		new Intl.DateTimeFormat(locale, { month: 'short', day: 'numeric', year: 'numeric' })
	);
	function readableDate(value: string | null) {
		return value ? dateFormat.format(new Date(`${value}T00:00:00`)) : '';
	}

	const preview = $derived(previewQuery.data ?? null);
	export function previewCount() {
		return asNeeded ? 0 : (preview?.visit_count ?? 0);
	}
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<div class="recurrence">
	<DateTimePicker
		id="job-schedule-start"
		range
		showTime={!anytime}
		dateLabel="Starts on"
		timeLabel="Time of day"
		{locale}
		{disabled}
		bind:value={startValue}
	/>

	<Checkbox
		id="job-schedule-anytime"
		label="Anytime"
		description="Tell the client the day without promising an hour."
		checked={anytime}
		{disabled}
		onchange={(checked) => (anytime = checked)}
	/>

	<Select
		id="job-schedule-repeats"
		label="Repeats"
		value={repeatChoice}
		options={repeatOptions}
		{disabled}
		onchange={chooseRepeat}
	/>

	{#if asNeeded}
		<p class="recurrence__note">
			No visits are created now. The job sits in your list as an ongoing agreement, and you add a
			visit each time the work comes up.
		</p>
	{:else}
		{#if repeatChoice === 'custom'}
			<div class="recurrence__custom">
				<div class="recurrence__interval">
					<span class="recurrence__inline-label">Every</span>
					<Input
						id="job-schedule-interval"
						label="Interval"
						type="number"
						min={1}
						max={52}
						{disabled}
						bind:value={rule.interval_count}
					/>
					<Select
						id="job-schedule-unit"
						ariaLabel="Repeat unit"
						value={rule.frequency}
						options={[
							{ value: 'daily', label: rule.interval_count > 1 ? 'days' : 'day' },
							{ value: 'weekly', label: rule.interval_count > 1 ? 'weeks' : 'week' },
							{ value: 'monthly', label: rule.interval_count > 1 ? 'months' : 'month' },
							{ value: 'yearly', label: rule.interval_count > 1 ? 'years' : 'year' }
						]}
						{disabled}
						onchange={chooseCustomUnit}
					/>
				</div>

				{#if rule.frequency === 'weekly'}
					<div class="recurrence__weekdays" role="group" aria-label="Days of the week">
						{#each WEEKDAY_LABELS as label, day (day)}
							<label
								class="recurrence__weekday"
								class:recurrence__weekday--on={rule.weekdays.includes(day)}
								title={WEEKDAY_NAMES[day]}
							>
								<input
									type="checkbox"
									checked={rule.weekdays.includes(day)}
									{disabled}
									onchange={(event) => toggleWeekday(day, event.currentTarget.checked)}
								/>
								<span aria-hidden="true">{label}</span>
								<span class="recurrence__weekday-name">{WEEKDAY_NAMES[day]}</span>
							</label>
						{/each}
					</div>
				{/if}

				{#if rule.frequency === 'monthly'}
					<SegmentedControl
						label="On"
						value={rule.monthly_mode ?? 'day_of_month'}
						options={[
							{ value: 'day_of_month', label: 'Day of month' },
							{ value: 'last_day', label: 'Last day' },
							{ value: 'day_of_week', label: 'Day of week' }
						]}
						{disabled}
						onchange={chooseMonthlyMode}
					/>

					{#if rule.monthly_mode === 'day_of_month'}
						<Input
							id="job-schedule-month-day"
							label="Day of the month"
							type="number"
							min={1}
							max={31}
							{disabled}
							bind:value={rule.month_day}
						/>
						<p class="recurrence__note">
							A month without that day is skipped. Pick “Last day” to cover every month.
						</p>
					{/if}

					{#if rule.monthly_mode === 'day_of_week'}
						<div class="recurrence__ordinal">
							<Select
								id="job-schedule-ordinal-week"
								ariaLabel="Which week"
								value={String(rule.ordinal_week ?? 1)}
								options={ORDINAL_LABELS.map((label, index) => ({
									value: String(index + 1),
									label
								}))}
								{disabled}
								onchange={(value) => (rule = { ...rule, ordinal_week: Number(value) })}
							/>
							<Select
								id="job-schedule-ordinal-weekday"
								ariaLabel="Which weekday"
								value={String(rule.ordinal_weekday ?? startWeekday)}
								options={WEEKDAY_NAMES.map((name, index) => ({
									value: String(index),
									label: name
								}))}
								{disabled}
								onchange={(value) => (rule = { ...rule, ordinal_weekday: Number(value) })}
							/>
						</div>
					{/if}
				{/if}
			</div>
		{/if}

		<div class="recurrence__count" aria-live="polite">
			{#if previewQuery.isError}
				<span class="recurrence__count-note">
					{(previewQuery.error as Error).message}
				</span>
			{:else if !askable || previewQuery.isPending}
				<span class="recurrence__count-note"
					>Finish the schedule to see how many visits it makes.</span
				>
			{:else if preview?.over_limit}
				<span class="recurrence__count-note recurrence__count-note--warn">
					That schedule makes {preview.visit_count} visits. The most we create at once is {preview.limit}.
					Try a nearer end date.
				</span>
			{:else if preview}
				<span class="recurrence__count-number">{preview.visit_count}</span>
				<span class="recurrence__count-word">
					{preview.visit_count === 1 ? 'visit' : 'visits'}
				</span>
				{#if preview.first_date}
					<span class="recurrence__count-range">
						{readableDate(preview.first_date)} – {readableDate(preview.last_date)}
					</span>
				{/if}
			{/if}
		</div>

		<SegmentedControl
			label="Ends"
			value={rule.end_mode}
			options={[
				{ value: 'after', label: 'Ends after' },
				{ value: 'on', label: 'Ends on' }
			]}
			{disabled}
			onchange={(value) => (rule = { ...rule, end_mode: value as JobRecurrenceInput['end_mode'] })}
		/>

		{#if rule.end_mode === 'after'}
			<div class="recurrence__interval">
				<Input
					id="job-schedule-duration"
					label="Ends after"
					type="number"
					min={1}
					max={520}
					{disabled}
					bind:value={rule.duration_count}
				/>
				<Select
					id="job-schedule-duration-unit"
					ariaLabel="Length"
					value={rule.duration_unit ?? 'month'}
					options={[
						{ value: 'day', label: rule.duration_count === 1 ? 'day' : 'days' },
						{ value: 'week', label: rule.duration_count === 1 ? 'week' : 'weeks' },
						{ value: 'month', label: rule.duration_count === 1 ? 'month' : 'months' },
						{ value: 'year', label: rule.duration_count === 1 ? 'year' : 'years' }
					]}
					{disabled}
					onchange={(value) =>
						(rule = { ...rule, duration_unit: value as JobRecurrenceInput['duration_unit'] })}
				/>
			</div>
		{:else}
			<DateTimePicker
				id="job-schedule-end"
				dateLabel="Ends on"
				{locale}
				{disabled}
				bind:value={endValue}
			/>
		{/if}
	{/if}
</div>

<style lang="scss">
	.recurrence {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);

		&__note {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			line-height: 1.45;
		}

		&__custom {
			display: flex;
			flex-direction: column;
			gap: var(--space-base);
			padding: var(--space-base);
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-base);
			background: var(--color-surface--background);
		}

		&__interval,
		&__ordinal {
			display: grid;
			align-items: center;
			gap: var(--space-small);
			grid-template-columns: minmax(0, 1fr) minmax(0, 1fr);
		}

		&__interval {
			grid-template-columns: auto minmax(0, 1fr) minmax(0, 1fr);
		}

		&__inline-label {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			font-weight: 600;
		}

		&__weekdays {
			display: flex;
			flex-wrap: wrap;
			gap: var(--space-smaller);
		}

		// A row of day toggles reads faster than seven stacked checkboxes, so the native input stays for the
		// keyboard and the screen reader while the label draws the circle.
		&__weekday {
			display: inline-flex;
			position: relative;
			align-items: center;
			justify-content: center;
			width: var(--space-larger);
			height: var(--space-larger);
			border: var(--border-base) solid var(--color-border);
			border-radius: 50%;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			font-weight: 600;
			cursor: pointer;

			&:hover {
				border-color: var(--color-interactive);
				color: var(--color-interactive);
			}

			&:focus-within {
				outline: var(--border-thick) solid var(--color-interactive);
				outline-offset: 2px;
			}

			&--on {
				border-color: var(--color-interactive);
				color: var(--color-surface);
				background: var(--color-interactive);
			}

			input {
				position: absolute;
				width: 1px;
				height: 1px;
				margin: -1px;
				padding: 0;
				overflow: hidden;
				border: 0;
				clip-path: inset(50%);
				white-space: nowrap;
			}
		}

		&__weekday-name {
			position: absolute;
			width: 1px;
			height: 1px;
			margin: -1px;
			overflow: hidden;
			clip-path: inset(50%);
			white-space: nowrap;
		}

		// The count sits directly above the end controls, exactly where the decision is made.
		&__count {
			display: flex;
			flex-wrap: wrap;
			align-items: baseline;
			gap: var(--space-smaller);
			min-height: var(--space-large);
		}

		&__count-number {
			color: var(--color-heading);
			font-size: var(--typography--fontSize-largest);
			font-weight: 700;
			line-height: 1;
		}

		&__count-word,
		&__count-range {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__count-range::before {
			margin-right: var(--space-smaller);
			content: '·';
		}

		&__count-note {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);

			&--warn {
				color: var(--color-critical);
				font-weight: 600;
			}
		}

		@media (max-width: 767px) {
			&__interval,
			&__ordinal {
				grid-template-columns: 1fr;
			}
		}
	}
</style>
