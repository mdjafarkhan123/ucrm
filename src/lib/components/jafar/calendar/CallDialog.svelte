<script lang="ts">
	import { untrack } from 'svelte';
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import { Time } from '@internationalized/date';
	import { resolve } from '$app/paths';
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import Textarea from '$lib/components/ui/Textarea.svelte';
	import DateTimePicker from '$lib/components/ui/DateTimePicker.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import {
		calendarDateFromString,
		calendarDateToString,
		timeToMinutes,
		type DateTimePickerValue
	} from '$lib/components/ui/date-time';
	import BusinessPicker from './BusinessPicker.svelte';
	import ReminderPicker from './ReminderPicker.svelte';
	import { sendLeadWrite, type WriteResult } from '$lib/jafar/lead-page-api';
	import {
		CALL_OUTCOME_LABELS,
		browserTimeZone,
		calendarEntryKey,
		fetchCalendarEntry,
		refreshCalendar,
		zonedInstant,
		zonedPlace,
		type ReminderDefaults,
		type ReminderRule
	} from '$lib/jafar/calendar';

	// Jafar business management C2: book a sales call, or open one to change its time, words or reminders. A new
	// call becomes the business's next action. Moving a call moves its reminders: the database drops the ones for
	// the old time in the same save. Closing a call (Held, They didn't show, Cancelled) is CallOutcomeDialog's.
	let {
		entryId = null,
		seed = null,
		business = null,
		zone,
		defaults,
		onClose,
		onOutcome
	}: {
		/** The call being opened, or null to book a new one. */
		entryId?: string | null;
		/** Where a new call starts: the slot clicked on the calendar. */
		seed?: { day: string; start: number; end: number } | null;
		/** The business, when booking from its own page; otherwise the dialog asks. */
		business?: { id: string; name: string } | null;
		/** The calendar's time zone (Jafar's, or the browser's until he saves one). */
		zone: string;
		defaults: ReminderDefaults;
		onClose: () => void;
		/** "How did it go?" / Cancel call on an open call. */
		onOutcome?: (entryId: string) => void;
	} = $props();

	const queryClient = useQueryClient();
	const toast = getToastManager();

	const entryQuery = createQuery(() => ({
		queryKey: calendarEntryKey(entryId ?? ''),
		queryFn: () => fetchCalendarEntry(entryId!),
		enabled: entryId !== null
	}));
	const entry = $derived(entryQuery.data);

	let relationshipId = $state(untrack(() => business?.id ?? ''));
	let businessName = $state(untrack(() => business?.name ?? ''));
	let title = $state('');
	let notes = $state('');
	let when = $state<DateTimePickerValue>({
		date: undefined,
		startTime: undefined,
		endTime: undefined
	});
	let reminders = $state<ReminderRule[] | null>(null);
	let fieldErrors = $state<Record<string, string>>({});
	let formError = $state('');
	let saving = $state(false);
	let loaded = $state(untrack(() => entryId === null));
	/** What was saved, to send only what changed. */
	let original = { starts_at: '', ends_at: '', words: '' };

	function timeOf(minutes: number) {
		return new Time(Math.floor(minutes / 60) % 24, minutes % 60);
	}

	function wordsKey() {
		return JSON.stringify([title.trim(), notes.trim(), reminders]);
	}

	// A new call starts at the clicked slot, or the next whole hour today, for 30 minutes.
	if (untrack(() => entryId === null)) {
		const start = untrack(() => seed);
		const place = start ?? nextHour();
		when = {
			date: calendarDateFromString(place.day),
			startTime: timeOf(place.start),
			endTime: timeOf(Math.min(place.end, 23 * 60 + 59))
		};
	}

	function nextHour() {
		const now = zonedPlace(
			new Date().toISOString(),
			untrack(() => zone)
		);
		const start = Math.min(Math.ceil((now.minutes + 1) / 60) * 60, 23 * 60);
		return { day: now.day, start, end: start + 30 };
	}

	// An opened call fills the form once, so a background refresh never overwrites what is being typed.
	$effect(() => {
		const detail = entryQuery.data;
		if (!detail || untrack(() => loaded)) return;
		untrack(() => {
			const start = zonedPlace(detail.starts_at, zone);
			const end = zonedPlace(detail.ends_at, zone);
			relationshipId = detail.relationship_id ?? '';
			businessName = detail.business_name ?? '';
			title = detail.title ?? '';
			notes = detail.notes ?? '';
			reminders = detail.reminders;
			when = {
				date: calendarDateFromString(start.day),
				startTime: timeOf(start.minutes),
				endTime: timeOf(end.day === start.day ? end.minutes : 23 * 60 + 59)
			};
			original = { starts_at: detail.starts_at, ends_at: detail.ends_at, words: wordsKey() };
			loaded = true;
		});
	});

	const closed = $derived(entry !== undefined && entry.status !== 'scheduled');
	const passed = $derived(entry !== undefined && Date.parse(entry.ends_at) <= Date.now());

	function span(): { starts_at: string; ends_at: string } | null {
		const day = calendarDateToString(when.date);
		const start = timeToMinutes(when.startTime);
		const end = timeToMinutes(when.endTime);
		if (!day || start === undefined || end === undefined) return null;
		return { starts_at: zonedInstant(day, start, zone), ends_at: zonedInstant(day, end, zone) };
	}

	function localErrors() {
		const errors: Record<string, string> = {};
		if (!relationshipId) errors.relationship_id = 'Choose the business.';
		if (!when.date) errors.when = 'Choose the day.';
		else if (!when.startTime || !when.endTime) errors.when = 'Choose when it starts and ends.';
		else if ((timeToMinutes(when.endTime) ?? 0) <= (timeToMinutes(when.startTime) ?? 0))
			errors.when = 'End after it starts.';
		return errors;
	}

	async function save(event: SubmitEvent) {
		event.preventDefault();
		if (saving || closed) return;
		formError = '';
		fieldErrors = localErrors();
		const times = span();
		if (Object.keys(fieldErrors).length || !times) return;

		saving = true;
		const results: WriteResult[] = [];
		if (entryId === null) {
			results.push(
				await sendLeadWrite('/api/jafar/calendar/entries', 'POST', {
					kind: 'call',
					relationship_id: relationshipId,
					...times,
					title: title.trim() || null,
					notes: notes.trim() || null,
					reminders,
					time_zone: browserTimeZone()
				})
			);
		} else {
			const path = `/api/jafar/calendar/entries/${encodeURIComponent(entryId)}`;
			if (times.starts_at !== original.starts_at || times.ends_at !== original.ends_at)
				results.push(await sendLeadWrite(path, 'PATCH', { action: 'move', ...times }));
			if (results.every((result) => result.ok) && wordsKey() !== original.words)
				results.push(
					await sendLeadWrite(path, 'PATCH', {
						action: 'edit',
						title: title.trim() || null,
						notes: notes.trim() || null,
						reminders
					})
				);
		}
		const failed = results.find((result) => !result.ok);
		if (failed && !failed.ok) {
			saving = false;
			fieldErrors = {
				...failed.fieldErrors,
				...(failed.fieldErrors.starts_at || failed.fieldErrors.ends_at
					? { when: failed.fieldErrors.ends_at ?? failed.fieldErrors.starts_at }
					: {})
			};
			formError = failed.error;
			return;
		}
		await refreshCalendar(queryClient);
		saving = false;
		toast.success(entryId === null ? 'Call booked' : results.length ? 'Call saved' : 'No changes');
		onClose();
	}

	const placeholderTitle = $derived(businessName ? `Call with ${businessName}` : 'Call');
	const dialogTitle = $derived(
		entryId === null ? 'Book a call' : closed ? 'Call' : passed ? 'Call (ended)' : 'Call'
	);
</script>

<Dialog
	open={true}
	title={dialogTitle}
	initialFocusId={business || entryId ? 'call-title' : 'call-business'}
	{onClose}
>
	{#if !loaded}
		{#if entryQuery.isError}
			<p class="call-form__error" role="alert">{entryQuery.error.message}</p>
		{:else}
			<LoadingSkeleton variant="card" rows={3} label="Loading the call" />
		{/if}
	{:else}
		<form class="call-form" onsubmit={save} novalidate>
			{#if entry && closed}
				<p class="call-form__status">
					{CALL_OUTCOME_LABELS[entry.status as keyof typeof CALL_OUTCOME_LABELS]}
				</p>
			{:else if entry && passed && onOutcome}
				<div class="call-form__ask">
					<p>This call has ended. How did it go?</p>
					<Button size="small" onclick={() => onOutcome(entryId!)}>Record outcome</Button>
				</div>
			{/if}

			{#if business || entryId}
				<p class="call-form__business">
					With
					<a href={resolve('/jafar/(protected)/leads/[id]', { id: relationshipId })}
						>{businessName}</a
					>
				</p>
			{:else}
				<BusinessPicker
					id="call-business"
					required
					bind:value={relationshipId}
					invalid={Boolean(fieldErrors.relationship_id)}
					errorMessage={fieldErrors.relationship_id ?? ''}
					onSelect={(picked) => (businessName = picked?.business_name ?? '')}
				/>
			{/if}

			<Input
				id="call-title"
				label="Title (optional)"
				placeholder={placeholderTitle}
				maxlength={200}
				autocomplete="off"
				disabled={closed}
				bind:value={title}
			/>

			<DateTimePicker
				id="call-when"
				range
				dateLabel="Day"
				timeLabel="Time"
				disabled={closed}
				invalid={Boolean(fieldErrors.when)}
				errorMessage={fieldErrors.when ?? ''}
				bind:value={when}
			/>

			<ReminderPicker id="call-reminders" timed defaults={defaults.call} bind:value={reminders} />

			<Textarea
				id="call-notes"
				label="Notes (optional)"
				rows={3}
				maxlength={4000}
				disabled={closed}
				bind:value={notes}
			/>

			{#if formError}<p class="call-form__error" role="alert">{formError}</p>{/if}

			<div class="call-form__actions">
				{#if entryId && !closed && onOutcome}
					<Button variant="tertiary" onclick={() => onOutcome(entryId!)}>
						{passed ? 'Record outcome' : 'Cancel call'}
					</Button>
				{/if}
				<span class="call-form__spacer"></span>
				<Button variant="secondary" onclick={onClose} disabled={saving}>
					{closed ? 'Close' : 'Cancel'}
				</Button>
				{#if !closed}
					<Button type="submit" loading={saving}>{entryId ? 'Save' : 'Book call'}</Button>
				{/if}
			</div>
		</form>
	{/if}
</Dialog>

<style lang="scss">
	.call-form {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);

		&__business {
			margin: 0;
			color: var(--color-text--secondary);

			a {
				color: var(--color-interactive);
				font-weight: 600;
				text-decoration: none;

				&:hover {
					text-decoration: underline;
				}
			}
		}

		&__status {
			align-self: flex-start;
			margin: 0;
			padding: var(--space-smaller) var(--space-slim);
			border-radius: var(--radius-circle);
			background: var(--color-surface--background);
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			font-weight: 600;
		}

		&__ask {
			display: flex;
			flex-wrap: wrap;
			align-items: center;
			justify-content: space-between;
			gap: var(--space-small);
			padding: var(--space-slim) var(--space-base);
			border-radius: var(--radius-base);
			background: var(--color-warning--surface);
			color: var(--color-warning--onSurface);

			p {
				margin: 0;
			}
		}

		&__error {
			margin: 0;
			color: var(--color-critical);
			font-size: var(--typography--fontSize-small);
		}

		&__actions {
			display: flex;
			flex-wrap: wrap;
			align-items: center;
			gap: var(--space-small);
		}

		&__spacer {
			flex: 1;
		}
	}
</style>
