<script lang="ts">
	import { resolve } from '$app/paths';
	import Button from '$lib/components/ui/Button.svelte';
	import StatusBadge from '$lib/components/ui/StatusBadge.svelte';
	import { visitDerivedStatus, visitShape } from '$lib/schedule/status';
	import { VISIT_STATUS_LABELS, VISIT_STATUS_TONES } from '$lib/schedule/statuses';
	import { assignmentLabel, clockLabel } from '$lib/schedule/labels';
	import type { AssessmentItem } from '$lib/schedule/items';
	import type { TeamMember } from '$lib/team/api';

	// What an assessment card says when you select it. Unlike a visit, the calendar never edits an assessment:
	// it is owned by its Request, and every change to it -- rescheduling, marking it done, reassigning -- lives
	// on the Request surface. So this preview reads the assessment and offers exactly one way forward: open the
	// Request it belongs to.

	let {
		assessment,
		today,
		dayLabel,
		employeesById
	}: {
		assessment: AssessmentItem;
		today: string;
		/** The assessment's date already in words, so every surface says the date the same way. */
		dayLabel: string;
		employeesById: Map<string, TeamMember>;
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
	<p class="assessment-preview__kind">On-site assessment</p>
	<p class="assessment-preview__work">{assessment.request_title?.trim() || 'Assessment'}</p>

	{#if status}
		<StatusBadge status={VISIT_STATUS_TONES[status]}>{VISIT_STATUS_LABELS[status]}</StatusBadge>
	{/if}

	<dl class="assessment-preview__facts">
		<dt>Client</dt>
		<dd>{client}</dd>

		<dt>When</dt>
		<dd>{dayLabel} · {timeLabel}</dd>

		<dt>Team</dt>
		<dd class:assessment-preview__none={assessment.assignee_ids.length === 0}>
			{assignmentLabel(assessment.assignee_ids, employeesById)}
		</dd>

		<dt>Where</dt>
		<dd>{address ?? 'No property on this assessment'}</dd>
	</dl>

	<!-- The assessment is Request-owned, so the calendar shows it but never edits it. The one way forward is
	     its Request, where it is scheduled, reassigned or marked done. -->
	<div class="assessment-preview__actions">
		<Button
			variant="secondary"
			size="small"
			href={resolve('/(app)/requests/[id]', { id: assessment.request_id })}
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
		gap: var(--space-slim);
	}

	.assessment-preview__kind {
		margin: 0;
		color: var(--color-request--onSurface);
		font-size: var(--typography--fontSize-smaller);
		font-weight: 700;
		text-transform: uppercase;
		letter-spacing: var(--typography--letterSpacing-loose);
	}

	.assessment-preview__work {
		margin: 0;
		color: var(--color-text);
		font-size: var(--typography--fontSize-base);
		line-height: var(--typography--lineHeight-base);
	}

	.assessment-preview__facts {
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

	.assessment-preview__actions {
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-small);
	}

	.assessment-preview__none {
		color: var(--color-warning--onSurface);
		font-weight: 700;
	}
</style>
