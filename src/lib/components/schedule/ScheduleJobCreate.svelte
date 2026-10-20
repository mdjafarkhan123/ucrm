<script lang="ts">
	import IconTile from '$lib/components/ui/IconTile.svelte';
	import type { Snippet } from 'svelte';
	import { createQuery } from '@tanstack/svelte-query';
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import Textarea from '$lib/components/ui/Textarea.svelte';
	import Checkbox from '$lib/components/ui/Checkbox.svelte';
	import DateTimePicker from '$lib/components/ui/DateTimePicker.svelte';
	import SegmentedControl from '$lib/components/ui/SegmentedControl.svelte';
	import PickedClient from '$lib/components/work/PickedClient.svelte';
	import checkIcon from '@tabler/icons/outline/check.svg?raw';
	import ClientPicker from '$lib/components/work/ClientPicker.svelte';
	import TeamPicker from '$lib/components/team/TeamPicker.svelte';
	import {
		calendarDateFromString,
		calendarDateToString,
		timeFromString,
		timeToString,
		emptyDateTimePickerValue,
		type DateTimePickerValue
	} from '$lib/components/ui/date-time';
	import { fetchClient, clientDetailKey, type ClientListItem } from '$lib/clients/api';
	import type { JobCreateSeed, JobFirstVisitSeed } from '$lib/jobs/createDraft';
	import type { AssessmentCreateSeed } from '$lib/requests/assessmentSeed';
	import type { NewVisitDraft } from '$lib/schedule/drag';
	import hammerIcon from '@tabler/icons/outline/hammer.svg?raw';
	import clipboardListIcon from '@tabler/icons/outline/inbox.svg?raw';
	import calendarEventIcon from '@tabler/icons/outline/calendar-event.svg?raw';
	import calendarTimeIcon from '@tabler/icons/outline/calendar-time.svg?raw';
	import clockIcon from '@tabler/icons/outline/clock.svg?raw';
	import alertCircleIcon from '@tabler/icons/outline/alert-circle.svg?raw';
	import arrowRightIcon from '@tabler/icons/outline/arrow-right.svg?raw';
	import adjustmentsIcon from '@tabler/icons/outline/adjustments-horizontal.svg?raw';

	// Booking work from empty calendar space, the way Jobber starts one in place. A Job/Request switch at the
	// top follows Jobber's empty-slot work-type chooser: Job is the default and its light form -- seeded with
	// the day, time and any team the gesture proposed -- makes the common "client + one visit" job a quick
	// fill-in without leaving the calendar. Picking Request instead carries the same slot to the full New
	// Request page, where its on-site assessment opens pre-booked; the Request and its assessment stay owned
	// by Requests. Full job creation still lives in Jobs -- More Options hands this exact draft to the New Job
	// page for line items and the rest. Save writes through the Jobs-owned create command; this form only
	// shapes the draft and hands it back, so the page owns the write and its feedback.

	let {
		open,
		draft = null,
		locale = 'en-US',
		saving = false,
		error = '',
		onCreate,
		onMoreOptions,
		onCreateRequest,
		onCreateEvent,
		onClose,
		notice
	}: {
		open: boolean;
		/** The day and time the calendar gesture proposed. Null means no slot -- the header action -- and the
		 *  form opens on Schedule later. */
		draft?: NewVisitDraft | null;
		locale?: string;
		saving?: boolean;
		error?: string;
		/** Save: the Jobs-owned create command runs on the page with this draft. */
		onCreate: (seed: JobCreateSeed) => void;
		/** More Options: the same draft is carried to the full New Job page. */
		onMoreOptions: (seed: JobCreateSeed) => void;
		/** Request: the same slot is carried to the Request-owned New Request page. */
		onCreateRequest: (seed: AssessmentCreateSeed) => void;
		/** Event: the same slot opens the Schedule-owned event dialog. Null slot means no date yet. */
		onCreateEvent: (
			seed: {
				event_date: string;
				start_time: string | null;
				end_time: string | null;
				all_day: boolean;
			} | null
		) => void;
		onClose: () => void;
		/** Client reminders Part 4: the "Notify customer" box, shown above Save job. */
		notice?: Snippet;
	} = $props();

	// Which kind of work this slot becomes. Job is the default, exactly as Jobber's chooser opens; Request and
	// Event both hand off rather than writing anything here -- Request to its own page, Event to Schedule's own
	// dialog.
	type CreateType = 'job' | 'request' | 'event';
	let createType = $state<CreateType>('job');
	// Each kind wears its own colour, the same ones the rest of the app gives a job, a request and an event.
	const typeOptions = [
		{ value: 'job', label: 'Job', icon: hammerIcon, iconColor: 'var(--color-job)' },
		{
			value: 'request',
			label: 'Request',
			icon: clipboardListIcon,
			iconColor: 'var(--color-request)'
		},
		{
			value: 'event',
			label: 'Event',
			icon: calendarEventIcon,
			iconColor: 'var(--color-event--onSurface)'
		}
	];
	const dialogLook = $derived(
		createType === 'request'
			? { icon: clipboardListIcon, tone: 'request' as const }
			: createType === 'event'
				? { icon: calendarEventIcon, tone: 'event' as const }
				: { icon: hammerIcon, tone: 'job' as const }
	);

	let title = $state('');
	let clientId = $state('');
	let selectedClient = $state<ClientListItem | null>(null);
	let propertyId = $state('');
	let choosingProperty = $state(false);
	let changingClient = $state(false);
	let scheduleLater = $state(false);
	let anytime = $state(false);
	let when = $state<DateTimePickerValue>(emptyDateTimePickerValue());
	let workNotes = $state('');
	let assigneeIds = $state<string[]>([]);
	let fieldError = $state('');

	// Re-seed the form each time the dialog opens, never while it is open, so a background refetch or a
	// re-render never overwrites what someone is typing.
	let wasOpen = false;
	$effect(() => {
		if (open && !wasOpen) {
			createType = 'job';
			title = '';
			clientId = '';
			selectedClient = null;
			changingClient = false;
			propertyId = '';
			choosingProperty = false;
			scheduleLater = draft === null;
			anytime = draft !== null && draft.all_day;
			when = {
				date: calendarDateFromString(draft?.visit_date ?? null),
				startTime: timeFromString(draft?.start_time ?? null),
				endTime: timeFromString(draft?.end_time ?? null)
			};
			workNotes = '';
			// A new draft carries no crew -- the job's own team is the person's next choice, here or later.
			assigneeIds = [];
			fieldError = '';
		}
		wasOpen = open;
	});

	function chooseClient(client: ClientListItem | null) {
		changingClient = false;
		selectedClient = client;
		propertyId = client?.primary_property?.id ?? '';
		choosingProperty = false;
	}

	// Most clients have one property, so this only asks which when there is a real choice to make.
	const clientPropertiesQuery = createQuery(() => ({
		queryKey: clientDetailKey(selectedClient?.id ?? ''),
		queryFn: () => fetchClient(selectedClient!.id),
		enabled: choosingProperty && Boolean(selectedClient),
		staleTime: 15_000
	}));
	const propertyOptions = $derived(
		(clientPropertiesQuery.data?.properties ?? []).map((property) => ({
			value: property.id,
			label: property.label || [property.address_line1, property.city].filter(Boolean).join(', ')
		}))
	);

	const chosenProperty = $derived(
		clientPropertiesQuery.data?.properties.find((p) => p.id === propertyId) ??
			(selectedClient?.primary_property?.id === propertyId ? selectedClient.primary_property : null)
	);
	const chosenAddress = $derived(
		chosenProperty
			? [
					chosenProperty.address_line1,
					chosenProperty.city,
					chosenProperty.state_region,
					chosenProperty.postal_code
				]
					.filter(Boolean)
					.join(', ')
			: 'No property yet'
	);
	// The first visit's schedule as the form currently holds it. This never rejects a half-filled schedule --
	// More Options carries whatever is there to the full form, where it can be finished -- so validation for
	// Save is a separate step below.
	function firstVisit(): JobFirstVisitSeed {
		const instructions = workNotes.trim() || null;
		if (scheduleLater) {
			return {
				visit_date: null,
				start_time: null,
				end_time: null,
				all_day: false,
				assignee_ids: assigneeIds,
				instructions
			};
		}
		const day = calendarDateToString(when.date) || null;
		if (anytime) {
			return {
				visit_date: day,
				start_time: null,
				end_time: null,
				all_day: true,
				assignee_ids: assigneeIds,
				instructions
			};
		}
		return {
			visit_date: day,
			start_time: timeToString(when.startTime) || null,
			end_time: timeToString(when.endTime) || null,
			all_day: false,
			assignee_ids: assigneeIds,
			instructions
		};
	}

	function buildSeed(): JobCreateSeed {
		return {
			client: selectedClient,
			property_id: propertyId,
			title: title.trim(),
			first_visit: firstVisit()
		};
	}

	// The same rules the create command and the database enforce, checked here so a bad combination is a
	// message in the form rather than a raw error bounced back from the write.
	function validate(): string | null {
		if (title.trim().length < 2) return 'Give the job a title.';
		if (!clientId || !selectedClient) return 'Choose a client to continue.';
		if (!propertyId) {
			return 'This client has no property yet. Add one on their profile before booking a job.';
		}
		if (!scheduleLater) {
			if (!calendarDateToString(when.date)) return 'Pick a day, or tick “Schedule later”.';
			if (!anytime) {
				const start = timeToString(when.startTime);
				const end = timeToString(when.endTime);
				if (end && !start) return 'Set a start time before an end time.';
				if (start && end && end <= start) return 'The end time has to come after the start time.';
			}
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
		onCreate(buildSeed());
	}

	function moreOptions() {
		// No validation gate: the full form is exactly where a half-filled draft gets finished.
		onMoreOptions(buildSeed());
	}

	// The slot to hand to the New Request page, in the calendar's own day/clock shape. It carries only the
	// schedule the gesture proposed -- an Anytime or dateless slot drops the clock, matching Jobber's Anytime
	// entry -- because the client, title and instructions all belong on the New Request page.
	function buildAssessmentSeed(): AssessmentCreateSeed {
		if (scheduleLater) {
			return { visit_date: null, start_time: null, end_time: null, all_day: false };
		}
		const day = calendarDateToString(when.date) || null;
		if (anytime) {
			return { visit_date: day, start_time: null, end_time: null, all_day: true };
		}
		return {
			visit_date: day,
			start_time: timeToString(when.startTime) || null,
			end_time: timeToString(when.endTime) || null,
			all_day: false
		};
	}

	function continueToRequest() {
		onCreateRequest(buildAssessmentSeed());
	}

	// The slot to hand to the event dialog, in its own day/clock shape. An event always needs a real day, so a
	// dateless slot (Schedule later, or no day yet) carries nothing and the dialog opens for the person to
	// pick a day. The title and details belong in the dialog, so only the schedule is carried.
	function buildEventSeed(): {
		event_date: string;
		start_time: string | null;
		end_time: string | null;
		all_day: boolean;
	} | null {
		if (scheduleLater) return null;
		const day = calendarDateToString(when.date);
		if (!day) return null;
		if (anytime) {
			return { event_date: day, start_time: null, end_time: null, all_day: true };
		}
		return {
			event_date: day,
			start_time: timeToString(when.startTime) || null,
			end_time: timeToString(when.endTime) || null,
			all_day: false
		};
	}

	function continueToEvent() {
		onCreateEvent(buildEventSeed());
	}

	// A short, human summary of the slot the Request will open onto, so the person can see what is carried
	// across before they leave the calendar.
	const slotSummary = $derived.by(() => {
		if (scheduleLater) return 'No date yet — you can pick the day next.';
		const day = calendarDateToString(when.date);
		if (!day) return 'No date yet — you can pick the day next.';
		const dayLabel = new Intl.DateTimeFormat(locale, {
			weekday: 'short',
			day: 'numeric',
			month: 'short'
		}).format(new Date(`${day}T00:00`));
		if (anytime) return `${dayLabel}, anytime`;
		const start = timeToString(when.startTime);
		if (!start) return dayLabel;
		const end = timeToString(when.endTime);
		const clock = (time: string) =>
			new Intl.DateTimeFormat(locale, { hour: 'numeric', minute: '2-digit' }).format(
				new Date(`${day}T${time}`)
			);
		return end ? `${dayLabel}, ${clock(start)} – ${clock(end)}` : `${dayLabel}, ${clock(start)}`;
	});

	// The same slot as a date tile, a day in words and a time, for the two tabs that hand it on. Null when
	// there is no date yet, and the plain sentence above says so instead.
	const slotParts = $derived.by(() => {
		if (scheduleLater) return null;
		const day = calendarDateToString(when.date);
		if (!day) return null;
		const date = new Date(`${day}T00:00`);
		const clock = (time: string) =>
			new Intl.DateTimeFormat(locale, { hour: 'numeric', minute: '2-digit' }).format(
				new Date(`${day}T${time}`)
			);
		const start = timeToString(when.startTime);
		const end = timeToString(when.endTime);
		const time = anytime
			? 'Anytime'
			: start
				? end
					? `${clock(start)} – ${clock(end)}`
					: clock(start)
				: null;
		return {
			month: new Intl.DateTimeFormat(locale, { month: 'short' }).format(date).toUpperCase(),
			dayNumber: date.getDate(),
			label: new Intl.DateTimeFormat(locale, {
				weekday: 'short',
				month: 'short',
				day: 'numeric'
			}).format(date),
			time
		};
	});
</script>

<!-- The icons are Tabler SVG files imported at build time, not user content. -->
<!-- eslint-disable svelte/no-at-html-tags -->
{#snippet slotCard()}
	{#if slotParts}
		<div class="job-create__slot">
			<span class="job-create__slot-tile" aria-hidden="true">
				<span class="job-create__slot-month">{slotParts.month}</span>
				<span class="job-create__slot-day">{slotParts.dayNumber}</span>
			</span>
			<span class="job-create__slot-text">
				<span class="job-create__slot-label">{slotParts.label}</span>
				{#if slotParts.time}
					<span class="job-create__slot-time">
						<span class="job-create__slot-clock" aria-hidden="true">{@html clockIcon}</span>
						{slotParts.time}
					</span>
				{/if}
			</span>
		</div>
	{:else}
		<p class="job-create__slot job-create__slot--none">{slotSummary}</p>
	{/if}
{/snippet}

{#snippet propertyPicker()}
	<Select
		id="job-create-property"
		value={propertyId}
		options={propertyOptions}
		placeholder="Loading properties…"
		label="Property"
		onchange={(id) => {
			propertyId = id;
			choosingProperty = false;
		}}
	/>
{/snippet}
<Dialog
	{open}
	title={createType === 'request'
		? 'New request'
		: createType === 'event'
			? 'New event'
			: 'New job'}
	size="medium"
	initialFocusId="job-create-title"
	icon={dialogLook.icon}
	iconTone={dialogLook.tone}
	onClose={() => {
		if (!saving) onClose();
	}}
>
	<div class="job-create">
		<SegmentedControl
			value={createType}
			options={typeOptions}
			ariaLabel="What are you booking?"
			size="small"
			tone="plain"
			fullWidth
			onchange={(value) => (createType = value as CreateType)}
		/>

		{#if createType === 'request'}
			<!-- Request creation is a page of its own, so this tab only stages the slot and hands off. The
			     Request and its on-site assessment are created and owned by Requests. -->
			<div class="job-create__handoff">
				<p class="job-create__handoff-lead">
					A request opens the full New Request form, with the on-site visit booked onto this slot:
				</p>
				{@render slotCard()}
				<p class="job-create__handoff-note">
					<span class="job-create__handoff-arrow" aria-hidden="true">{@html arrowRightIcon}</span>
					You will add the client and what they are asking for there.
				</p>
			</div>
		{:else if createType === 'event'}
			<!-- An event is Schedule's own, so this tab only carries the slot into the event dialog. It belongs
			     to no client and no job -- just a title, an optional note and this day. -->
			<div class="job-create__handoff">
				<p class="job-create__handoff-lead">
					An event blocks this slot for the whole team — a meeting, training or holiday:
				</p>
				{@render slotCard()}
				<p class="job-create__handoff-note">
					<span class="job-create__handoff-arrow" aria-hidden="true">{@html arrowRightIcon}</span>
					You will give it a title and any details next. It has no client or crew.
				</p>
			</div>
		{:else}
			{#each [error, fieldError].filter(Boolean) as message (message)}
				<p class="job-create__alert" role="alert">
					<span class="job-create__alert-icon" aria-hidden="true">{@html alertCircleIcon}</span>
					{message}
				</p>
			{/each}

			<Input
				id="job-create-title"
				label="Job title"
				placeholder="What is this job?"
				required
				bind:value={title}
				maxlength={160}
			/>

			<div class="job-create__client">
				{#if selectedClient && !changingClient}
					<span class="job-create__field-label">Client <span aria-hidden="true">*</span></span>
					<PickedClient
						id={selectedClient.id}
						name={selectedClient.display_name}
						subtitle={selectedClient.company_name !== selectedClient.display_name
							? selectedClient.company_name
							: null}
						phone={selectedClient.phone}
						email={selectedClient.email}
						property={chosenAddress}
						propertyHint={chosenProperty?.label || undefined}
						onChangeClient={() => (changingClient = true)}
						onChangeProperty={selectedClient.additional_property_count > 0
							? () => (choosingProperty = true)
							: undefined}
						propertyPicker={choosingProperty ? propertyPicker : undefined}
					/>
				{:else}
					<ClientPicker
						id="job-create-client"
						required
						bind:value={clientId}
						onSelect={chooseClient}
					/>
				{/if}
			</div>

			<section class="job-create__group" aria-labelledby="job-create-first-visit">
				<header class="job-create__group-head">
					<IconTile icon={calendarTimeIcon} tone="time" size={24} />
					<h3 class="job-create__group-title" id="job-create-first-visit">First visit</h3>
				</header>

				<Checkbox
					id="job-create-later"
					label="Schedule later"
					description="Book the job now and give its first visit a date when you know it."
					bind:checked={scheduleLater}
				/>

				{#if !scheduleLater}
					<DateTimePicker
						id="job-create-when"
						range
						showTime={!anytime}
						dateLabel="Day of the first visit"
						timeLabel="Time"
						{locale}
						bind:value={when}
					/>
					<Checkbox
						id="job-create-anytime"
						label="Anytime"
						description="Promise the day without promising an hour."
						checked={anytime}
						onchange={(checked) => {
							anytime = checked;
							if (checked) when = { ...when, startTime: undefined, endTime: undefined };
						}}
					/>
				{/if}

				<Textarea
					id="job-create-notes"
					label="Notes for the first visit"
					rows={3}
					maxlength={2000}
					bind:value={workNotes}
				/>
			</section>

			<TeamPicker id="job-create-team" bind:value={assigneeIds} {open} />

			{@render notice?.()}
		{/if}
	</div>

	{#snippet footer()}
		{#if createType === 'request'}
			<Button onclick={continueToRequest}>Continue to new request</Button>
		{:else if createType === 'event'}
			<Button onclick={continueToEvent}>Continue to new event</Button>
		{:else}
			<Button variant="tertiary" onclick={moreOptions} disabled={saving}>
				<span class="job-create__button-icon" aria-hidden="true">{@html adjustmentsIcon}</span>
				More options
			</Button>
			<Button onclick={save} loading={saving}>{@html checkIcon}Save job</Button>
		{/if}
	{/snippet}
</Dialog>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.job-create {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);

		&__alert {
			display: flex;
			align-items: center;
			gap: var(--space-small);
			margin: 0;
			padding: 11px var(--space-base);
			border-radius: var(--radius-base);
			background: var(--color-critical--surface);
			color: var(--color-critical--onSurface);
			font-size: var(--typography--fontSize-small);
			font-weight: 600;
		}

		&__alert-icon {
			display: inline-flex;
			flex-shrink: 0;

			:global(svg) {
				width: 16px;
				height: 16px;
			}
		}

		&__client {
			display: flex;
			flex-direction: column;
			gap: var(--space-small);
		}

		// Everything about the first visit, in one tinted group, so the form reads as who it is for, when, and
		// who is going.
		&__group {
			display: flex;
			flex-direction: column;
			gap: var(--space-base);
			padding: 0;
			border: 0;
			background: transparent;
		}

		&__field-label {
			font-size: var(--typography--fontSize-label);
			font-weight: 600;
			color: var(--color-heading);
			> span {
				color: var(--color-critical);
			}
		}
		&__group-head {
			padding: var(--space-small) var(--space-slim);
			border-radius: var(--radius-base);
			background: var(--color-surface--background--subtle);
			display: flex;
			align-items: center;
			gap: 10px;
		}

		&__group-title {
			margin: 0;
			color: var(--color-heading);
			font-size: var(--typography--fontSize-base);
			font-weight: 700;
		}

		&__button-icon {
			display: inline-flex;

			:global(svg) {
				width: 16px;
				height: 16px;
			}
		}

		&__handoff {
			display: flex;
			flex-direction: column;
			gap: var(--space-base);
			padding-top: var(--space-smaller);
		}

		&__handoff-lead {
			margin: 0;
			color: var(--color-text);
			font-size: var(--typography--fontSize-base);
			line-height: var(--typography--lineHeight-base);
		}

		&__slot {
			display: flex;
			align-items: center;
			gap: var(--space-base);
			margin: 0;
			padding: var(--space-small) var(--space-base);
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-base);
			background: var(--color-surface--background--subtle);

			&--none {
				color: var(--color-text--secondary);
				font-size: var(--typography--fontSize-small);
			}
		}

		// A little calendar page: the month on a green strip, the day under it.
		&__slot-tile {
			display: flex;
			flex: 0 0 auto;
			flex-direction: column;
			width: 50px;
			overflow: hidden;
			border: var(--border-base) solid var(--color-border--interactive);
			border-radius: var(--radius-small);
			background: var(--color-surface);
			text-align: center;
		}

		&__slot-month {
			padding: 2px 0;
			background: var(--color-interactive);
			color: var(--color-text--reverse);
			font-size: 10px;
			font-weight: 700;
			letter-spacing: 0.8px;
		}

		&__slot-day {
			padding: 3px 0 4px;
			color: var(--color-heading);
			font-size: 20px;
			font-weight: 700;
			line-height: 1.1;
		}

		&__slot-text {
			display: flex;
			flex-direction: column;
			gap: 3px;
		}

		&__slot-label {
			color: var(--color-heading);
			font-size: var(--typography--fontSize-large);
			font-weight: 700;
		}

		&__slot-time {
			display: inline-flex;
			align-items: center;
			gap: 6px;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__slot-clock {
			display: inline-flex;

			:global(svg) {
				width: 14px;
				height: 14px;
			}
		}

		&__handoff-note {
			display: flex;
			align-items: center;
			gap: var(--space-small);
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__handoff-arrow {
			display: inline-flex;

			:global(svg) {
				width: 14px;
				height: 14px;
			}
		}
	}
</style>
