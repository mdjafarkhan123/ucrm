<script lang="ts">
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import { page } from '$app/state';
	import SectionBlock from '$lib/components/layout/SectionBlock.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Toggle from '$lib/components/ui/Toggle.svelte';
	import TimePicker from '$lib/components/ui/TimePicker.svelte';
	import CalendarPicker from '$lib/components/ui/CalendarPicker.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import {
		calendarDateToString,
		timeFromString,
		timeToString,
		type TimeRangeValue
	} from '$lib/components/ui/date-time';
	import type { CalendarDate } from '@internationalized/date';
	import { WEEKDAY_LABELS } from '$lib/settings/api';
	import {
		deleteMemberAvailabilityException,
		fetchMemberAvailability,
		saveMemberAvailabilityException,
		saveMemberWeeklyAvailability,
		teamMemberAvailabilityKey,
		TeamWriteError,
		type AvailabilityDay,
		type MemberAvailabilityEditor
	} from '$lib/team/api';
	import calendarIcon from '@tabler/icons/outline/calendar-time.svg?raw';
	import trashIcon from '@tabler/icons/outline/trash.svg?raw';

	let { userId }: { userId: string } = $props();

	const queryClient = useQueryClient();
	const toast = getToastManager();
	const actorUserId = $derived(page.data.user?.id ?? '');

	// Rule 10: this section does not load with the page. The query stays off until the control is hovered
	// or clicked, and a skeleton covers the gap if the click beats the prefetch.
	let revealed = $state(false);

	const availabilityQuery = createQuery(() => ({
		queryKey: teamMemberAvailabilityKey(actorUserId, userId),
		queryFn: () => fetchMemberAvailability(userId),
		enabled: revealed && Boolean(actorUserId),
		staleTime: 30_000
	}));
	const availability = $derived(availabilityQuery.data);
	const canEdit = $derived(Boolean(availability?.can_edit));
	const editingSelf = $derived(actorUserId === userId);

	type DayDraft = { isWorking: boolean; hours: TimeRangeValue };

	let weekDraft = $state<DayDraft[] | null>(null);
	let savingWeek = $state(false);
	let weekError = $state('');
	let stale = $state(false);

	let addingDate = $state(false);
	let exceptionDate = $state<CalendarDate | undefined>(undefined);
	let exceptionWorking = $state(false);
	let exceptionHours = $state<TimeRangeValue>({
		start: timeFromString('09:00'),
		end: timeFromString('13:00')
	});
	let exceptionReason = $state('');
	let savingException = $state(false);
	let exceptionError = $state('');
	let removingId = $state('');

	// A blank week is every day off. Somebody who opens an unset pattern builds it up rather than turning a
	// nine-to-five they never agreed to back off again.
	function blankWeek(): DayDraft[] {
		return [0, 1, 2, 3, 4, 5, 6].map(() => ({
			isWorking: false,
			hours: { start: undefined, end: undefined }
		}));
	}

	function weekFrom(pattern: AvailabilityDay[]): DayDraft[] {
		const draft = blankWeek();
		for (const day of pattern) {
			if (day.weekday < 0 || day.weekday > 6) continue;
			draft[day.weekday] = {
				isWorking: day.is_working,
				hours: { start: timeFromString(day.starts_at), end: timeFromString(day.ends_at) }
			};
		}
		return draft;
	}

	function beginWeekEdit(source: MemberAvailabilityEditor) {
		weekError = '';
		stale = false;
		weekDraft = source.pattern.length > 0 ? weekFrom(source.pattern) : blankWeek();
	}

	function useWeekdaySuggestion() {
		const draft = blankWeek();
		for (const weekday of [1, 2, 3, 4, 5]) {
			draft[weekday] = {
				isWorking: true,
				hours: { start: timeFromString('08:00'), end: timeFromString('17:00') }
			};
		}
		weekDraft = draft;
	}

	function cancelWeekEdit() {
		weekDraft = null;
		weekError = '';
	}

	async function prefetch() {
		if (!actorUserId || revealed) return;
		await queryClient.prefetchQuery({
			queryKey: teamMemberAvailabilityKey(actorUserId, userId),
			queryFn: () => fetchMemberAvailability(userId)
		});
	}

	async function refresh() {
		await queryClient.invalidateQueries({
			queryKey: teamMemberAvailabilityKey(actorUserId, userId)
		});
	}

	async function reloadLatest() {
		stale = false;
		weekDraft = null;
		await refresh();
	}

	async function saveWeek() {
		if (!availability || !weekDraft) return;

		// Every working day needs both ends. Saying so here means the row that is wrong keeps its own
		// message instead of the whole week failing on a database error.
		const incomplete = weekDraft.some(
			(day) => day.isWorking && (!day.hours.start || !day.hours.end)
		);
		if (incomplete) {
			weekError = 'Every working day needs a start and a finish.';
			return;
		}
		const backwards = weekDraft.some(
			(day) =>
				day.isWorking &&
				day.hours.start &&
				day.hours.end &&
				(timeToString(day.hours.end) ?? '') <= (timeToString(day.hours.start) ?? '')
		);
		if (backwards) {
			weekError = 'A day has to finish after it starts.';
			return;
		}

		const pattern: AvailabilityDay[] = weekDraft.map((day, weekday) => ({
			weekday,
			is_working: day.isWorking,
			starts_at: day.isWorking ? (timeToString(day.hours.start) ?? null) : null,
			ends_at: day.isWorking ? (timeToString(day.hours.end) ?? null) : null
		}));

		savingWeek = true;
		weekError = '';
		try {
			await saveMemberWeeklyAvailability(userId, {
				pattern,
				expected_availability_revision: availability.availability_revision
			});
			weekDraft = null;
			toast.success('Working week saved.');
			await refresh();
		} catch (reason) {
			stale = reason instanceof TeamWriteError && reason.stale;
			weekError =
				reason instanceof Error ? reason.message : 'That working week could not be saved.';
		} finally {
			savingWeek = false;
		}
	}

	// Clearing says "nobody has set when this person works", which is not the same as a week of days off:
	// the calendar warns about the second and stays quiet about the first.
	async function clearWeek() {
		if (!availability) return;
		savingWeek = true;
		weekError = '';
		try {
			await saveMemberWeeklyAvailability(userId, {
				pattern: [],
				expected_availability_revision: availability.availability_revision
			});
			weekDraft = null;
			toast.success('Working week cleared.');
			await refresh();
		} catch (reason) {
			stale = reason instanceof TeamWriteError && reason.stale;
			weekError =
				reason instanceof Error ? reason.message : 'That working week could not be cleared.';
		} finally {
			savingWeek = false;
		}
	}

	function beginAddDate() {
		addingDate = true;
		exceptionDate = undefined;
		exceptionWorking = false;
		exceptionHours = { start: timeFromString('09:00'), end: timeFromString('13:00') };
		exceptionReason = '';
		exceptionError = '';
	}

	async function saveException() {
		if (!availability) return;
		const day = calendarDateToString(exceptionDate);
		if (!day) {
			exceptionError = 'Pick a date.';
			return;
		}
		if (exceptionWorking && (!exceptionHours.start || !exceptionHours.end)) {
			exceptionError = 'Say which hours are worked that day.';
			return;
		}

		savingException = true;
		exceptionError = '';
		try {
			await saveMemberAvailabilityException(userId, {
				exception_date: day,
				is_working: exceptionWorking,
				starts_at: exceptionWorking ? (timeToString(exceptionHours.start) ?? null) : null,
				ends_at: exceptionWorking ? (timeToString(exceptionHours.end) ?? null) : null,
				reason: exceptionReason,
				expected_availability_revision: availability.availability_revision
			});
			addingDate = false;
			toast.success('Date saved.');
			await refresh();
		} catch (reason) {
			stale = reason instanceof TeamWriteError && reason.stale;
			exceptionError = reason instanceof Error ? reason.message : 'That date could not be saved.';
		} finally {
			savingException = false;
		}
	}

	async function removeException(exceptionId: string) {
		if (!availability) return;
		removingId = exceptionId;
		exceptionError = '';
		try {
			await deleteMemberAvailabilityException(userId, {
				exception_id: exceptionId,
				expected_availability_revision: availability.availability_revision
			});
			toast.success('Date removed.');
			await refresh();
		} catch (reason) {
			stale = reason instanceof TeamWriteError && reason.stale;
			exceptionError = reason instanceof Error ? reason.message : 'That date could not be removed.';
		} finally {
			removingId = '';
		}
	}

	function dayLabel(day: AvailabilityDay): string {
		if (!day.is_working) return 'Not working';
		return `${clockLabel(day.starts_at)} – ${clockLabel(day.ends_at)}`;
	}

	function clockLabel(value: string | null): string {
		return value ? value.slice(0, 5) : '';
	}

	function longDate(value: string): string {
		const parsed = new Date(`${value}T00:00:00Z`);
		return Number.isNaN(parsed.getTime())
			? value
			: parsed.toLocaleDateString(undefined, {
					weekday: 'short',
					day: 'numeric',
					month: 'short',
					year: 'numeric',
					timeZone: 'UTC'
				});
	}
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<SectionBlock title="Availability" icon={calendarIcon} level={2}>
	{#snippet actions()}
		{#if !revealed}
			<Button
				variant="secondary"
				variation="subtle"
				size="small"
				onhover={() => void prefetch()}
				onclick={() => (revealed = true)}
			>
				Manage availability
			</Button>
		{/if}
	{/snippet}

	{#if !revealed}
		<p class="member-availability__summary">
			Open this section to set when {editingSelf ? 'you work' : 'this person works'}, and to book
			time off.
		</p>
	{:else if availabilityQuery.isPending}
		<LoadingSkeleton variant="card" label="Loading availability" rows={3} />
	{:else if availabilityQuery.isError}
		<ErrorState
			description="That person’s availability could not be loaded."
			retry={() => availabilityQuery.refetch()}
		/>
	{:else if availability}
		{#if stale}
			<div class="member-availability__conflict" role="alert">
				<p>Someone else changed this availability while you were editing.</p>
				<button type="button" onclick={() => void reloadLatest()}>Reload latest availability</button
				>
			</div>
		{/if}

		{#if !canEdit}
			<p class="member-availability__summary">
				Only an owner or administrator can change someone else’s availability.
			</p>
		{/if}

		<section class="member-availability__section" aria-labelledby="member-week-heading">
			<div class="member-availability__section-header">
				<div>
					<h3 id="member-week-heading">Working week</h3>
					<p>
						Business hours say when the company is open. This says when {editingSelf
							? 'you work'
							: 'this person works'}.
					</p>
				</div>
				{#if canEdit && !weekDraft}
					<Button
						variant="secondary"
						variation="subtle"
						size="small"
						onclick={() => beginWeekEdit(availability)}
					>
						{availability.pattern.length > 0 ? 'Change hours' : 'Set hours'}
					</Button>
				{/if}
			</div>

			{#if weekError}<p class="member-availability__error" role="alert">{weekError}</p>{/if}

			{#if weekDraft}
				<div class="member-availability__week">
					{#each weekDraft as day, weekday (weekday)}
						<div class="member-availability__day">
							<div class="member-availability__day-header">
								<span class="member-availability__day-name">{WEEKDAY_LABELS[weekday]}</span>
								<Toggle
									id={`availability-working-${weekday}`}
									label={day.isWorking ? 'Working' : 'Not working'}
									checked={day.isWorking}
									disabled={savingWeek}
									onchange={(checked) => {
										if (!weekDraft) return;
										weekDraft[weekday].isWorking = checked;
										if (checked && !weekDraft[weekday].hours.start) {
											weekDraft[weekday].hours = {
												start: timeFromString('08:00'),
												end: timeFromString('17:00')
											};
										}
									}}
								/>
							</div>
							{#if day.isWorking}
								<TimePicker
									bind:value={weekDraft[weekday].hours}
									range
									label={`${WEEKDAY_LABELS[weekday]} hours`}
									disabled={savingWeek}
								/>
							{/if}
						</div>
					{/each}
				</div>

				<div class="member-availability__week-actions">
					<Button onclick={() => void saveWeek()} disabled={savingWeek}>
						{savingWeek ? 'Saving…' : 'Save working week'}
					</Button>
					<Button variant="secondary" onclick={cancelWeekEdit} disabled={savingWeek}>Cancel</Button>
					<Button variant="tertiary" onclick={useWeekdaySuggestion} disabled={savingWeek}>
						Use Monday–Friday, 8am–5pm
					</Button>
				</div>
			{:else if availability.pattern.length === 0}
				<p class="member-availability__empty">
					No working week set. The calendar will not warn anybody about {editingSelf
						? 'your'
						: 'their'} hours until one is.
				</p>
			{:else}
				<dl class="member-availability__readout">
					{#each availability.pattern as day (day.weekday)}
						<div class="member-availability__readout-row" class:is-off={!day.is_working}>
							<dt>{WEEKDAY_LABELS[day.weekday]}</dt>
							<dd>{dayLabel(day)}</dd>
						</div>
					{/each}
				</dl>
				{#if canEdit}
					<Button
						variant="tertiary"
						size="small"
						onclick={() => void clearWeek()}
						disabled={savingWeek}
					>
						Clear working week
					</Button>
				{/if}
			{/if}
		</section>

		<section class="member-availability__section" aria-labelledby="member-time-off-heading">
			<div class="member-availability__section-header">
				<div>
					<h3 id="member-time-off-heading">Time off and one-off changes</h3>
					<p>Leave, training, or a day worked to different hours. These beat the working week.</p>
				</div>
				{#if canEdit && !addingDate}
					<Button variant="secondary" variation="subtle" size="small" onclick={beginAddDate}>
						Add a date
					</Button>
				{/if}
			</div>

			{#if exceptionError}<p class="member-availability__error" role="alert">
					{exceptionError}
				</p>{/if}

			{#if addingDate}
				<div class="member-availability__date-form">
					<CalendarPicker
						id="availability-exception-date"
						bind:value={exceptionDate}
						label="Date"
						disabled={savingException}
					/>
					<Toggle
						id="availability-exception-working"
						label={exceptionWorking ? 'Working different hours' : 'Not working that day'}
						bind:checked={exceptionWorking}
						disabled={savingException}
					/>
					{#if exceptionWorking}
						<TimePicker
							bind:value={exceptionHours}
							range
							label="Hours that day"
							disabled={savingException}
						/>
					{/if}
					<Input
						id="availability-exception-reason"
						label="Reason"
						placeholder="Annual leave"
						bind:value={exceptionReason}
						maxlength={120}
						disabled={savingException}
					/>
					<div class="member-availability__date-actions">
						<Button onclick={() => void saveException()} disabled={savingException}>
							{savingException ? 'Saving…' : 'Save date'}
						</Button>
						<Button
							variant="secondary"
							onclick={() => (addingDate = false)}
							disabled={savingException}
						>
							Cancel
						</Button>
					</div>
				</div>
			{/if}

			{#if availability.exceptions.length === 0}
				<p class="member-availability__empty">No upcoming time off.</p>
			{:else}
				<ul class="member-availability__dates">
					{#each availability.exceptions as entry (entry.id)}
						<li class="member-availability__date">
							<div class="member-availability__date-main">
								<span class="member-availability__date-day">{longDate(entry.exception_date)}</span>
								<span class="member-availability__date-detail">
									{entry.is_working
										? `Working ${clockLabel(entry.starts_at)} – ${clockLabel(entry.ends_at)}`
										: 'Not working'}{entry.reason ? ` · ${entry.reason}` : ''}
								</span>
							</div>
							{#if canEdit}
								<button
									type="button"
									class="member-availability__remove"
									aria-label={`Remove ${longDate(entry.exception_date)}`}
									disabled={removingId === entry.id}
									onclick={() => void removeException(entry.id)}
								>
									{@html trashIcon}
								</button>
							{/if}
						</li>
					{/each}
				</ul>
			{/if}
		</section>
	{/if}
</SectionBlock>

<style lang="scss">
	.member-availability {
		&__summary,
		&__empty {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__section {
			display: flex;
			flex-direction: column;
			gap: var(--space-base);
			padding-top: var(--space-base);
			border-top: var(--border-base) solid var(--color-border);

			&:first-of-type {
				padding-top: 0;
				border-top: none;
			}
		}

		&__section-header {
			display: flex;
			align-items: flex-start;
			justify-content: space-between;
			gap: var(--space-base);

			h3 {
				margin: 0;
				color: var(--color-heading);
				font-size: var(--typography--fontSize-base);
				font-weight: 700;
			}

			p {
				margin: var(--space-slimmer) 0 0;
				color: var(--color-text--secondary);
				font-size: var(--typography--fontSize-small);
			}
		}

		&__error {
			margin: 0;
			color: var(--danger-text);
			font-size: var(--typography--fontSize-small);
		}

		&__conflict {
			display: flex;
			flex-wrap: wrap;
			align-items: center;
			gap: var(--space-small);
			padding: var(--space-small) var(--space-base);
			border: var(--border-base) solid var(--warning-border);
			border-radius: var(--radius-base);
			background: var(--warning-surface);

			p {
				margin: 0;
				color: var(--warning-text);
				font-size: var(--typography--fontSize-small);
			}

			button {
				border: none;
				background: none;
				color: var(--color-brand);
				font: inherit;
				font-weight: 600;
				cursor: pointer;

				&:hover {
					text-decoration: underline;
				}
			}
		}

		&__week {
			display: flex;
			flex-direction: column;
			gap: var(--space-small);
		}

		&__day {
			display: flex;
			flex-direction: column;
			gap: var(--space-small);
			padding: var(--space-small) var(--space-base);
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-base);
			background: var(--color-surface--background);
		}

		&__day-header {
			display: flex;
			align-items: center;
			justify-content: space-between;
			gap: var(--space-base);
		}

		&__day-name {
			color: var(--color-text--primary);
			font-size: var(--typography--fontSize-small);
			font-weight: 600;
		}

		&__week-actions,
		&__date-actions {
			display: flex;
			flex-wrap: wrap;
			gap: var(--space-small);
		}

		&__readout {
			display: flex;
			flex-direction: column;
			gap: var(--space-slimmer);
			margin: 0;
		}

		&__readout-row {
			display: flex;
			align-items: baseline;
			justify-content: space-between;
			gap: var(--space-base);
			padding: var(--space-slimmer) 0;
			border-bottom: var(--border-base) solid var(--color-border--subtle);

			&:last-child {
				border-bottom: none;
			}

			dt {
				color: var(--color-text--primary);
				font-size: var(--typography--fontSize-small);
				font-weight: 600;
			}

			dd {
				margin: 0;
				color: var(--color-text--secondary);
				font-size: var(--typography--fontSize-small);
				font-variant-numeric: tabular-nums;
			}

			&.is-off dd {
				color: var(--color-text--tertiary);
			}
		}

		&__date-form {
			display: flex;
			flex-direction: column;
			gap: var(--space-base);
			padding: var(--space-base);
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-base);
			background: var(--color-surface--background);
		}

		&__dates {
			display: flex;
			flex-direction: column;
			gap: var(--space-slimmer);
			margin: 0;
			padding: 0;
			list-style: none;
		}

		&__date {
			display: flex;
			align-items: center;
			justify-content: space-between;
			gap: var(--space-base);
			padding: var(--space-small) var(--space-base);
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-base);
		}

		&__date-main {
			display: flex;
			flex-direction: column;
			gap: 2px;
			min-width: 0;
		}

		&__date-day {
			color: var(--color-text--primary);
			font-size: var(--typography--fontSize-small);
			font-weight: 600;
		}

		&__date-detail {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__remove {
			display: inline-flex;
			align-items: center;
			justify-content: center;
			flex-shrink: 0;
			width: 32px;
			height: 32px;
			padding: 0;
			border: var(--border-base) solid transparent;
			border-radius: var(--radius-base);
			background: none;
			color: var(--color-icon--secondary);
			cursor: pointer;

			:global(svg) {
				width: 18px;
				height: 18px;
			}

			&:hover:not(:disabled) {
				border-color: var(--danger-border);
				background: var(--danger-surface);
				color: var(--danger-text);
			}

			&:focus-visible {
				outline: 2px solid var(--color-brand);
				outline-offset: 2px;
			}

			&:disabled {
				opacity: 0.5;
				cursor: not-allowed;
			}
		}
	}

	@media (max-width: 640px) {
		.member-availability__section-header {
			flex-direction: column;
		}
	}
</style>
