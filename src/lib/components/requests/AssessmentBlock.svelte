<script lang="ts">
	import NotifyCustomerCheckbox from '$lib/components/schedule/NotifyCustomerCheckbox.svelte';
	import { createQuery } from '@tanstack/svelte-query';
	import { page } from '$app/state';
	import SectionBlock from '$lib/components/layout/SectionBlock.svelte';
	import RecordCard from '$lib/components/layout/RecordCard.svelte';
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
	import { calendarDay, clockMinutesInZone, zonedTimeToUtc } from '$lib/time/calendar-day';
	import { assignableTeamKey, fetchAssignableTeam, type TeamMember } from '$lib/team/api';
	import type { AssessmentDraft, RequestAssessment } from '$lib/requests/api';
	import type { AssessmentCreateSeed } from '$lib/requests/assessmentSeed';
	import WorkTimerControl from '$lib/components/time-clock/WorkTimerControl.svelte';
	import { fetchMyTimer, myTimerKey } from '$lib/time-clock/api';
	import truckIcon from '@tabler/icons/outline/truck.svg?raw';
	import usersIcon from '@tabler/icons/outline/users.svg?raw';
	import calendarIcon from '@tabler/icons/outline/calendar.svg?raw';

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
		timezone = 'UTC',
		saving = false,
		error = '',
		draft = false,
		seed = null,
		onSave,
		onRemove,
		onComplete,
		onDraftChange,
		notify = $bindable(false),
		look = 'default'
	}: {
		assessment: RequestAssessment | null;
		/** The organization's own timezone. A day/time typed here is booked in it, not the browser's. */
		timezone?: string;
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
		/** Client reminders Part 4: true when the "Notify customer" box is showing and ticked. The page sends it
		 *  with the save. */
		notify?: boolean;
		/** `record` draws classic.pen's "On-site assessment card" when Classic is on; the New Request form
		 *  keeps the default look. */
		look?: 'default' | 'record';
	} = $props();

	const classic = $derived(look === 'record' && page.data.presentation === 'classic');

	let notifyCustomer = $state(true);
	let noticeVisible = $state(false);
	$effect(() => {
		notify = notifyCustomer && noticeVisible;
	});

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
	// organization's own timezone rather than the browser's, or a dispatcher whose device disagrees with
	// the business would silently book the wrong day or hour.
	function localPart(iso: string | null) {
		if (!iso) return undefined;
		return calendarDay(new Date(iso), timezone);
	}

	function localTime(iso: string | null) {
		if (!iso) return undefined;
		const minutes = clockMinutesInZone(new Date(iso), timezone);
		return `${String(Math.floor(minutes / 60)).padStart(2, '0')}:${String(minutes % 60).padStart(2, '0')}`;
	}

	function isoFrom(day: string, time: string) {
		const parsed = zonedTimeToUtc(day, time, timezone);
		return parsed ? parsed.toISOString() : null;
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

	const dayFormat = $derived(
		new Intl.DateTimeFormat('en-GB', {
			timeZone: timezone,
			weekday: 'short',
			day: 'numeric',
			month: 'short',
			year: 'numeric'
		})
	);
	const timeFormat = $derived(
		new Intl.DateTimeFormat('en-GB', { timeZone: timezone, hour: 'numeric', minute: '2-digit' })
	);

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

	// The person's own Start and Stop (plan § Assessment timers): offered only on the day the visit is booked,
	// as Jobber does, and on an Assessment not yet complete. A timer already running here always shows, so it
	// can be stopped. The timer query is the one shared by every Start control and the header.
	const timerQuery = createQuery(() => ({
		queryKey: myTimerKey,
		queryFn: fetchMyTimer,
		enabled: Boolean(assessment?.starts_at) && !draft,
		staleTime: 30_000
	}));
	const isToday = $derived.by(() => {
		const startsAt = assessment?.starts_at;
		if (!startsAt) return false;
		return calendarDay(new Date(startsAt), timezone) === calendarDay(new Date(), timezone);
	});
	const timerHere = $derived(
		timerQuery.data?.timer?.kind === 'assessment' &&
			timerQuery.data.timer.assessment_id === assessment?.id
	);
	const showsTimer = $derived(
		!draft &&
			Boolean(assessment) &&
			(timerHere || (isToday && !isComplete && Boolean(timerQuery.data?.can_time)))
	);

	// classic.pen "Assessment visit" row: a date tile, then "Today · 2:00 PM – 3:00 PM" in the office's clock.
	const weekdayFormat = $derived(
		new Intl.DateTimeFormat('en-GB', { timeZone: timezone, weekday: 'short' })
	);
	const dayNumberFormat = $derived(
		new Intl.DateTimeFormat('en-GB', { timeZone: timezone, day: 'numeric' })
	);
	const monthDayFormat = $derived(
		new Intl.DateTimeFormat(undefined, { timeZone: timezone, month: 'short', day: 'numeric' })
	);
	const clockFormat = $derived(
		new Intl.DateTimeFormat(undefined, { timeZone: timezone, hour: 'numeric', minute: '2-digit' })
	);

	const classicWhen = $derived.by(() => {
		if (!assessment?.starts_at) return 'No date set yet';
		const start = new Date(assessment.starts_at);
		const day = isToday ? 'Today' : monthDayFormat.format(start);
		if (assessment.all_day) return `${day} · Anytime`;
		const end = assessment.ends_at ? new Date(assessment.ends_at) : null;
		return end
			? `${day} · ${clockFormat.format(start)} – ${clockFormat.format(end)}`
			: `${day} · ${clockFormat.format(start)}`;
	});
	const highlightToday = $derived(isToday && !isComplete);

	// The header's main button books the visit too, so it opens this panel rather than growing a second
	// copy of it.
	export function open() {
		openPanel();
	}
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
{#snippet panel()}
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

		{#if !scheduleLater}
			<NotifyCustomerCheckbox
				id="assessment-notify-customer"
				bind:checked={notifyCustomer}
				bind:visible={noticeVisible}
				kinds={assessment?.starts_at ? ['rescheduled'] : ['booked']}
				disabled={saving}
			/>
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
{/snippet}

{#snippet completeFooter()}
	<Checkbox
		id="assessment-complete"
		label="Assessment complete"
		description="Tick this once the visit has happened and you know what the work involves."
		checked={isComplete}
		disabled={saving}
		onchange={(checked) => void onComplete?.(checked)}
	/>
{/snippet}

{#if classic}
	<RecordCard
		title="On-site assessment"
		subtitle="Visit the property before you price the work"
		id="request-assessment"
		class="assessment-card"
		footer={assessment && !editing ? completeFooter : undefined}
	>
		{#snippet actions()}
			{#if assessment && !editing}
				<PencilButton onclick={openPanel} label="Edit the on-site assessment" />
			{/if}
		{/snippet}

		{#if editing}
			<div class="assessment-card__editor">{@render panel()}</div>
		{:else if !assessment}
			<div class="assessment-card__empty">
				<p>No visit booked yet.</p>
				<Button variant="secondary" size="small" onclick={openPanel} onhover={warm}>
					Book a visit
				</Button>
			</div>
		{:else}
			<div class="assessment-visit" class:assessment-visit--today={highlightToday}>
				<span
					class="assessment-visit__date"
					class:assessment-visit__date--today={highlightToday}
					aria-hidden="true"
				>
					{#if assessment.starts_at}
						<span class="assessment-visit__weekday"
							>{weekdayFormat.format(new Date(assessment.starts_at))}</span
						>
						<span class="assessment-visit__day"
							>{dayNumberFormat.format(new Date(assessment.starts_at))}</span
						>
					{:else}
						<span class="assessment-visit__no-date">{@html calendarIcon}</span>
					{/if}
				</span>

				<div class="assessment-visit__info">
					<p class="assessment-visit__when">{classicWhen}</p>
					{#if assessment.instructions}
						<p class="assessment-visit__instructions">{assessment.instructions}</p>
					{/if}
					<p class="assessment-visit__note">
						<span aria-hidden="true">{@html usersIcon}</span>
						{assignedNames.length > 0 ? assignedNames.join(', ') : 'Nobody assigned yet'}
					</p>
				</div>

				{#if showsTimer}
					<div class="assessment-visit__timer">
						<WorkTimerControl
							target={{ kind: 'assessment', assessmentId: assessment.id }}
							completed={isComplete || !isToday}
						/>
					</div>
				{/if}
			</div>

			{#if error}
				<p class="assessment-card__error" role="alert">{error}</p>
			{/if}
		{/if}
	</RecordCard>
{:else}
	<SectionBlock title="On-site assessment" icon={truckIcon} level={2} form={editing}>
		{#snippet actions()}
			{#if assessment && !editing}
				<PencilButton onclick={openPanel} label="Edit the on-site assessment" />
			{/if}
		{/snippet}

		{#if editing}
			{@render panel()}
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

				{#if showsTimer && assessment}
					<div class="assessment__timer">
						<WorkTimerControl
							target={{ kind: 'assessment', assessmentId: assessment.id }}
							completed={isComplete || !isToday}
						/>
					</div>
				{/if}

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
{/if}

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

		&__timer {
			display: flex;
			flex-wrap: wrap;
			align-items: center;
			gap: var(--space-small);
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

	// --- Classic (classic.pen "On-site assessment card" in "Request details · 1440") ---------------------
	.assessment-card {
		&__editor {
			padding: 18px 24px 22px;
			border-top: 1px solid var(--classic2-divider);
		}

		&__empty {
			display: flex;
			align-items: center;
			justify-content: space-between;
			gap: 12px;
			padding: 16px 24px;
			border-top: 1px solid var(--classic2-divider);

			p {
				margin: 0;
				color: var(--classic2-secondary);
				font-size: var(--classic2-font-label);
			}
		}

		&__error {
			margin: 0;
			padding: 0 24px 14px;
			color: var(--classic2-rose);
			font-size: var(--classic2-font-label);
			font-weight: 600;
		}
	}

	.assessment-visit {
		display: flex;
		align-items: center;
		gap: 16px;
		padding: 16px 24px;
		border-top: 1px solid var(--classic2-divider);
		font-family: var(--classic2-font);

		&--today {
			background: var(--classic2-green-tint);
		}

		&__date {
			display: flex;
			flex: 0 0 auto;
			flex-direction: column;
			align-items: center;
			justify-content: center;
			gap: 1px;
			box-sizing: border-box;
			width: 52px;
			height: 56px;
			border: 1px solid var(--classic2-border-control);
			border-radius: var(--classic2-radius-control);
			background: var(--classic2-surface);

			&--today {
				border-color: var(--classic2-solid-green);
				background: var(--classic2-solid-green);

				.assessment-visit__weekday,
				.assessment-visit__day {
					color: var(--classic2-green-on);
				}

				.assessment-visit__weekday {
					opacity: 0.8;
				}
			}
		}

		&__weekday {
			color: var(--classic2-secondary);
			font-size: 10px;
			font-weight: 700;
			letter-spacing: 0.6px;
			text-transform: uppercase;
		}

		&__day {
			color: var(--classic2-ink);
			font-size: 20px;
			font-weight: 700;
			line-height: 1.1;
		}

		&__no-date {
			display: inline-flex;
			color: var(--classic2-icon-muted);

			:global(svg) {
				width: 20px;
				height: 20px;
			}
		}

		&__info {
			display: flex;
			flex: 1 1 auto;
			flex-direction: column;
			gap: 4px;
			min-width: 0;
		}

		&__when {
			margin: 0;
			color: var(--classic2-ink);
			font-size: 15px;
			font-weight: 600;
		}

		&__instructions {
			margin: 0;
			color: var(--classic2-secondary);
			font-size: var(--classic2-font-label);
			font-weight: 500;
			white-space: pre-wrap;
			overflow-wrap: anywhere;
		}

		&__note {
			display: flex;
			align-items: center;
			gap: 6px;
			margin: 0;
			padding-top: 2px;
			color: var(--classic2-secondary);
			font-size: var(--classic2-font-small);
			font-weight: 600;

			span {
				display: inline-flex;
			}

			:global(svg) {
				width: 13px;
				height: 13px;
			}
		}

		&__timer {
			display: flex;
			flex: 0 0 auto;
			align-items: center;
		}
	}
</style>
