<script lang="ts">
	import { createQuery } from '@tanstack/svelte-query';
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import Textarea from '$lib/components/ui/Textarea.svelte';
	import Checkbox from '$lib/components/ui/Checkbox.svelte';
	import DateTimePicker from '$lib/components/ui/DateTimePicker.svelte';
	import SegmentedControl from '$lib/components/ui/SegmentedControl.svelte';
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
		onClose
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
		onClose: () => void;
	} = $props();

	// Which kind of work this slot becomes. Job is the default, exactly as Jobber's chooser opens; Request
	// hands off to its own page rather than writing anything here.
	type CreateType = 'job' | 'request';
	let createType = $state<CreateType>('job');
	const typeOptions = [
		{ value: 'job', label: 'Job' },
		{ value: 'request', label: 'Request' }
	];

	let title = $state('');
	let clientId = $state('');
	let selectedClient = $state<ClientListItem | null>(null);
	let propertyId = $state('');
	let choosingProperty = $state(false);
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

	// A short, human summary of the slot the Request will open onto, so the person can see what is carried
	// across before they leave the calendar.
	const slotSummary = $derived.by(() => {
		if (scheduleLater) return 'No date yet — you can book the visit on the request.';
		const day = calendarDateToString(when.date);
		if (!day) return 'No date yet — you can book the visit on the request.';
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
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<Dialog {open} title={createType === 'request' ? 'New request' : 'New job'} {onClose}>
	<div class="job-create">
		<SegmentedControl
			value={createType}
			options={typeOptions}
			label="What are you booking?"
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
				<p class="job-create__handoff-slot">{slotSummary}</p>
				<p class="job-create__handoff-note">
					You will add the client and what they are asking for there.
				</p>
			</div>
			<div class="job-create__actions">
				<Button onclick={continueToRequest}>Continue to new request</Button>
			</div>
		{:else}
			{#if error}<p class="job-create__alert" role="alert">{error}</p>{/if}
			{#if fieldError}<p class="job-create__alert" role="alert">{fieldError}</p>{/if}

			<Input
				id="job-create-title"
				label="Job title"
				placeholder="What is this job?"
				required
				bind:value={title}
				maxlength={160}
			/>

			<div class="job-create__client">
				<ClientPicker
					id="job-create-client"
					required
					bind:value={clientId}
					onSelect={chooseClient}
				/>
				{#if selectedClient && (selectedClient.additional_property_count > 0 || choosingProperty)}
					{#if choosingProperty}
						<Select
							id="job-create-property"
							bind:value={propertyId}
							options={propertyOptions}
							placeholder="Loading properties…"
							label="Property"
						/>
					{:else}
						<button
							type="button"
							class="job-create__change-property"
							onclick={() => (choosingProperty = true)}
						>
							Change property
						</button>
					{/if}
				{/if}
			</div>

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

			<TeamPicker id="job-create-team" bind:value={assigneeIds} {open} />

			<div class="job-create__actions">
				<Button variant="tertiary" onclick={moreOptions} disabled={saving}>More options</Button>
				<Button onclick={save} loading={saving}>Save job</Button>
			</div>
		{/if}
	</div>
</Dialog>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.job-create {
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

		&__client {
			display: flex;
			flex-direction: column;
			gap: var(--space-small);
		}

		&__change-property {
			align-self: flex-start;
			padding: 0;
			border: 0;
			color: var(--color-interactive);
			background: transparent;
			font: inherit;
			font-size: var(--typography--fontSize-small);
			font-weight: 600;
			cursor: pointer;

			&:hover {
				color: var(--color-interactive--hover);
				text-decoration: underline;
			}
			&:focus-visible {
				outline: none;
				box-shadow: var(--shadow-focus);
			}
		}

		&__actions {
			display: flex;
			justify-content: flex-end;
			gap: var(--space-small);
			margin-top: var(--space-small);
		}

		&__handoff {
			display: flex;
			flex-direction: column;
			gap: var(--space-small);
			padding: var(--space-base);
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-base);
			background: var(--color-surface--background--subtle);
		}

		&__handoff-lead {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__handoff-slot {
			margin: 0;
			color: var(--color-heading);
			font-size: var(--typography--fontSize-large);
			font-weight: 600;
		}

		&__handoff-note {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}
	}
</style>
