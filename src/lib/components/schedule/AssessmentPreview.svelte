<script lang="ts">
	import type { Snippet } from 'svelte';
	import { resolve } from '$app/paths';
	import Button from '$lib/components/ui/Button.svelte';
	import StatusBadge from '$lib/components/ui/StatusBadge.svelte';
	import SchedulePreviewFacts from '$lib/components/schedule/SchedulePreviewFacts.svelte';
	import { visitDerivedStatus, visitShape } from '$lib/schedule/status';
	import { VISIT_STATUS_LABELS, VISIT_STATUS_TONES } from '$lib/schedule/statuses';
	import { assignmentLabel, clockLabel } from '$lib/schedule/labels';
	import type { AssessmentItem } from '$lib/schedule/items';
	import type { TeamMember } from '$lib/team/api';

	// What an assessment card says when you select it. Unlike a visit, the calendar never edits an assessment:
	// it is owned by its Request, and every change to it -- rescheduling, marking it done, reassigning -- lives
	// on the Request surface. So this preview reads the assessment and offers exactly one way forward: open the
	// Request it belongs to. The one exception is the reader's own timer, which is theirs rather than the
	// assessment's.

	let {
		assessment,
		today,
		dayLabel,
		headerStatus = false,
		employeesById,
		timer
	}: {
		assessment: AssessmentItem;
		today: string;
		/** The assessment's date already in words, so every surface says the date the same way. */
		dayLabel: string;
		headerStatus?: boolean;
		employeesById: Map<string, TeamMember>;
		/** The reader's own Start/Stop timer for this assessment, supplied by the page that owns the timer
		 *  query. */
		timer?: Snippet;
	} = $props();

	const status = $derived(visitDerivedStatus(assessment, today));
	const timeLabel = $derived.by(() => {
		if (visitShape(assessment) === 'anytime') return 'Anytime';
		const start = clockLabel(assessment.start_time);
		if (!start) return 'Anytime';
		const end = clockLabel(assessment.end_time);
		return end ? `${start} – ${end}` : start;
	});
	const address = $derived.by(() => {
		const street = [assessment.property_label, assessment.property_address_line1]
			.filter(Boolean)
			.join(' · ');
		const region = [assessment.property_city, assessment.property_state_region]
			.filter(Boolean)
			.join(', ');
		const line = [street, region, assessment.property_postal_code].filter(Boolean).join(' ');
		return line.length > 0 ? line : null;
	});
	const client = $derived(
		assessment.client_name ?? assessment.client_company_name ?? 'Client hidden'
	);
</script>

<div class="assessment-preview">
	{#if status && !headerStatus}
		<StatusBadge status={VISIT_STATUS_TONES[status]}>{VISIT_STATUS_LABELS[status]}</StatusBadge>
	{/if}

	<SchedulePreviewFacts
		facts={[
			{ kind: 'client', label: 'Client', value: client },
			{ kind: 'when', label: 'When', value: `${dayLabel} · ${timeLabel}` },
			{
				kind: 'team',
				label: 'Team',
				people: assessment.assignee_ids
					.slice(0, 3)
					.map((id) => employeesById.get(id)?.full_name ?? 'One employee'),
				value: assignmentLabel(assessment.assignee_ids, employeesById),
				warn: assessment.assignee_ids.length === 0
			},
			{ kind: 'where', label: 'Where', value: address ?? 'No property on this assessment' }
		]}
	/>

	{#if timer}
		<!-- Time clock: a crew member's first action on arrival, so it sits above the way to the Request. -->
		<div class="assessment-preview__timer">{@render timer()}</div>
	{/if}

	<!-- The assessment is Request-owned, so the calendar shows it but never edits it. The one way forward is
	     its Request, where it is scheduled, reassigned or marked done. -->
	<div class="assessment-preview__actions">
		<Button
			variant="quiet"
			size="small"
			href={resolve('/(app)/requests/[id=uuid]', { id: assessment.request_id })}
		>
			Open request
		</Button>
	</div>
</div>

<style lang="scss">
	.assessment-preview {
		display: flex;
		flex-direction: column;
		align-items: flex-start;
		gap: var(--space-base);
		min-width: 260px;
	}

	// The timer panel draws its own box (time-clock.md); this only gives it the column's width.
	.assessment-preview__timer {
		width: 100%;
	}

	.assessment-preview__actions {
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-small);
		box-sizing: border-box;
		width: calc(100% + var(--space-medium) * 2);
		margin: 0 calc(-1 * var(--space-medium)) calc(-1 * var(--space-medium));
		padding: var(--space-small) var(--space-slim);
		background: var(--color-surface--background--subtle);
		border-top: var(--border-base) solid var(--color-border);
	}
</style>
