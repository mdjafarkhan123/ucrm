<script lang="ts">
	import { createQuery } from '@tanstack/svelte-query';
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import Textarea from '$lib/components/ui/Textarea.svelte';
	import Checkbox from '$lib/components/ui/Checkbox.svelte';
	import DateTimePicker from '$lib/components/ui/DateTimePicker.svelte';
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
	import type { NewVisitDraft } from '$lib/schedule/drag';

	// Booking a job from empty calendar space, the way Jobber starts one in place: a light form seeded with
	// the day, time and any team the gesture proposed, so the common "client + one visit" job is a quick
	// fill-in without leaving the calendar. Full job creation still lives in Jobs -- More Options hands this
	// exact draft to the New Job page for line items and the rest. Save writes through the Jobs-owned create
	// command; this form only shapes the draft and hands it back, so the page owns the write and its feedback.

	let {
		open,
		draft = null,
		locale = 'en-US',
		saving = false,
		error = '',
		onCreate,
		onMoreOptions,
		onClose
	}: {
		open: boolean;
		/** The day and time the calendar gesture proposed. Null would mean no seed; every gesture supplies one. */
		draft?: NewVisitDraft | null;
		locale?: string;
		saving?: boolean;
		error?: string;
		/** Save: the Jobs-owned create command runs on the page with this draft. */
		onCreate: (seed: JobCreateSeed) => void;
		/** More Options: the same draft is carried to the full New Job page. */
		onMoreOptions: (seed: JobCreateSeed) => void;
		onClose: () => void;
	} = $props();

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
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<Dialog {open} title="New job" {onClose}>
	<div class="job-create">
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
			<ClientPicker id="job-create-client" required bind:value={clientId} onSelect={chooseClient} />
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
	}
</style>
