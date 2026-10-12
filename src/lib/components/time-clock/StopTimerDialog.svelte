<script lang="ts">
	import { useQueryClient } from '@tanstack/svelte-query';
	import { Time, type CalendarDate } from '@internationalized/date';
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import CalendarPicker from '$lib/components/ui/CalendarPicker.svelte';
	import SegmentedControl from '$lib/components/ui/SegmentedControl.svelte';
	import TimePickerField from '$lib/components/ui/TimePickerField.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import { calendarDateFromString, calendarDateToString } from '$lib/components/ui/date-time';
	import { clockTime } from '$lib/time-clock/timesheets';
	import { formatCalendarDay } from '$lib/schedule/labels';
	import {
		businessClock,
		refreshAfterCorrection,
		stopTimerAt,
		type CorrectionError,
		type StopTarget
	} from '$lib/time-clock/corrections';

	// Clock someone out, or stop a forgotten timer at the time work really ended (plan § Forgotten timers). A
	// timer is never stopped by itself, because that would invent an end time nobody worked; someone who can
	// correct the hours says when. Over 24 hours only a chosen end is possible. Either way the day is over:
	// nothing starts again afterwards.
	let {
		open,
		target,
		timezone,
		onClose
	}: {
		open: boolean;
		target: StopTarget | null;
		timezone: string;
		onClose: () => void;
	} = $props();

	const toast = getToastManager();
	const queryClient = useQueryClient();

	let when = $state<'now' | 'chosen'>('now');
	let day = $state<CalendarDate | undefined>();
	let time = $state<Time | undefined>();
	let saving = $state(false);
	let error = $state('');

	let wasOpen = false;
	$effect(() => {
		if (open && !wasOpen && target) {
			// A forgotten timer most likely ended the day it started; start the choice there.
			const begun = businessClock(target.startedAt, timezone);
			when = target.overADay ? 'chosen' : 'now';
			day = calendarDateFromString(begun.day);
			time = new Time(17, 0);
			saving = false;
			error = '';
		}
		wasOpen = open;
	});

	const action = $derived(target?.clockedIn ? 'Clock out' : 'Stop timer');
	const started = $derived(
		target
			? `${formatCalendarDay(businessClock(target.startedAt, timezone).day, {
					weekday: 'short',
					month: 'short',
					day: 'numeric'
				})} at ${clockTime(target.startedAt, timezone)}`
			: ''
	);

	async function stop() {
		if (!target || saving) return;
		error = '';
		let end: { day: string; time: string } | null = null;
		if (when === 'chosen') {
			const dayText = calendarDateToString(day);
			if (!dayText || !time) {
				error = 'Choose the day and the time work ended.';
				return;
			}
			end = {
				day: dayText,
				time: `${String(time.hour).padStart(2, '0')}:${String(time.minute).padStart(2, '0')}`
			};
		}

		saving = true;
		try {
			const result = await stopTimerAt(target.userId, end);
			await refreshAfterCorrection(queryClient);
			if (result.too_short) toast.info('Stopped. Under a minute, so no hours were recorded.');
			else if (!result.stopped) toast.info('That timer had already stopped.');
			else toast.success(target.clockedIn ? 'Clocked out' : 'Timer stopped');
			onClose();
		} catch (cause) {
			error = (cause as CorrectionError).message;
		} finally {
			saving = false;
		}
	}
</script>

<Dialog
	open={open && Boolean(target)}
	title={action}
	size="small"
	onClose={() => !saving && onClose()}
>
	{#if target}
		<form
			class="stop-timer"
			onsubmit={(event) => {
				event.preventDefault();
				void stop();
			}}
		>
			{#if error}<p class="stop-timer__alert" role="alert">{error}</p>{/if}

			<p class="stop-timer__summary">
				<strong>{target.name}</strong> has been on <strong>{target.what}</strong> since {started}.
			</p>

			{#if target.overADay}
				<p class="stop-timer__warning">
					This timer has run for more than 24 hours, so it cannot stop as it is. Choose when work
					really ended.
				</p>
			{:else}
				<SegmentedControl
					label="Ended"
					name="stop-when"
					fullWidth
					options={[
						{ value: 'now', label: 'Now' },
						{ value: 'chosen', label: 'At a set time' }
					]}
					value={when}
					onchange={(next) => (when = next as 'now' | 'chosen')}
				/>
			{/if}

			{#if when === 'chosen'}
				<div class="stop-timer__when">
					<CalendarPicker id="stop-day" label="Day work ended" bind:value={day} />
					<TimePickerField id="stop-time" label="Time work ended" bind:value={time} />
				</div>
			{/if}

			<p class="stop-timer__note">
				{target.clockedIn
					? 'Nothing keeps running afterwards: the working day is over.'
					: 'Nothing keeps running afterwards.'}
				A stop under a minute records nothing.
			</p>

			<div class="stop-timer__actions">
				<Button variant="secondary" variation="subtle" disabled={saving} onclick={onClose}>
					Cancel
				</Button>
				<Button variant="primary" type="submit" loading={saving}>{action}</Button>
			</div>
		</form>
	{/if}
</Dialog>

<style lang="scss">
	.stop-timer {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);

		&__alert,
		&__warning {
			margin: 0;
			padding: var(--space-small) var(--space-base);
			border-radius: var(--radius-base);
			font-size: var(--typography--fontSize-small);
		}

		&__alert {
			background: var(--color-critical--surface);
			color: var(--color-critical--onSurface);
		}

		&__warning {
			background: var(--color-warning--surface);
			color: var(--color-warning--onSurface);
		}

		&__summary {
			margin: 0;
			color: var(--color-text);

			strong {
				color: var(--color-heading);
			}
		}

		&__when {
			display: grid;
			grid-template-columns: 1fr 1fr;
			gap: var(--space-small);
		}

		&__note {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__actions {
			display: flex;
			justify-content: flex-end;
			gap: var(--space-small);
		}
	}

	@media (max-width: 479px) {
		.stop-timer__when {
			grid-template-columns: 1fr;
		}
	}
</style>
