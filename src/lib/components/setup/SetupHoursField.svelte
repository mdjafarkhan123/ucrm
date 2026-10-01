<script lang="ts">
	import { untrack } from 'svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import WeeklyHoursEditor from '$lib/components/settings/WeeklyHoursEditor.svelte';
	import { timeFromString, timeToString } from '$lib/components/ui/date-time';
	import { closedWeek, suggestedWeek, type DayState } from '$lib/settings/weekly-hours';
	import { parseSetupHours, type SetupHours, type SetupHoursDay } from '$lib/setup/hours';

	// The normal week for the setup wizard. It reads and writes the answer as JSON text, so the page saves
	// it exactly like any other answer; `onchange` fires on every edit.
	let {
		id,
		value = $bindable(''),
		onchange
	}: {
		id: string;
		value?: string;
		onchange: () => void;
	} = $props();

	function toDayState(day: SetupHoursDay): DayState {
		return {
			isOpen: day.open,
			is24h: day.all_day,
			periods: day.periods.map(([opens, closes]) => ({
				start: timeFromString(opens),
				end: timeFromString(closes)
			}))
		};
	}

	// A period still missing a time is left out, and a day with none left counts as closed — the same way
	// the Business Hours screen saves a week.
	function fromDayState(day: DayState): SetupHoursDay {
		if (!day.isOpen) return { open: false, all_day: false, periods: [] };
		if (day.is24h) return { open: true, all_day: true, periods: [] };
		const periods = day.periods
			.filter((period) => period.start && period.end)
			.map((period): [string, string] => [timeToString(period.start), timeToString(period.end)])
			.filter(([opens, closes]) => opens !== closes);
		return periods.length > 0
			? { open: true, all_day: false, periods }
			: { open: false, all_day: false, periods: [] };
	}

	const initial = untrack(() => (value ? parseSetupHours(value).value : null));
	let mode = $state<SetupHours['mode'] | null>(initial?.mode ?? null);
	let days = $state<DayState[]>(
		initial?.mode === 'weekly' ? initial.days.map(toDayState) : closedWeek()
	);

	function emit() {
		if (!mode) return;
		const answer: SetupHours =
			mode === 'weekly' ? { mode, days: days.map(fromDayState) } : { mode: 'appointment_only' };
		value = JSON.stringify(answer);
		onchange();
	}

	function startWeekly() {
		mode = 'weekly';
		days = suggestedWeek();
		emit();
	}
	function startAlwaysOpen() {
		mode = 'weekly';
		days = closedWeek().map(() => ({ isOpen: true, is24h: true, periods: [] }));
		emit();
	}
	function startAppointmentOnly() {
		mode = 'appointment_only';
		emit();
	}
</script>

<div class="setup-hours">
	{#if mode === null}
		<p class="setup-hours__intro">
			Pick the closest starting point — you can change any day afterwards.
		</p>
		<div class="setup-hours__starters">
			<Button variant="secondary" onclick={startWeekly}>Monday–Friday, 8am–5pm</Button>
			<Button variant="secondary" onclick={startAlwaysOpen}>Open 24 hours, every day</Button>
			<Button variant="secondary" onclick={startAppointmentOnly}>By appointment only</Button>
		</div>
	{:else if mode === 'appointment_only'}
		<p class="setup-hours__intro">
			<strong>By appointment only.</strong> No fixed weekly hours — every visit is arranged individually.
		</p>
		<div class="setup-hours__starters">
			<Button variant="tertiary" onclick={startWeekly}>Set weekly hours instead</Button>
		</div>
	{:else}
		<WeeklyHoursEditor bind:days idPrefix={id} singleColumn onchange={emit} />
		<div class="setup-hours__starters">
			<Button variant="tertiary" onclick={startAppointmentOnly}
				>I work by appointment only instead</Button
			>
		</div>
	{/if}
</div>

<style lang="scss">
	.setup-hours {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);
		min-width: 0;

		&__intro {
			color: var(--color-text--secondary);
		}

		&__starters {
			display: flex;
			flex-wrap: wrap;
			gap: var(--space-small);
		}
	}
</style>
