<script lang="ts">
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import Textarea from '$lib/components/ui/Textarea.svelte';
	import Checkbox from '$lib/components/ui/Checkbox.svelte';
	import DateTimePicker from '$lib/components/ui/DateTimePicker.svelte';
	import {
		calendarDateFromString,
		calendarDateToString,
		timeFromString,
		timeToString,
		emptyDateTimePickerValue,
		type DateTimePickerValue
	} from '$lib/components/ui/date-time';
	import type { EventItem } from '$lib/schedule/items';
	import type { ScheduleEventWrite } from '$lib/schedule/api';

	// The one form that creates and edits a Schedule-owned event. An event is deliberately small -- a title, an
	// optional description, and a single day that is either timed or anytime for the whole team -- so this is a
	// short modal, not a page. It shapes and validates the draft and hands it back; the page owns the write and
	// its feedback, exactly as the job create form does. It is used both from the empty-slot chooser (seeded
	// with the clicked slot) and from an existing event's Edit action (seeded with the event).

	let {
		open,
		event = null,
		seed = null,
		locale = 'en-US',
		saving = false,
		error = '',
		onSave,
		onClose
	}: {
		open: boolean;
		/** The event being edited, or null when creating a new one. */
		event?: EventItem | null;
		/** The slot a calendar gesture proposed for a new event: its day and time. Null means no slot (the
		 *  header create), and the form opens with today's picker empty for the person to choose a day. */
		seed?: { event_date: string; start_time: string | null; end_time: string | null; all_day: boolean } | null;
		locale?: string;
		saving?: boolean;
		error?: string;
		onSave: (payload: ScheduleEventWrite) => void;
		onClose: () => void;
	} = $props();

	const editing = $derived(event !== null);

	let title = $state('');
	let description = $state('');
	let anytime = $state(false);
	let when = $state<DateTimePickerValue>(emptyDateTimePickerValue());
	let fieldError = $state('');

	// Re-seed the form each time the dialog opens, never while it is open, so a background change never
	// overwrites what someone is typing. Editing fills from the event; creating fills from the slot the gesture
	// proposed, or leaves the day empty when there was no slot.
	let wasOpen = false;
	$effect(() => {
		if (open && !wasOpen) {
			const source = event
				? {
						event_date: event.visit_date,
						start_time: event.start_time,
						end_time: event.end_time,
						all_day: event.all_day
					}
				: seed;
			title = event?.title ?? '';
			description = event?.description ?? '';
			anytime = source?.all_day ?? false;
			when = {
				date: calendarDateFromString(source?.event_date ?? null),
				startTime: timeFromString(source?.start_time ?? null),
				endTime: timeFromString(source?.end_time ?? null)
			};
			fieldError = '';
		}
		wasOpen = open;
	});

	function buildPayload(): ScheduleEventWrite {
		const day = calendarDateToString(when.date) || '';
		const notes = description.trim() || null;
		if (anytime) {
			return { title: title.trim(), description: notes, event_date: day, start_time: null, end_time: null, all_day: true };
		}
		return {
			title: title.trim(),
			description: notes,
			event_date: day,
			start_time: timeToString(when.startTime) || null,
			end_time: timeToString(when.endTime) || null,
			all_day: false
		};
	}

	// The same rules the server and the database enforce, checked here so a bad combination is a message in the
	// form rather than an error bounced back from the write.
	function validate(): string | null {
		if (title.trim().length < 1) return 'Give the event a title.';
		if (!calendarDateToString(when.date)) return 'Pick a day for the event.';
		if (!anytime) {
			const start = timeToString(when.startTime);
			const end = timeToString(when.endTime);
			if (!start) return 'Give the event a start time, or tick “Anytime”.';
			if (end && end <= start) return 'The end time has to come after the start time.';
		}
		return null;
	}

	function save() {
		fieldError = '';
		const problem = validate();
		if (problem) {
			fieldError = problem;
			return;
		}
		onSave(buildPayload());
	}
</script>

<Dialog {open} title={editing ? 'Edit event' : 'New event'} {onClose}>
	<div class="event-form">
		{#if error}<p class="event-form__alert" role="alert">{error}</p>{/if}
		{#if fieldError}<p class="event-form__alert" role="alert">{fieldError}</p>{/if}

		<Input
			id="event-title"
			label="Event title"
			placeholder="What is this event?"
			required
			bind:value={title}
			maxlength={160}
		/>

		<DateTimePicker
			id="event-when"
			range
			showTime={!anytime}
			dateLabel="Day"
			timeLabel="Time"
			{locale}
			bind:value={when}
		/>
		<Checkbox
			id="event-anytime"
			label="Anytime"
			description="Block the day for the whole team without promising an hour."
			checked={anytime}
			onchange={(checked) => {
				anytime = checked;
				if (checked) when = { ...when, startTime: undefined, endTime: undefined };
			}}
		/>

		<Textarea
			id="event-description"
			label="Details (optional)"
			rows={3}
			maxlength={2000}
			bind:value={description}
		/>

		<div class="event-form__actions">
			<Button variant="tertiary" onclick={onClose} disabled={saving}>Cancel</Button>
			<Button onclick={save} loading={saving}>{editing ? 'Save event' : 'Create event'}</Button>
		</div>
	</div>
</Dialog>

<style lang="scss">
	.event-form {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);

		&__alert {
			margin: 0;
			padding: var(--space-small) var(--space-base);
			border-radius: var(--radius-base);
			background: var(--color-critical--surface);
			color: var(--color-critical--onSurface);
			font-size: var(--typography--fontSize-small);
		}

		&__actions {
			display: flex;
			justify-content: flex-end;
			gap: var(--space-small);
			margin-top: var(--space-small);
		}
	}
</style>
