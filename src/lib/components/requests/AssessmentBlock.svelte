<script lang="ts">
	import { createQuery } from '@tanstack/svelte-query';
	import SectionBlock from '$lib/components/layout/SectionBlock.svelte';
	import EmptyState from '$lib/components/data-display/EmptyState.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Checkbox from '$lib/components/ui/Checkbox.svelte';
	import Textarea from '$lib/components/ui/Textarea.svelte';
	import DateTimePicker from '$lib/components/ui/DateTimePicker.svelte';
	import PencilButton from '$lib/components/ui/PencilButton.svelte';
	import Badge from '$lib/components/ui/Badge.svelte';
	import {
		calendarDateFromString,
		emptyDateTimePickerValue,
		timeFromString,
		timeToString,
		calendarDateToString,
		type DateTimePickerValue
	} from '$lib/components/ui/date-time';
	import { assignableTeamKey, fetchAssignableTeam, type TeamMember } from '$lib/team/api';
	import type { AssessmentDraft, RequestAssessment } from '$lib/requests/api';
	import type { AssessmentCreateSeed } from '$lib/requests/assessmentSeed';
	import truckIcon from '@tabler/icons/outline/truck.svg?raw';
	import usersIcon from '@tabler/icons/outline/users.svg?raw';

	// The on-site assessment, the way Jobber does it: an empty card inviting you to book the visit, which
	// opens into a panel on the page itself rather than a dialog. The panel owns its own Save, because an
	// assessment is a record of its own hanging off the request — the same rule a client's property follows.
	//
	// On the New Request form there is no request to hang it off yet, so `draft` turns that around: the
	// same panel, but it keeps the visit in memory and the page's own action bar writes it once the request
	// exists. In that mode the panel has no Save of its own — a second save footer is exactly what the
	// design rules forbid — only a way to drop the visit again.
	let {
		assessment,
		saving = false,
		error = '',
		draft = false,
		seed = null,
		onSave,
		onRemove,
		onComplete,
		onDraftChange
	}: {
		assessment: RequestAssessment | null;
		saving?: boolean;
		error?: string;
		/** Hold the visit in memory for a page that has not created its request yet. */
		draft?: boolean;
		/** Draft mode only: a slot handed over from Schedule's empty-slot chooser. When it carries a date, the
		 *  panel opens once already booked onto it, so the request is created with the visit the person clicked. */
		seed?: AssessmentCreateSeed | null;
		onSave?: (draft: AssessmentDraft) => void | Promise<void>;
		onRemove?: () => void | Promise<void>;
		onComplete?: (complete: boolean) => void | Promise<void>;
		/** Draft mode only: tells the page whether a visit is waiting to be saved with it. */
		onDraftChange?: (booked: boolean) => void;
	} = $props();

	let editing = $state(false);

	// --- The panel's own fields -----------------------------------------------------------------------

	let instructions = $state('');
	let scheduleLater = $state(true);
	let anytime = $state(false);
	let when = $state<DateTimePickerValue>(emptyDateTimePickerValue());
	let assigneeIds = $state<string[]>([]);
	let fieldError = $state('');

	// The team list waits until it is actually needed — someone opening the panel, or a booked visit that
	// has names to read out — and is cached from then on.
	let panelOpened = $state(false);
	const teamWanted = $derived(panelOpened || (assessment?.assignee_ids ?? []).length > 0);
	const teamQuery = createQuery(() => ({
		queryKey: assignableTeamKey,
		queryFn: fetchAssignableTeam,
		enabled: teamWanted,
		staleTime: 5 * 60 * 1000
	}));
	const team = $derived<TeamMember[]>(teamQuery.data ?? []);

	// Hovering anything that opens the panel is enough to start the team list loading, so the names are
	// already there when the panel appears.
	export function warm() {
		panelOpened = true;
	}

	// A slot handed over from Schedule's empty-slot chooser. When it names a day, the panel opens once already
	// booked onto that slot -- the same fields openPanel fills, but from the clicked day/clock rather than a
	// stored assessment. A dateless slot (the calendar's header action) leaves the empty card in place so the
	// person books the visit themselves. This runs a single time; after that the panel is theirs to edit.
	let seededFromSlot = false;
	$effect(() => {
		if (!draft || seededFromSlot || !seed || seed.visit_date === null) return;
		seededFromSlot = true;
		panelOpened = true;
		instructions = '';
		assigneeIds = [];
		scheduleLater = false;
		anytime = seed.all_day;
		when = {
			date: calendarDateFromString(seed.visit_date),
			startTime: timeFromString(seed.start_time),
			endTime: timeFromString(seed.end_time)
		};
		editing = true;
		fieldError = '';
		onDraftChange?.(true);
	});

	function openPanel() {
		panelOpened = true;
		fieldError = '';
		instructions = assessment?.instructions ?? '';
		assigneeIds = [...(assessment?.assignee_ids ?? [])];
		scheduleLater = !assessment?.starts_at;
		anytime = assessment?.all_day ?? false;
		when = assessment?.starts_at
			? {
					date: calendarDateFromString(localPart(assessment.starts_at)),
					startTime: timeFromString(localTime(assessment.starts_at)),
					endTime: timeFromString(localTime(assessment.ends_at))
				}
			: emptyDateTimePickerValue();
		editing = true;
		if (draft) onDraftChange?.(true);
	}

	function closePanel() {
		editing = false;
		fieldError = '';
	}

	// The stored instants are UTC; the office books in its own clock, so both directions go through the
	// browser's local time rather than slicing the ISO string.
	function localPart(iso: string | null) {
		if (!iso) return undefined;
		const date = new Date(iso);
		return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`;
	}

	function localTime(iso: string | null) {
		if (!iso) return undefined;
		const date = new Date(iso);
		return `${String(date.getHours()).padStart(2, '0')}:${String(date.getMinutes()).padStart(2, '0')}`;
	}

	function isoFrom(day: string, time: string) {
		const parsed = new Date(`${day}T${time}`);
		return Number.isNaN(parsed.getTime()) ? null : parsed.toISOString();
	}

	function toggleAssignee(id: string, checked: boolean) {
		assigneeIds = checked ? [...assigneeIds, id] : assigneeIds.filter((entry) => entry !== id);
	}

	// Reads the panel's fields into the shape the API wants, or returns the one thing that stops it. Both
	// the panel's own Save and the New Request page's action bar go through here, so a visit is checked the
	// same way whichever button ends up writing it.
	function buildDraft(): { draft: AssessmentDraft } | { message: string } {
		if (scheduleLater) {
			return {
				draft: {
					starts_at: null,
					ends_at: null,
					all_day: false,
					instructions: instructions.trim() || null,
					assignee_ids: assigneeIds
				}
			};
		}

		const day = calendarDateToString(when.date);
		if (!day) {
			return { message: 'Pick the day of the visit, or tick "Schedule later".' };
		}

		// "Anytime" is Jobber's arrival-window state: the day is booked, the hour is not promised.
		const startTime = anytime ? '00:00' : timeToString(when.startTime);
		const endTime = anytime ? '23:59' : timeToString(when.endTime);
		if (!startTime || !endTime) {
			return { message: 'Set a start and an end time, or tick "Anytime".' };
		}

		const startsAt = isoFrom(day, startTime);
		const endsAt = isoFrom(day, endTime);
		if (!startsAt || !endsAt) {
			return { message: 'That date and time could not be read. Try picking them again.' };
		}
		if (Date.parse(endsAt) <= Date.parse(startsAt)) {
			return { message: 'The end time has to come after the start time.' };
		}

		return {
			draft: {
				starts_at: startsAt,
				ends_at: endsAt,
				all_day: anytime,
				instructions: instructions.trim() || null,
				assignee_ids: assigneeIds
			}
		};
	}

	function submit() {
		fieldError = '';
		const built = buildDraft();
		if ('message' in built) {
			fieldError = built.message;
			return;
		}
		void onSave?.(built.draft);
	}

	// --- Draft mode -----------------------------------------------------------------------------------

	// The page asks for the visit at the moment it saves. A panel nobody opened means no visit at all, not
	// an empty one, so this hands back null rather than a blank draft.
	export function collectDraft():
		{ ok: true; draft: AssessmentDraft | null } | { ok: false; message: string } {
		if (!editing) return { ok: true, draft: null };
		const built = buildDraft();
		if ('message' in built) {
			fieldError = built.message;
			return { ok: false, message: built.message };
		}
		fieldError = '';
		return { ok: true, draft: built.draft };
	}

	// Jobber's ✕ on the panel throws the visit away and puts the empty card back. Ours says so in words.
	function discardDraft() {
		closePanel();
		instructions = '';
		scheduleLater = true;
		anytime = false;
		when = emptyDateTimePickerValue();
		assigneeIds = [];
		onDraftChange?.(false);
	}

	// --- What the booked card reads out ---------------------------------------------------------------

	const dayFormat = new Intl.DateTimeFormat('en-GB', {
		weekday: 'short',
		day: 'numeric',
		month: 'short',
		year: 'numeric'
	});
	const timeFormat = new Intl.DateTimeFormat('en-GB', { hour: 'numeric', minute: '2-digit' });

	const scheduleLine = $derived.by(() => {
		if (!assessment?.starts_at) return 'No date set yet';
		const start = new Date(assessment.starts_at);
		const day = dayFormat.format(start);
		if (assessment.all_day) return `${day}, anytime`;
		const end = assessment.ends_at ? new Date(assessment.ends_at) : null;
		return end
			? `${day}, ${timeFormat.format(start)} – ${timeFormat.format(end)}`
			: `${day}, ${timeFormat.format(start)}`;
	});

	const assignedNames = $derived.by(() => {
		const ids = assessment?.assignee_ids ?? [];
		if (ids.length === 0) return [];
		const byId = new Map(team.map((member) => [member.id, member]));
		return ids.map((id) => byId.get(id)?.full_name ?? 'A team member');
	});

	const isComplete = $derived(Boolean(assessment?.completed_at));

	// The header's main button books the visit too, so it opens this panel rather than growing a second
	// copy of it.
	export function open() {
		openPanel();
	}
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<SectionBlock title="On-site assessment" icon={truckIcon} level={2} form={editing}>
	{#snippet actions()}
		{#if assessment && !editing}
			<PencilButton onclick={openPanel} label="Edit the on-site assessment" />
		{/if}
	{/snippet}

	{#if editing}
		<div class="assessment__panel">
			<Textarea
				id="assessment-instructions"
				label="Instructions"
				rows={3}
				maxlength={2000}
				bind:value={instructions}
				placeholder="Anything whoever visits needs to know before they arrive"
			/>

			<Checkbox
				id="assessment-schedule-later"
				label="Schedule later"
				description="Book the visit now and pick the day once the client comes back to you."
				bind:checked={scheduleLater}
			/>

			{#if !scheduleLater}
				<DateTimePicker
					id="assessment-when"
					range={!anytime}
					dateLabel="Day of the visit"
					timeLabel="Time"
					bind:value={when}
				/>
				<Checkbox
					id="assessment-anytime"
					label="Anytime"
					description="Tell the client which day you are coming without promising an hour."
					bind:checked={anytime}
				/>
			{/if}

			<fieldset class="assessment__team">
				<legend class="assessment__team-title">Who is going</legend>
				{#if teamQuery.isPending}
					<p class="assessment__hint">Loading your team…</p>
				{:else if teamQuery.isError}
					<p class="assessment__error">
						Your team could not be loaded. You can still save the visit.
					</p>
				{:else if team.length === 0}
					<p class="assessment__hint">Nobody else is on your team yet.</p>
				{:else}
					<ul class="assessment__team-list">
						{#each team as member (member.id)}
							<li>
								<Checkbox
									id={`assessment-assignee-${member.id}`}
									label={member.full_name ?? 'Unnamed team member'}
									checked={assigneeIds.includes(member.id)}
									onchange={(checked) => toggleAssignee(member.id, checked)}
								/>
							</li>
						{/each}
					</ul>
				{/if}
			</fieldset>

			{#if fieldError || error}
				<p class="assessment__error" role="alert">{fieldError || error}</p>
			{/if}

			<div class="assessment__panel-actions">
				{#if draft}
					<!-- The New Request page's own bar saves this panel, so it gets no Save of its own —
					     only Jobber's ✕, spelled out. -->
					<Button variant="tertiary" variation="destructive" onclick={discardDraft}>
						Remove visit
					</Button>
				{:else}
					{#if assessment}
						<Button
							variant="tertiary"
							variation="destructive"
							onclick={() => void onRemove?.()}
							disabled={saving}
						>
							Remove visit
						</Button>
					{/if}
					<span class="assessment__spacer"></span>
					<Button variant="tertiary" onclick={closePanel} disabled={saving}>Cancel</Button>
					<Button variant="primary" onclick={submit} loading={saving}>Save visit</Button>
				{/if}
			</div>
		</div>
	{:else if !assessment}
		<EmptyState
			icon={truckIcon}
			iconLabel="Book the on-site visit"
			onIconClick={openPanel}
			title="No visit booked"
			description="Visit the property to assess the job before you do the work."
		>
			{#snippet action()}
				<Button variant="secondary" onclick={openPanel} onhover={warm}>Book a visit</Button>
			{/snippet}
		</EmptyState>
	{:else}
		<div class="assessment__booked">
			<p class="assessment__when">
				{scheduleLine}
				{#if isComplete}<Badge size="small" status="success">Done</Badge>{/if}
			</p>

			{#if assessment.instructions}
				<p class="assessment__instructions">{assessment.instructions}</p>
			{/if}

			<p class="assessment__assigned">
				<span class="assessment__assigned-icon" aria-hidden="true">{@html usersIcon}</span>
				{#if assignedNames.length > 0}
					{assignedNames.join(', ')}
				{:else}
					Nobody assigned yet
				{/if}
			</p>

			<Checkbox
				id="assessment-complete"
				label="Assessment complete"
				description="Tick this once the visit has happened and you know what the work involves."
				checked={isComplete}
				disabled={saving}
				onchange={(checked) => void onComplete?.(checked)}
			/>

			{#if error}
				<p class="assessment__error" role="alert">{error}</p>
			{/if}
		</div>
	{/if}
</SectionBlock>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.assessment {
		&__panel {
			display: flex;
			flex-direction: column;
			gap: var(--space-base);
		}

		&__panel-actions {
			display: flex;
			align-items: center;
			gap: var(--space-small);
			padding-top: var(--space-small);
			border-top: var(--border-base) solid var(--color-border);
		}

		&__spacer {
			flex: 1 1 auto;
		}

		&__team {
			border: 0;
			margin: 0;
			padding: 0;
			min-width: 0;
		}

		&__team-title {
			padding: 0 0 var(--space-small);
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			font-weight: 600;
		}

		&__team-list {
			display: flex;
			flex-wrap: wrap;
			gap: var(--space-small) var(--space-large);
			margin: 0;
			padding: 0;
			list-style: none;
		}

		&__booked {
			display: flex;
			flex-direction: column;
			gap: var(--space-base);
		}

		&__when {
			display: flex;
			align-items: center;
			gap: var(--space-small);
			margin: 0;
			color: var(--color-heading);
			font-size: var(--typography--fontSize-large);
			font-weight: 600;
		}

		&__instructions {
			margin: 0;
			color: var(--color-text--secondary);
			white-space: pre-wrap;
		}

		&__assigned {
			display: flex;
			align-items: center;
			gap: var(--space-small);
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__assigned-icon :global(svg) {
			width: 18px;
			height: 18px;
			color: var(--color-icon--secondary);
		}

		&__hint {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__error {
			margin: 0;
			color: var(--color-critical--onSurface);
			font-size: var(--typography--fontSize-small);
			font-weight: 600;
		}
	}
</style>
