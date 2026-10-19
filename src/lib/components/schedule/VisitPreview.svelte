<script lang="ts">
	import type { Snippet } from 'svelte';
	import { resolve } from '$app/paths';
	import Button from '$lib/components/ui/Button.svelte';
	import StatusBadge from '$lib/components/ui/StatusBadge.svelte';
	import SchedulePreviewFacts from '$lib/components/schedule/SchedulePreviewFacts.svelte';
	import checkIcon from '@tabler/icons/outline/check.svg?raw';
	import arrowUpRightIcon from '@tabler/icons/outline/arrow-up-right.svg?raw';
	import { visitDerivedStatus } from '$lib/schedule/status';
	import { VISIT_STATUS_LABELS, VISIT_STATUS_TONES } from '$lib/schedule/statuses';
	import { visitAddressLabel, visitAssignmentLabel, visitTimeLabel } from '$lib/schedule/labels';
	import type { ScheduleVisit } from '$lib/schedule/api';
	import type { TeamMember } from '$lib/team/api';

	// What a card says when you select it: enough to act on the visit without leaving the calendar, and
	// nothing more. It is deliberately not a small copy of the Job page -- the way to the whole record is
	// the link at the bottom. The client's name and the work sit in the popover's own heading, above this.

	let {
		visit,
		today,
		dayLabel,
		headerStatus = false,
		employeesById,
		canSchedule = false,
		canComplete = false,
		completing = false,
		onreschedule,
		onunschedule,
		oncomplete,
		onuncomplete,
		timer
	}: {
		visit: ScheduleVisit;
		today: string;
		/** The visit's date already in words, so every surface says the date the same way. */
		dayLabel: string;
		headerStatus?: boolean;
		employeesById: Map<string, TeamMember>;
		/** Whether this reader may change the schedule. A completed visit is never rescheduled. */
		canSchedule?: boolean;
		/** Whether this reader holds the Jobs completion authority. Without it the control is absent. */
		canComplete?: boolean;
		/** True while this visit's own complete/uncomplete write is in flight. */
		completing?: boolean;
		onreschedule: () => void;
		/** Send a dated visit back to the Unscheduled backlog. The page confirms before it clears the date. */
		onunschedule?: () => void;
		/** Mark the visit complete through the Jobs-owned command. Absent for a reader without the authority. */
		oncomplete?: () => void;
		/** Clear the visit's completion through the Jobs-owned command. */
		onuncomplete?: () => void;
		/** The reader's own Start/Stop timer for this visit, supplied by the page that owns the timer query. */
		timer?: Snippet;
	} = $props();

	const status = $derived(visitDerivedStatus(visit, today));
	const address = $derived(visitAddressLabel(visit));
</script>

<!-- The arrow is a Tabler SVG file imported at build time, not user content. -->
<!-- eslint-disable svelte/no-at-html-tags -->
<div class="visit-preview">
	{#if status && !headerStatus}
		<StatusBadge status={VISIT_STATUS_TONES[status]}>{VISIT_STATUS_LABELS[status]}</StatusBadge>
	{/if}

	<SchedulePreviewFacts
		facts={[
			{ kind: 'when', label: 'When', value: `${dayLabel} · ${visitTimeLabel(visit)}` },
			{
				kind: 'team',
				label: 'Team',
				people: visit.assignee_ids
					.slice(0, 3)
					.map((id) => employeesById.get(id)?.full_name ?? 'One employee'),
				value: visitAssignmentLabel(visit, employeesById),
				warn: visit.assignee_ids.length === 0
			},
			{ kind: 'where', label: 'Where', value: address ?? 'No property on this visit' }
		]}
	/>

	{#if timer}
		<!-- Time clock: a crew member's first action on arrival, so it sits above the dispatch actions. -->
		<div class="visit-preview__timer">{@render timer()}</div>
	{/if}

	<div class="visit-preview__actions">
		<!-- Completion is the Jobs-owned command, presented here and written through /api/jobs. Marking done is
		     the headline dispatch action, so it leads; reopening is an undo, so it is quiet. -->
		{#if canComplete && !visit.completed_at && oncomplete}
			<Button size="small" onclick={oncomplete} loading={completing}
				>{@html checkIcon}Mark complete</Button
			>
		{/if}
		{#if canComplete && visit.completed_at && onuncomplete}
			<Button variant="tertiary" size="small" onclick={onuncomplete} loading={completing}>
				Mark incomplete
			</Button>
		{/if}
		<!-- Every change a drag can make is reachable here too, with the keyboard, through the same Jobs
		     form the Job page uses. -->
		{#if canSchedule && !visit.completed_at}
			<Button variant="secondary" size="small" onclick={onreschedule} disabled={completing}
				>Reschedule</Button
			>
		{/if}
	</div>

	<div class="visit-preview__links">
		<Button
			variant="quiet"
			size="small"
			href={resolve('/(app)/jobs/[id=uuid]', { id: visit.job_id })}
		>
			Open job{visit.job_number ? ` #${visit.job_number}` : ''}
			{@html arrowUpRightIcon}
		</Button>
		<!-- Take a placed visit off the calendar and back into the backlog. Absent for an already-unscheduled
		     visit, which has no date to clear. -->
		{#if canSchedule && !visit.completed_at && visit.visit_date && onunschedule}
			<Button variant="quiet" size="small" onclick={onunschedule} disabled={completing}
				>Move to Unscheduled</Button
			>
		{/if}
	</div>
</div>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.visit-preview {
		display: flex;
		flex-direction: column;
		align-items: flex-start;
		gap: var(--space-base);
		min-width: 260px;
	}

	.visit-preview__timer {
		width: 100%;
		box-sizing: border-box;
		padding: var(--space-slim) var(--space-slim) var(--space-slim) 14px;
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface--background--subtle);
	}

	.visit-preview__actions {
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-small);
		width: 100%;

		:global(.button) {
			flex: 1;
		}
	}

	.visit-preview__links {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-small) var(--space-base);
		box-sizing: border-box;
		width: calc(100% + var(--space-medium) * 2);
		margin: 0 calc(-1 * var(--space-medium)) calc(-1 * var(--space-medium));
		padding: var(--space-small) var(--space-slim);
		background: var(--color-surface--background--subtle);
		border-top: var(--border-base) solid var(--color-border);
	}
</style>
