<script lang="ts">
	import NotifyCustomerCheckbox from '$lib/components/schedule/NotifyCustomerCheckbox.svelte';
	import { createQuery } from '@tanstack/svelte-query';
	import SectionBlock from '$lib/components/layout/SectionBlock.svelte';
	import EmptyState from '$lib/components/data-display/EmptyState.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Checkbox from '$lib/components/ui/Checkbox.svelte';
	import PersonPickChip from '$lib/components/ui/PersonPickChip.svelte';
	import Textarea from '$lib/components/ui/Textarea.svelte';
	import DateTimePicker from '$lib/components/ui/DateTimePicker.svelte';
	import PencilButton from '$lib/components/ui/PencilButton.svelte';
	import Badge from '$lib/components/ui/Badge.svelte';
	import IconTile from '$lib/components/ui/IconTile.svelte';
	import {
		calendarDateFromString,
		emptyDateTimePickerValue,
		timeFromString,
		timeToString,
		calendarDateToString,
		formatTimeText,
		type DateTimePickerValue
	} from '$lib/components/ui/date-time';
	import { calendarDay, clockMinutesInZone, zonedTimeToUtc } from '$lib/time/calendar-day';
	import { assignableTeamKey, fetchAssignableTeam, type TeamMember } from '$lib/team/api';
	import type { AssessmentDraft, RequestAssessment } from '$lib/requests/api';
	import type { AssessmentCreateSeed } from '$lib/requests/assessmentSeed';
	import WorkTimerControl from '$lib/components/time-clock/WorkTimerControl.svelte';
	import { fetchMyTimer, myTimerKey } from '$lib/time-clock/api';
	import truckIcon from '@tabler/icons/outline/truck.svg?raw';
	import calendarPlusIcon from '@tabler/icons/outline/calendar-plus.svg?raw';
	import usersIcon from '@tabler/icons/outline/users.svg?raw';
	import calendarIcon from '@tabler/icons/outline/calendar-question.svg?raw';
	import calendarClockIcon from '@tabler/icons/outline/calendar-clock.svg?raw';
	import trashIcon from '@tabler/icons/outline/trash.svg?raw';
	import checkIcon from '@tabler/icons/outline/check.svg?raw';
	import alertCircleIcon from '@tabler/icons/outline/alert-circle.svg?raw';
	import loaderIcon from '@tabler/icons/outline/loader-2.svg?raw';

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
		notify = $bindable(false)
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
	} = $props();

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
	// Which box the message is about, so that box alone gets the error edge.
	let fieldErrorAt = $state<'date' | 'time' | null>(null);

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
		fieldErrorAt = null;
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
	function buildDraft():
		| { draft: AssessmentDraft }
		| { message: string; at: 'date' | 'time' | null } {
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
			return { message: 'Pick the day of the visit, or tick "Schedule later".', at: 'date' };
		}

		// "Anytime" is Jobber's arrival-window state: the day is booked, the hour is not promised.
		const startTime = anytime ? '00:00' : timeToString(when.startTime);
		const endTime = anytime ? '23:59' : timeToString(when.endTime);
		if (!startTime || !endTime) {
			return { message: 'Set a start and an end time, or tick "Anytime".', at: 'time' };
		}

		const startsAt = isoFrom(day, startTime);
		const endsAt = isoFrom(day, endTime);
		if (!startsAt || !endsAt) {
			return {
				message: 'That date and time could not be read. Try picking them again.',
				at: null
			};
		}
		if (Date.parse(endsAt) <= Date.parse(startsAt)) {
			return { message: 'The end time has to come after the start time.', at: 'time' };
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
		fieldErrorAt = null;
		const built = buildDraft();
		if ('message' in built) {
			fieldError = built.message;
			fieldErrorAt = built.at;
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
			fieldErrorAt = built.at;
			return { ok: false, message: built.message };
		}
		fieldError = '';
		fieldErrorAt = null;
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

	// --- The open panel's head ------------------------------------------------------------------------

	// The Time-tinted head reads the visit back as it is filled in: the day tile, when, and who is going,
	// the same head as an open visit on New job.
	const headDay = $derived(
		!scheduleLater && when.date ? new Date(when.date.year, when.date.month - 1, when.date.day) : null
	);
	const headLine = $derived.by(() => {
		if (scheduleLater) return 'No day yet · pick it once the client comes back to you';
		if (!headDay) return 'No day yet';
		const day = new Intl.DateTimeFormat('en-US', {
			weekday: 'short',
			month: 'short',
			day: 'numeric'
		}).format(headDay);
		if (anytime) return `${day} · Anytime`;
		const start = formatTimeText(when.startTime);
		const end = formatTimeText(when.endTime);
		if (!start) return day;
		return `${day} · ${end ? `${start} – ${end}` : start}`;
	});
	const headPeople = $derived.by(() => {
		const byId = new Map(team.map((member) => [member.id, member]));
		return assigneeIds.map((id) => byId.get(id)?.full_name ?? 'A team member').join(', ');
	});

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

	// The date tile beside a booked visit: weekday over day of the month, in the office's own clock.
	const tileWeekday = $derived(
		assessment?.starts_at
			? new Intl.DateTimeFormat('en-GB', { timeZone: timezone, weekday: 'short' })
					.format(new Date(assessment.starts_at))
					.toUpperCase()
			: ''
	);
	const tileDay = $derived(
		assessment?.starts_at
			? new Intl.DateTimeFormat('en-GB', { timeZone: timezone, day: 'numeric' }).format(
					new Date(assessment.starts_at)
				)
			: ''
	);

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

	// The header's main button books the visit too, so it opens this panel rather than growing a second
	// copy of it.
	export function open() {
		openPanel();
	}
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<SectionBlock
	title="On-site assessment"
	icon={truckIcon}
	level={2}
	tone="time"
	hint={draft ? 'Book a visit before you price the work.' : 'Visit the property before you price the work'}
>
	{#snippet actions()}
		{#if assessment && !editing}
			<PencilButton onclick={openPanel} label="Edit the on-site assessment" />
		{/if}
	{/snippet}

	{#if editing}
		<!-- The open visit, exactly like an open visit on New job: a Time-tinted head that reads the visit
		     back, then its fields. -->
		<div class="assessment__panel">
			<div class="assessment__head">
				{#if headDay}
					<span class="assessment__head-tile" aria-hidden="true">
						<span class="assessment__head-weekday"
							>{new Intl.DateTimeFormat('en-US', { weekday: 'short' })
								.format(headDay)
								.toUpperCase()}</span
						>
						<span class="assessment__head-day">{headDay.getDate()}</span>
					</span>
				{:else}
					<span class="assessment__head-tile assessment__head-tile--open" aria-hidden="true"
						>{@html calendarClockIcon}</span
					>
				{/if}
				<span class="assessment__head-text">
					<span class="assessment__head-title">Assessment</span>
					<span class="assessment__head-when">{headLine}</span>
				</span>
				{#if headPeople}
					<span class="assessment__head-people">{headPeople}</span>
				{:else}
					<span class="assessment__head-nobody">Nobody assigned yet</span>
				{/if}
			</div>

			<div class="assessment__editor">
				{#if !scheduleLater}
					<div class="assessment__schedule">
						<DateTimePicker
							id="assessment-when"
							range
							showTime={!anytime}
							dateLabel="Day of the visit"
							timeLabel="Time"
							dateInvalid={fieldErrorAt === 'date'}
							timeInvalid={fieldErrorAt === 'time'}
							bind:value={when}
						/>
						{#if fieldError && fieldErrorAt}
							<p class="assessment__field-error" role="alert">
								<span aria-hidden="true">{@html alertCircleIcon}</span>{fieldError}
							</p>
						{/if}
					</div>
				{/if}

				<div class="assessment__choices">
					{#if !scheduleLater}
						<Checkbox
							id="assessment-anytime"
							label="Anytime"
							description="Tell the client the day without promising an hour."
							bind:checked={anytime}
						/>
					{/if}
					<Checkbox
						id="assessment-schedule-later"
						label="Schedule later"
						description="Book the visit now and pick the day once the client comes back to you."
						bind:checked={scheduleLater}
					/>
				</div>

				<Textarea
					id="assessment-instructions"
					label="Instructions"
					rows={3}
					maxlength={2000}
					bind:value={instructions}
					placeholder="Anything whoever visits needs to know before they arrive"
				/>

				<fieldset class="assessment__team">
					<legend class="assessment__team-title">Who is going</legend>
					{#if teamQuery.isPending}
						<p class="assessment__team-state">
							<span class="assessment__team-icon assessment__team-icon--loading" aria-hidden="true"
								>{@html loaderIcon}</span
							>Loading your team…
						</p>
					{:else if teamQuery.isError}
						<p class="assessment__team-state assessment__team-state--error">
							<span class="assessment__team-icon" aria-hidden="true">{@html alertCircleIcon}</span>Your
							team could not be loaded. You can still save the visit.
						</p>
					{:else if team.length === 0}
						<p class="assessment__team-state">
							<span class="assessment__team-icon" aria-hidden="true">{@html usersIcon}</span>Nobody
							else is on your team yet.
						</p>
					{:else}
						<ul class="assessment__team-list">
							{#each team as member (member.id)}
								<li>
									<PersonPickChip
										id={`assessment-assignee-${member.id}`}
										personId={member.id}
										name={member.full_name ?? 'Unnamed team member'}
										checked={assigneeIds.includes(member.id)}
										onchange={(checked) => toggleAssignee(member.id, checked)}
									/>
								</li>
							{/each}
						</ul>
					{/if}
				</fieldset>

				{#if (fieldError && !fieldErrorAt) || (!fieldError && error)}
					<p class="assessment__field-error" role="alert">
						<span aria-hidden="true">{@html alertCircleIcon}</span>{fieldError || error}
					</p>
				{/if}

				{#if draft}
					<!-- The New Request page's own bar saves this panel, so it gets no Save of its own —
					     only Jobber's ✕, spelled out. -->
					<div class="assessment__editor-actions">
						<Button variant="secondary" variation="destructive" size="small" onclick={discardDraft}>
							<span class="assessment__button-icon" aria-hidden="true">{@html trashIcon}</span>
							Remove visit
						</Button>
					</div>
				{/if}
			</div>
		</div>

		{#if !scheduleLater}
			<div class="assessment__notify">
				<NotifyCustomerCheckbox
					id="assessment-notify-customer"
					bind:checked={notifyCustomer}
					bind:visible={noticeVisible}
					kinds={assessment?.starts_at ? ['rescheduled'] : ['booked']}
					disabled={saving}
				/>
			</div>
		{/if}

		{#if !draft}
			<div class="assessment__actions">
				{#if assessment}
					<Button
						variant="secondary"
						variation="destructive"
						onclick={() => void onRemove?.()}
						disabled={saving}
					>
						<span class="assessment__button-icon" aria-hidden="true">{@html trashIcon}</span>
						Remove visit
					</Button>
				{/if}
				<span class="assessment__spacer"></span>
				<Button variant="secondary" onclick={closePanel} disabled={saving}>Cancel</Button>
				<Button variant="primary" onclick={submit} loading={saving}>
					<span class="assessment__button-icon" aria-hidden="true">{@html checkIcon}</span>
					Save visit
				</Button>
			</div>
		{/if}
	{:else if !assessment && draft}
		<!-- A new request's empty visit is one slim row (layout.md → Create pages), not a page-sized empty state. -->
		<div class="assessment__empty-row">
			<IconTile icon={truckIcon} tone="time" size={40} />
			<div class="assessment__empty-words">
				<p class="assessment__empty-title">No visit booked</p>
				<p class="assessment__empty-text">
					Visit the property to assess the job before you do the work.
				</p>
			</div>
			<Button variant="secondary" onclick={openPanel} onhover={warm}>
				<span class="assessment__button-icon" aria-hidden="true">{@html calendarPlusIcon}</span>
				Book a visit
			</Button>
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
			<div class="assessment__visit">
				<span
					class="assessment__tile"
					class:assessment__tile--open={!assessment.starts_at}
					aria-hidden="true"
				>
					{#if assessment.starts_at}
						<span class="assessment__tile-weekday">{tileWeekday}</span>
						<span class="assessment__tile-day">{tileDay}</span>
					{:else}
						<span class="assessment__tile-icon">{@html calendarIcon}</span>
					{/if}
				</span>

				<div class="assessment__info">
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
				</div>

				{#if showsTimer && assessment}
					<div class="assessment__timer">
						<WorkTimerControl
							target={{ kind: 'assessment', assessmentId: assessment.id }}
							completed={isComplete || !isToday}
						/>
					</div>
				{/if}
			</div>

			<div class="assessment__complete">
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
		</div>
	{/if}
</SectionBlock>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.assessment__empty-row {
		display: flex;
		align-items: center;
		gap: var(--space-base);
	}

	.assessment__empty-words {
		display: grid;
		flex: 1 1 auto;
		gap: var(--space-smaller);
		min-width: 0;
	}

	.assessment__empty-title {
		margin: 0;
		color: var(--color-heading);
		font-size: var(--typography--fontSize-base);
		font-weight: 600;
	}

	.assessment__empty-text {
		margin: 0;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-base);
	}

	.assessment__button-icon {
		display: inline-flex;

		:global(svg) {
			width: 16px;
			height: 16px;
		}
	}

	.assessment {
		// The open visit: the New job open-visit panel (layout.md → On-site assessment panel).
		&__panel {
			overflow: hidden;
			border: var(--border-base) solid var(--color-time--surface-edge);
			border-radius: var(--radius-large);
		}

		&__head {
			display: flex;
			align-items: center;
			gap: 14px;
			padding: var(--space-slim) var(--space-base);
			border-bottom: var(--border-base) solid var(--color-time--surface-edge);
			background: var(--color-time--surface);
		}

		&__head-tile {
			display: flex;
			flex: 0 0 auto;
			flex-direction: column;
			align-items: center;
			justify-content: center;
			width: 44px;
			height: 44px;
			border-radius: var(--radius-tile-large);
			color: var(--color-surface);
			background: var(--color-time);

			&--open {
				border: var(--border-base) solid var(--color-time--surface-edge);
				color: var(--color-time);
				background: var(--color-surface);

				:global(svg) {
					width: 20px;
					height: 20px;
				}
			}
		}

		&__head-weekday {
			font-size: var(--typography--fontSize-small);
			font-weight: 600;
			line-height: 1.2;
		}

		&__head-day {
			font-size: 17px;
			font-weight: 700;
			line-height: 1.1;
		}

		&__head-text {
			display: flex;
			min-width: 0;
			flex: 1 1 auto;
			flex-direction: column;
			gap: 2px;
		}

		&__head-title {
			color: var(--color-time--onSurface);
			font-weight: 600;
		}

		&__head-when,
		&__head-people {
			color: var(--color-time--onSurface);
			font-size: var(--typography--fontSize-small);
		}

		&__head-people {
			overflow: hidden;
			flex: 0 1 auto;
			max-width: 40%;
			font-weight: 500;
			text-overflow: ellipsis;
			white-space: nowrap;
		}

		&__head-nobody {
			flex: 0 0 auto;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__editor {
			display: flex;
			flex-direction: column;
			gap: var(--space-base);
			padding: var(--space-base);
			background: var(--color-surface);
		}

		&__schedule {
			display: flex;
			flex-direction: column;
			gap: 6px;
		}

		// Anytime and Schedule later side by side.
		&__choices {
			display: grid;
			grid-template-columns: repeat(2, minmax(0, 1fr));
			gap: var(--space-slim) var(--space-large);
		}

		&__editor-actions {
			display: flex;
		}

		&__field-error {
			display: flex;
			align-items: center;
			gap: 6px;
			margin: 0;
			color: var(--color-critical);
			font-size: var(--typography--fontSize-small);

			:global(svg) {
				flex: 0 0 auto;
				width: 14px;
				height: 14px;
			}
		}

		// Notify customer closes the card under a line; it only shows for a dated visit it can tell about.
		&__notify {
			padding-top: var(--space-base);
			border-top: var(--border-base) solid var(--color-border);

			&:not(:has(input)) {
				display: none;
			}
		}

		&__actions {
			display: flex;
			align-items: center;
			gap: var(--space-small);
			padding-top: var(--space-base);
			border-top: var(--border-base) solid var(--color-border);
		}

		&__spacer {
			flex: 1 1 auto;
		}

		&__team {
			min-width: 0;
			margin: 0;
			padding: 0;
			border: 0;
		}

		&__team-title {
			padding: 0 0 6px;
			color: var(--color-heading);
			font-size: var(--typography--fontSize-label);
			font-weight: 600;
		}

		&__team-list {
			display: flex;
			flex-wrap: wrap;
			gap: var(--space-small);
			margin: 0;
			padding: 0;
			list-style: none;
		}

		&__team-state {
			display: flex;
			align-items: center;
			gap: var(--space-small);
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-label);
			font-weight: 500;

			&--error {
				color: var(--color-critical);
			}
		}

		&__team-icon {
			display: inline-flex;
			color: var(--color-icon--secondary);

			:global(svg) {
				width: 16px;
				height: 16px;
			}

			&--loading {
				animation: spinning var(--timing-loading) linear infinite;
			}
		}

		&__team-state--error &__team-icon {
			color: var(--color-critical);
		}

		// The booked visit: a tinted strip with the date tile, what and who, and the timer at the far end,
		// then a footer strip for ticking the visit complete. Both run edge to edge inside the card.
		// Doubled class: the card's own rule gives its children side margins, and this one has to win it.
		&__booked.assessment__booked {
			display: flex;
			flex-direction: column;
			margin: 0;
		}

		&__visit {
			display: flex;
			align-items: center;
			gap: 16px;
			padding: 18px 24px;
			border-top: var(--border-base) solid var(--color-border);
			background: var(--color-surface--background--subtle);
		}

		&__tile {
			display: flex;
			flex: 0 0 auto;
			flex-direction: column;
			align-items: center;
			justify-content: center;
			width: 52px;
			height: 56px;
			border-radius: var(--radius-base);
			color: var(--color-white);
			background: var(--color-interactive);
			line-height: 1;

			&--open {
				border: var(--border-base) solid var(--color-border);
				color: var(--color-icon--secondary);
				background: var(--color-surface);
			}
		}
		&__tile-weekday {
			font-size: 11px;
			font-weight: 600;
			letter-spacing: 0.6px;
		}
		&__tile-day {
			margin-top: 3px;
			font-size: 22px;
			font-weight: 700;
			letter-spacing: -0.4px;
		}
		&__tile-icon :global(svg) {
			display: block;
			width: 22px;
			height: 22px;
		}

		&__info {
			display: flex;
			flex: 1 1 auto;
			min-width: 0;
			flex-direction: column;
			gap: 4px;
		}

		&__when {
			display: flex;
			flex-wrap: wrap;
			align-items: center;
			gap: var(--space-small);
			margin: 0;
			color: var(--color-heading);
			font-size: 15px;
			font-weight: 600;
		}

		&__instructions {
			margin: 0;
			color: var(--color-text--secondary);
			white-space: pre-wrap;
		}

		&__timer {
			display: flex;
			flex: 0 0 auto;
			flex-wrap: wrap;
			align-items: center;
			gap: var(--space-small);
		}

		&__complete {
			display: flex;
			flex-direction: column;
			gap: var(--space-small);
			padding: 16px 24px 18px;
			border-top: var(--border-base) solid var(--color-border);
		}

		&__assigned {
			display: flex;
			align-items: center;
			gap: 6px;
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			font-weight: 500;
		}

		&__assigned-icon :global(svg) {
			display: block;
			width: 15px;
			height: 15px;
			color: var(--color-icon--secondary);
		}

		&__error {
			margin: 0;
			color: var(--color-critical--onSurface);
			font-size: var(--typography--fontSize-small);
			font-weight: 600;
		}
	}
</style>
