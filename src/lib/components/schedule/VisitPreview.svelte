<script lang="ts">
	import { resolve } from '$app/paths';
	import Button from '$lib/components/ui/Button.svelte';
	import StatusBadge from '$lib/components/ui/StatusBadge.svelte';
	import { visitDerivedStatus } from '$lib/schedule/status';
	import { VISIT_STATUS_LABELS, VISIT_STATUS_TONES } from '$lib/schedule/statuses';
	import {
		visitAddressLabel,
		visitAssignmentLabel,
		visitTimeLabel,
		visitWorkLabel
	} from '$lib/schedule/labels';
	import type { ScheduleVisit } from '$lib/schedule/api';
	import type { TeamMember } from '$lib/team/api';

	// What a card says when you select it: enough to act on the visit without leaving the calendar, and
	// nothing more. It is deliberately not a small copy of the Job page -- the way to the whole record is
	// the button at the bottom.

	let {
		visit,
		today,
		dayLabel,
		employeesById,
		canSchedule = false,
		canComplete = false,
		completing = false,
		onreschedule,
		onunschedule,
		oncomplete,
		onuncomplete
	}: {
		visit: ScheduleVisit;
		today: string;
		/** The visit's date already in words, so every surface says the date the same way. */
		dayLabel: string;
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
	} = $props();

	const status = $derived(visitDerivedStatus(visit, today));
	const address = $derived(visitAddressLabel(visit));
</script>

<div class="visit-preview">
	<p class="visit-preview__work">{visitWorkLabel(visit)}</p>

	{#if status}
		<StatusBadge status={VISIT_STATUS_TONES[status]}>{VISIT_STATUS_LABELS[status]}</StatusBadge>
	{/if}

	<dl class="visit-preview__facts">
		<dt>When</dt>
		<dd>{dayLabel} · {visitTimeLabel(visit)}</dd>

		<dt>Team</dt>
		<dd class:visit-preview__none={visit.assignee_ids.length === 0}>
			{visitAssignmentLabel(visit, employeesById)}
		</dd>

		<dt>Where</dt>
		<dd>{address ?? 'No property on this visit'}</dd>
	</dl>

	<div class="visit-preview__actions">
		<!-- Completion is the Jobs-owned command, presented here and written through /api/jobs. Marking done is
		     the headline dispatch action, so it leads; reopening is an undo, so it is quiet. -->
		{#if canComplete && !visit.completed_at && oncomplete}
			<Button size="small" onclick={oncomplete} loading={completing}>Mark complete</Button>
		{/if}
		{#if canComplete && visit.completed_at && onuncomplete}
			<Button variant="tertiary" size="small" onclick={onuncomplete} loading={completing}>
				Mark incomplete
			</Button>
		{/if}
		<!-- Every change a drag can make is reachable here too, with the keyboard, through the same Jobs
		     form the Job page uses. -->
		{#if canSchedule && !visit.completed_at}
			<Button variant="secondary" size="small" onclick={onreschedule}>Reschedule</Button>
		{/if}
		<!-- Take a placed visit off the calendar and back into the backlog. Absent for an already-unscheduled
		     visit, which has no date to clear. -->
		{#if canSchedule && !visit.completed_at && visit.visit_date && onunschedule}
			<Button variant="tertiary" size="small" onclick={onunschedule}>Move to Unscheduled</Button>
		{/if}
		<Button
			variant="secondary"
			size="small"
			href={resolve('/(app)/jobs/[id]', { id: visit.job_id })}
		>
			Open job{visit.job_number ? ` #${visit.job_number}` : ''}
		</Button>
	</div>
</div>

<style lang="scss">
	.visit-preview {
		display: flex;
		flex-direction: column;
		align-items: flex-start;
		gap: var(--space-slim);
	}

	.visit-preview__work {
		color: var(--color-text);
		font-size: var(--typography--fontSize-base);
		line-height: var(--typography--lineHeight-base);
	}

	.visit-preview__facts {
		display: grid;
		grid-template-columns: auto minmax(0, 1fr);
		gap: var(--space-smaller) var(--space-slim);
		margin: 0;
		width: 100%;

		dt {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			line-height: var(--typography--lineHeight-tighter);
		}

		dd {
			margin: 0;
			color: var(--color-text);
			font-size: var(--typography--fontSize-small);
			line-height: var(--typography--lineHeight-tighter);
			overflow-wrap: anywhere;
		}
	}

	.visit-preview__actions {
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-small);
	}

	.visit-preview__none {
		color: var(--color-warning--onSurface);
		font-weight: 700;
	}
</style>
