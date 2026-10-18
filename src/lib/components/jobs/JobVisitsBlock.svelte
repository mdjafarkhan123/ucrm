<script lang="ts">
	import { createQuery } from '@tanstack/svelte-query';
	import type { Snippet } from 'svelte';
	import SectionBlock from '$lib/components/layout/SectionBlock.svelte';
	import EmptyState from '$lib/components/data-display/EmptyState.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Checkbox from '$lib/components/ui/Checkbox.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import Textarea from '$lib/components/ui/Textarea.svelte';
	import DateTimePicker from '$lib/components/ui/DateTimePicker.svelte';
	import CreateVisitsDialog from '$lib/components/jobs/CreateVisitsDialog.svelte';
	import RecurrenceFields from '$lib/components/jobs/RecurrenceFields.svelte';
	import SegmentedControl from '$lib/components/ui/SegmentedControl.svelte';
	import PersonPickChip from '$lib/components/ui/PersonPickChip.svelte';
	import Avatar from '$lib/components/ui/Avatar.svelte';
	import {
		calendarDateFromString,
		calendarDateToString,
		emptyDateTimePickerValue,
		timeFromString,
		timeToString,
		type DateTimePickerValue
	} from '$lib/components/ui/date-time';
	import { assignableTeamKey, fetchAssignableTeam, type TeamMember } from '$lib/team/api';
	import type { JobFirstVisitSeed } from '$lib/jobs/createDraft';
	import type { JobVisitInput, JobRecurrenceInput } from '$lib/jobs/api';
	import calendarIcon from '@tabler/icons/outline/calendar-event.svg?raw';
	import calendarCheckIcon from '@tabler/icons/outline/calendar-check.svg?raw';
	import repeatIcon from '@tabler/icons/outline/repeat.svg?raw';
	import chevronDownIcon from '@tabler/icons/outline/chevron-down.svg?raw';
	import plusIcon from '@tabler/icons/outline/plus.svg?raw';
	import trashIcon from '@tabler/icons/outline/trash.svg?raw';

	// The Visits part of the New Job form, the way Jobber lays it out: an empty card that invites you to add
	// visits, a "Create Visits" button that picks a batch of days at once, then a card per visit you can open
	// to set its time, title, instructions and who is going. Every field lives in memory here; the page's own
	// action bar writes the whole job — scope and visits together — in one command, so this block has no Save
	// of its own.
	let {
		jobTitle = '',
		locale = 'en-US',
		seed = null,
		onCountChange,
		onKindChange,
		footer
	}: {
		jobTitle?: string;
		locale?: string;
		/** The first visit's schedule and team, when a Schedule calendar gesture opened this form. Null means
		 * the plain New Job page, which starts one visit dated today. */
		seed?: JobFirstVisitSeed | null;
		onCountChange?: (count: number) => void;
		/** The page hides the one-off billing reminder when the job repeats; billing for repeating work is
		 * its own decision and belongs to the billing part, not to this checkbox. */
		onKindChange?: (kind: 'one_off' | 'recurring') => void;
		/** Shown under the visits, inside the section: the New Job page's "Notify customer" box. */
		footer?: Snippet;
	} = $props();

	type VisitDraft = {
		key: string;
		when: DateTimePickerValue;
		scheduleLater: boolean;
		anytime: boolean;
		title: string;
		instructions: string;
		assigneeIds: string[];
		expanded: boolean;
	};

	function todayString() {
		const now = new Date();
		return `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}-${String(now.getDate()).padStart(2, '0')}`;
	}

	// Jobber opens a New Job with one visit already there, dated today and open for editing, so the common
	// one-visit job is a straight fill-in rather than a "create a visit first" step. When Schedule handed a
	// draft over, that first visit starts from the calendar gesture -- its day, time and team -- instead.
	function seededDraft(): VisitDraft {
		if (!seed) return { ...newDraft(todayString()), expanded: true };
		return {
			key: crypto.randomUUID(),
			when: {
				date: calendarDateFromString(seed.visit_date),
				startTime: timeFromString(seed.start_time),
				endTime: timeFromString(seed.end_time)
			},
			scheduleLater: seed.visit_date === null,
			anytime: seed.visit_date !== null && seed.all_day,
			title: '',
			instructions: seed.instructions ?? '',
			assigneeIds: [...seed.assignee_ids],
			expanded: true
		};
	}
	let drafts = $state<VisitDraft[]>([seededDraft()]);
	let creating = $state(false);
	let fieldError = $state('');

	// One-off or recurring, fixed the moment the job is saved and never switchable afterwards -- the same rule
	// Jobber enforces, because the type decides how the work is priced, scheduled and billed. A one-off lists
	// the days someone typed; a recurring job carries a rule and builds its own.
	let scheduleKind = $state<'one_off' | 'recurring'>('one_off');
	let asNeeded = $state(false);

	function blankRecurrence(): JobRecurrenceInput {
		return {
			frequency: 'weekly',
			interval_count: 1,
			weekdays: [new Date().getDay()],
			monthly_mode: null,
			month_day: null,
			ordinal_week: null,
			ordinal_weekday: null,
			start_date: todayString(),
			end_mode: 'after',
			duration_count: 6,
			duration_unit: 'month',
			end_date: null,
			start_time: null,
			end_time: null,
			all_day: false
		};
	}
	let recurrence = $state<JobRecurrenceInput>(blankRecurrence());

	// The page's Save button and its "job total" both watch how many visits are on the form. Reporting from
	// one effect covers the seeded first visit as well as later adds and removals, so the count is never
	// stale by one.
	$effect(() => onCountChange?.(scheduleKind === 'recurring' ? 1 : drafts.length));
	$effect(() => onKindChange?.(scheduleKind));

	// The team list waits until it is needed — the Create Visits button being hovered, a visit opened, or a
	// visit that already names someone — and is cached from then on. The New Job form always opens with its
	// first visit card expanded (see `drafts` above), so that "Who is going" list counts as revealed on load
	// and is fetched now rather than on the first interaction.
	let teamWanted = $state(true);
	const teamQuery = createQuery(() => ({
		queryKey: assignableTeamKey,
		queryFn: fetchAssignableTeam,
		enabled: teamWanted,
		staleTime: 5 * 60 * 1000
	}));
	const team = $derived<TeamMember[]>(teamQuery.data ?? []);
	const teamById = $derived(new Map(team.map((member) => [member.id, member])));

	function newDraft(date: string | null): VisitDraft {
		return {
			key: crypto.randomUUID(),
			when: date
				? { date: calendarDateFromString(date), startTime: undefined, endTime: undefined }
				: emptyDateTimePickerValue(),
			scheduleLater: date === null,
			anytime: false,
			title: '',
			instructions: '',
			assigneeIds: [],
			expanded: false
		};
	}

	function addVisits(result: { dates: string[]; scheduleLater: boolean }) {
		teamWanted = true;
		if (result.scheduleLater) {
			drafts = [...drafts, newDraft(null)];
		} else {
			drafts = [...drafts, ...result.dates.map((date) => newDraft(date))];
		}
		creating = false;
	}

	function removeVisit(key: string) {
		drafts = drafts.filter((draft) => draft.key !== key);
	}

	function toggleExpanded(key: string) {
		teamWanted = true;
		drafts = drafts.map((draft) =>
			draft.key === key ? { ...draft, expanded: !draft.expanded } : draft
		);
	}

	function setAnytime(key: string, checked: boolean) {
		drafts = drafts.map((draft) =>
			draft.key === key
				? {
						...draft,
						anytime: checked,
						when: checked ? { ...draft.when, startTime: undefined, endTime: undefined } : draft.when
					}
				: draft
		);
	}

	function toggleAssignee(key: string, id: string, checked: boolean) {
		drafts = drafts.map((draft) =>
			draft.key === key
				? {
						...draft,
						assigneeIds: checked
							? [...draft.assigneeIds, id]
							: draft.assigneeIds.filter((entry) => entry !== id)
					}
				: draft
		);
	}

	// --- What each card reads out ---------------------------------------------------------------------

	const weekdayFormat = $derived(new Intl.DateTimeFormat(locale, { weekday: 'short' }));
	const dayFormat = $derived(
		new Intl.DateTimeFormat(locale, { weekday: 'short', month: 'short', day: 'numeric' })
	);
	const timeFormat = $derived(
		new Intl.DateTimeFormat(locale, { hour: 'numeric', minute: '2-digit' })
	);

	function visitDate(draft: VisitDraft) {
		const day = draft.when.date;
		if (draft.scheduleLater || !day) return null;
		return new Date(day.year, day.month - 1, day.day);
	}

	// The date tile at the start of each visit row: the weekday over the day of the month.
	function dayBadge(draft: VisitDraft) {
		const date = visitDate(draft);
		if (!date) return { weekday: '', day: 'TBD' };
		return { weekday: weekdayFormat.format(date).toUpperCase(), day: String(date.getDate()) };
	}

	function clockTime(time: { hour: number; minute: number } | undefined) {
		return time ? timeFormat.format(new Date(2000, 0, 1, time.hour, time.minute)) : '';
	}

	// The quiet line under a visit's title: its day and hours, e.g. "Tue, Oct 21 · 9:00 AM – 1:00 PM".
	function whenLine(draft: VisitDraft) {
		const date = visitDate(draft);
		if (!date) return 'Not scheduled yet';
		const day = dayFormat.format(date);
		if (draft.anytime) return `${day} · Anytime`;
		const start = clockTime(draft.when.startTime);
		const end = clockTime(draft.when.endTime);
		if (!start) return day;
		return `${day} · ${end ? `${start} – ${end}` : start}`;
	}

	function assignees(draft: VisitDraft) {
		return draft.assigneeIds.map((id) => ({
			id,
			name: teamById.get(id)?.full_name ?? 'A team member'
		}));
	}

	// The line under the card's title: how many visits and when the first is.
	const headerHint = $derived.by(() => {
		if (scheduleKind === 'recurring') {
			return asNeeded ? 'As needed · no visits until you add them' : 'Repeats on a schedule';
		}
		if (drafts.length === 0) return 'No visits yet';
		const count = `${drafts.length} ${drafts.length === 1 ? 'visit' : 'visits'}`;
		const first = drafts
			.map(visitDate)
			.filter((date): date is Date => date !== null)
			.sort((a, b) => a.getTime() - b.getTime())[0];
		return first ? `${count} · first on ${dayFormat.format(first)}` : count;
	});

	// --- Handing the visits to the page ---------------------------------------------------------------

	// Reads every card into the shape the create command wants, or returns the first problem that stops it.
	// Times are optional — a visit can carry just a day — but a start without an end, or an end before its
	// start, is caught here rather than as a raw constraint from the database.
	export type CollectedSchedule = {
		ok: true;
		job_type: 'one_off' | 'recurring';
		is_as_needed: boolean;
		recurrence: JobRecurrenceInput | null;
		visits: JobVisitInput[];
	};

	export function collect(): CollectedSchedule | { ok: false; message: string } {
		if (scheduleKind === 'recurring') {
			if (asNeeded) {
				return {
					ok: true,
					job_type: 'recurring',
					is_as_needed: true,
					recurrence: null,
					visits: []
				};
			}
			if (!recurrence.start_date) {
				return { ok: false, message: 'Pick the date this schedule starts.' };
			}
			if (recurrence.frequency === 'weekly' && recurrence.weekdays.length === 0) {
				return { ok: false, message: 'Pick at least one day of the week.' };
			}
			if (recurrence.frequency === 'monthly' && !recurrence.monthly_mode) {
				return { ok: false, message: 'Choose how the monthly schedule picks its day.' };
			}
			if (recurrence.end_mode === 'after' && !recurrence.duration_count) {
				return { ok: false, message: 'Say how long this schedule runs for.' };
			}
			if (recurrence.end_mode === 'on' && !recurrence.end_date) {
				return { ok: false, message: 'Pick the date this schedule ends.' };
			}
			return {
				ok: true,
				job_type: 'recurring',
				is_as_needed: false,
				recurrence: $state.snapshot(recurrence),
				visits: []
			};
		}

		const visits: JobVisitInput[] = [];
		for (let index = 0; index < drafts.length; index++) {
			const draft = drafts[index];
			const base = {
				position: index,
				title: draft.title.trim() || null,
				instructions: draft.instructions.trim() || null,
				assignee_ids: draft.assigneeIds
			};

			if (draft.scheduleLater) {
				visits.push({
					...base,
					visit_date: null,
					start_time: null,
					end_time: null,
					all_day: false
				});
				continue;
			}

			const day = calendarDateToString(draft.when.date);
			if (!day) {
				return { ok: false, message: 'Pick a day for each visit, or tick "Schedule later".' };
			}

			if (draft.anytime) {
				visits.push({ ...base, visit_date: day, start_time: null, end_time: null, all_day: true });
				continue;
			}

			const start = timeToString(draft.when.startTime);
			const end = timeToString(draft.when.endTime);
			if (end && !start) {
				return { ok: false, message: 'Set a start time before an end time.' };
			}
			if (start && end && end <= start) {
				return { ok: false, message: 'The end time has to come after the start time.' };
			}
			visits.push({
				...base,
				visit_date: day,
				start_time: start || null,
				end_time: end || null,
				all_day: false
			});
		}
		return { ok: true, job_type: 'one_off', is_as_needed: false, recurrence: null, visits };
	}

	export function warm() {
		teamWanted = true;
	}
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<SectionBlock title="Visits" subtitle={headerHint} icon={calendarIcon} tone="time">
	{#snippet actions()}
		{#if scheduleKind === 'one_off' && drafts.length > 0}
			<Button variant="secondary" size="small" onclick={() => (creating = true)} onhover={warm}>
				<span class="job-visits__button-icon" aria-hidden="true">{@html plusIcon}</span>
				Create visits
			</Button>
		{/if}
	{/snippet}

	<div class="job-visits concept-fields">
		<div class="job-visits__kind">
			<SegmentedControl
				label="Schedule"
				value={scheduleKind}
				options={[
					{
						value: 'one_off',
						label: 'One-off',
						icon: calendarCheckIcon,
						iconColor: 'var(--color-time)'
					},
					{
						value: 'recurring',
						label: 'Recurring',
						icon: repeatIcon,
						iconColor: 'var(--color-time)'
					}
				]}
				onchange={(value) => (scheduleKind = value as 'one_off' | 'recurring')}
			/>
			<p class="job-visits__hint">
				{scheduleKind === 'recurring'
					? 'Visits on a repeating schedule, like weekly cleaning or monthly mowing.'
					: 'One visit, or a few, until the work is done.'}
			</p>
		</div>

		{#if scheduleKind === 'recurring'}
			<RecurrenceFields bind:rule={recurrence} bind:asNeeded {locale} concept />
		{:else if drafts.length === 0}
			<EmptyState
				icon={calendarIcon}
				iconLabel="Add the first visit"
				onIconClick={() => (creating = true)}
				title="No visits yet"
				description="Add the days your team will be on site. You can pick several at once."
			>
				{#snippet action()}
					<Button variant="secondary" onclick={() => (creating = true)} onhover={warm}>
						Create visits
					</Button>
				{/snippet}
			</EmptyState>
		{:else}
			<ul class="job-visits__list">
				{#each drafts as draft, index (draft.key)}
					{@const badge = dayBadge(draft)}
					{@const people = assignees(draft)}
					<li class={['job-visits__item', draft.expanded && 'job-visits__item--open']}>
						<button
							type="button"
							class="job-visits__summary"
							aria-expanded={draft.expanded}
							onclick={() => toggleExpanded(draft.key)}
						>
							<span class="job-visits__badge">
								{#if badge.weekday}<span class="job-visits__badge-weekday">{badge.weekday}</span
									>{/if}
								<span class="job-visits__badge-day">{badge.day}</span>
							</span>
							<span class="job-visits__summary-text">
								<span class="job-visits__summary-title">
									{draft.title.trim() || jobTitle.trim() || `Visit ${index + 1}`}
								</span>
								<span class="job-visits__summary-when">{whenLine(draft)}</span>
							</span>
							{#if people.length > 0}
								<span
									class="job-visits__people"
									aria-label={people.map((person) => person.name).join(', ')}
								>
									{#each people as person (person.id)}
										<Avatar id={person.id} name={person.name} size="small" />
									{/each}
								</span>
							{:else}
								<span class="job-visits__nobody">Nobody assigned yet</span>
							{/if}
							<span
								class="job-visits__chevron"
								class:job-visits__chevron--open={draft.expanded}
								aria-hidden="true"
							>
								{@html chevronDownIcon}
							</span>
						</button>

						{#if draft.expanded}
							<div class="job-visits__editor">
								<Input
									id={`visit-title-${draft.key}`}
									label="Visit title"
									placeholder="Leave blank to use the job title"
									bind:value={draft.title}
									maxlength={160}
								/>

								{#if !draft.scheduleLater}
									<DateTimePicker
										id={`visit-when-${draft.key}`}
										range
										showTime={!draft.anytime}
										dateLabel="Day of the visit"
										timeLabel="Time"
										{locale}
										bind:value={draft.when}
									/>
								{/if}

								<div class="job-visits__choices">
									{#if !draft.scheduleLater}
										<Checkbox
											id={`visit-anytime-${draft.key}`}
											label="Anytime"
											description="Tell the client the day without promising an hour."
											checked={draft.anytime}
											onchange={(checked) => setAnytime(draft.key, checked)}
										/>
									{/if}
									<Checkbox
										id={`visit-later-${draft.key}`}
										label="Schedule later"
										description="Keep this visit without a date until you know it."
										bind:checked={draft.scheduleLater}
									/>
								</div>

								<Textarea
									id={`visit-instructions-${draft.key}`}
									label="Instructions"
									rows={2}
									maxlength={2000}
									bind:value={draft.instructions}
									placeholder="Anything whoever visits needs to know before they arrive"
								/>

								<fieldset class="job-visits__team">
									<legend class="job-visits__team-title">Who is going</legend>
									{#if teamQuery.isPending}
										<p class="job-visits__hint">Loading your team…</p>
									{:else if teamQuery.isError}
										<p class="job-visits__error">
											Your team could not be loaded. You can still save the visit.
										</p>
									{:else if team.length === 0}
										<p class="job-visits__hint">Nobody else is on your team yet.</p>
									{:else}
										<ul class="job-visits__team-list">
											{#each team as member (member.id)}
												<li>
													<PersonPickChip
														id={`visit-${draft.key}-assignee-${member.id}`}
														personId={member.id}
														name={member.full_name ?? 'Unnamed team member'}
														checked={draft.assigneeIds.includes(member.id)}
														onchange={(checked) => toggleAssignee(draft.key, member.id, checked)}
													/>
												</li>
											{/each}
										</ul>
									{/if}
								</fieldset>

								<div class="job-visits__editor-actions">
									<Button
										variant="secondary"
										variation="destructive"
										size="small"
										onclick={() => removeVisit(draft.key)}
									>
										<span class="job-visits__button-icon" aria-hidden="true">{@html trashIcon}</span
										>
										Remove visit
									</Button>
								</div>
							</div>
						{/if}
					</li>
				{/each}
			</ul>
		{/if}

		{#if fieldError}
			<p class="job-visits__error" role="alert">{fieldError}</p>
		{/if}

		{@render footer?.()}
	</div>
</SectionBlock>

<CreateVisitsDialog open={creating} onClose={() => (creating = false)} onCreate={addVisits} />

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.job-visits {
		display: flex;
		flex-direction: column;
		gap: var(--space-medium);

		&__kind {
			display: flex;
			flex-direction: column;
			align-items: flex-start;
			gap: 6px;
		}

		&__button-icon {
			display: inline-flex;

			:global(svg) {
				display: block;
				width: 16px;
				height: 16px;
			}
		}

		&__list {
			display: flex;
			flex-direction: column;
			gap: var(--space-small);
			margin: 0;
			padding: 0;
			list-style: none;
		}

		&__item {
			overflow: hidden;
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-large);
		}

		&__summary {
			display: flex;
			width: 100%;
			align-items: center;
			gap: 14px;
			padding: 10px var(--space-slim);
			border: 0;
			color: inherit;
			background: var(--color-surface);
			font: inherit;
			text-align: left;
			cursor: pointer;
			transition: background-color var(--timing-quick);

			&:hover {
				background: var(--color-surface--hover);
			}
			&:focus-visible {
				outline: none;
				box-shadow: inset var(--shadow-focus);
			}
		}

		// The open visit's row takes the Schedule colour, with its date tile filled.
		&__item--open &__summary {
			background: var(--color-time--surface);
		}

		&__badge {
			display: flex;
			flex: 0 0 auto;
			flex-direction: column;
			align-items: center;
			justify-content: center;
			width: 44px;
			height: 44px;
			border-radius: var(--radius-tile-large);
			color: var(--color-time--onSurface);
			background: var(--color-time--surface);
		}

		&__item--open &__badge {
			color: var(--color-surface);
			background: var(--color-time);
		}

		&__badge-weekday {
			color: var(--color-time);
			font-size: var(--typography--fontSize-overline);
			font-weight: 600;
			line-height: 1.2;
		}

		&__item--open &__badge-weekday {
			color: inherit;
		}

		&__badge-day {
			font-size: 17px;
			font-weight: 700;
			line-height: 1.1;
		}

		&__summary-text {
			display: flex;
			min-width: 0;
			flex: 1 1 auto;
			flex-direction: column;
			gap: 2px;
		}

		&__summary-title {
			overflow: hidden;
			color: var(--color-heading);
			font-weight: 600;
			text-overflow: ellipsis;
			white-space: nowrap;
		}

		&__item--open &__summary-title {
			color: var(--color-time--onSurface);
		}

		&__summary-when {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__people {
			display: inline-flex;
			flex: 0 0 auto;

			:global(.avatar) {
				box-shadow: 0 0 0 2px var(--color-surface);
			}
			:global(.avatar + .avatar) {
				margin-left: -6px;
			}
		}

		&__nobody {
			flex: 0 0 auto;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__chevron {
			display: grid;
			flex: 0 0 auto;
			place-items: center;
			color: var(--color-icon--secondary);
			transition: transform var(--timing-quick);

			:global(svg) {
				width: 16px;
				height: 16px;
			}

			&--open {
				transform: rotate(180deg);
			}
		}

		&__editor {
			display: flex;
			flex-direction: column;
			gap: var(--space-base);
			padding: var(--space-base);
			border-top: var(--border-base) solid var(--color-border);
			background: var(--color-surface);
		}

		&__choices {
			display: flex;
			flex-direction: column;
			gap: var(--space-slim);
		}

		&__editor-actions {
			display: flex;
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
