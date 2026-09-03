<script lang="ts">
	import { visitDerivedStatus, visitShape } from '$lib/schedule/status';
	import { VISIT_STATUS_LABELS } from '$lib/schedule/statuses';
	import { assignmentLabel, clockLabel } from '$lib/schedule/labels';
	import type { CardDensity } from '$lib/schedule/layout';
	import type { AssessmentItem } from '$lib/schedule/items';
	import type { TeamMember } from '$lib/team/api';
	import truckIcon from '@tabler/icons/outline/truck.svg?raw';

	// One on-site assessment, drawn at whatever size the calendar could give it.
	//
	// It mirrors the visit card's shape so a day reads as one calendar, but it is a different object with a
	// different owner: it wears the Request accent, never carries a drag or resize handle, and its click opens
	// the Request rather than a visit editor. Colour alone never carries the difference -- the accessible label
	// and, where there is room, a marker both say "Assessment".

	let {
		assessment,
		density,
		today,
		employeesById,
		selected = false,
		showAssignment = true,
		onselect
	}: {
		assessment: AssessmentItem;
		density: CardDensity;
		today: string;
		employeesById: Map<string, TeamMember>;
		selected?: boolean;
		/** False where the surface itself already says who is going, as the Day board's employee row does. */
		showAssignment?: boolean;
		/** The element is handed back so the page can anchor the preview to this exact card. */
		onselect: (assessment: AssessmentItem, element: HTMLElement) => void;
	} = $props();

	const status = $derived(visitDerivedStatus(assessment, today));

	const timeLabel = $derived.by(() => {
		if (visitShape(assessment) === 'anytime') return 'Anytime';
		const start = clockLabel(assessment.start_time);
		if (!start) return 'Anytime';
		const end = clockLabel(assessment.end_time);
		return end ? `${start} – ${end}` : start;
	});
	const startLabel = $derived(
		visitShape(assessment) === 'anytime' ? 'Anytime' : (clockLabel(assessment.start_time) ?? 'Anytime')
	);

	const clientLabel = $derived(
		assessment.client_name ?? assessment.client_company_name ?? 'Client hidden'
	);
	const workLabel = $derived(assessment.request_title?.trim() || 'Assessment');
	const place = $derived(
		[assessment.property_label, assessment.property_address_line1, assessment.property_city]
			.filter((part): part is string => Boolean(part))
			.join(' · ') || null
	);

	const summary = $derived(
		[
			'Assessment',
			timeLabel,
			clientLabel,
			workLabel,
			assignmentLabel(assessment.assignee_ids, employeesById),
			status ? VISIT_STATUS_LABELS[status] : null
		]
			.filter(Boolean)
			.join(', ')
	);
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<button
	type="button"
	class="assessment-card assessment-card--{density}"
	class:assessment-card--selected={selected}
	class:assessment-card--completed={status === 'completed'}
	class:assessment-card--late={status === 'late'}
	aria-label={summary}
	aria-pressed={selected}
	title={summary}
	onclick={(event) => onselect(assessment, event.currentTarget)}
>
	<span class="assessment-card__accent" aria-hidden="true"></span>

	{#if density === 'micro'}
		<span class="assessment-card__line">
			<span class="assessment-card__marker" aria-hidden="true">{@html truckIcon}</span>
			<span class="assessment-card__time">{startLabel}</span>
			<span class="assessment-card__work">{clientLabel} · {workLabel}</span>
		</span>
	{:else}
		<span class="assessment-card__time">
			<span class="assessment-card__marker" aria-hidden="true">{@html truckIcon}</span>
			{density === 'standard' ? timeLabel : startLabel}
		</span>
		{#if density === 'standard'}
			<span class="assessment-card__client">{clientLabel}</span>
			<span class="assessment-card__work">{workLabel}</span>
		{:else}
			<span class="assessment-card__work">
				<span class="assessment-card__client">{clientLabel}</span> · {workLabel}
			</span>
		{/if}

		{#if density === 'standard'}
			{#if place}
				<span class="assessment-card__place">{place}</span>
			{/if}
			<span class="assessment-card__foot">
				{#if showAssignment}
					<span class="assessment-card__assignment">
						{assignmentLabel(assessment.assignee_ids, employeesById)}
					</span>
				{/if}
				<span class="assessment-card__tag">Assessment</span>
			</span>
		{/if}
	{/if}
</button>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.assessment-card {
		position: relative;
		display: flex;
		flex-direction: column;
		gap: var(--space-smallest);
		box-sizing: border-box;
		width: 100%;
		height: 100%;
		min-width: 0;
		padding: var(--space-smaller) var(--space-small);
		overflow: hidden;
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-small);
		background-color: var(--color-surface);
		color: var(--color-text);
		font-family: inherit;
		text-align: left;
		cursor: pointer;
		transition:
			background-color var(--timing-quick) ease,
			box-shadow var(--timing-quick) ease;

		&:hover {
			background-color: var(--color-surface--hover);
		}
		&:focus-visible {
			outline: none;
			box-shadow: var(--shadow-focus);
		}
	}

	.assessment-card__accent {
		position: absolute;
		top: 0;
		bottom: 0;
		left: 0;
		width: var(--space-smaller);
		// The Request accent, so an assessment reads as a different kind of work from a job visit at a glance.
		background-color: var(--color-request);
	}

	.assessment-card--selected {
		background-color: var(--color-surface--active);
		box-shadow: var(--shadow-focus);
	}

	.assessment-card--completed {
		border-style: dashed;
		color: var(--color-text--secondary);

		.assessment-card__client {
			color: var(--color-text--secondary);
		}
		.assessment-card__accent {
			opacity: 0.5;
		}
	}

	.assessment-card--late {
		border-color: var(--color-critical);
	}

	.assessment-card__line {
		display: flex;
		align-items: center;
		gap: var(--space-smaller);
		min-width: 0;
	}

	.assessment-card__marker {
		display: inline-flex;
		flex-shrink: 0;
		color: var(--color-request);

		:global(svg) {
			width: 13px;
			height: 13px;
		}
	}

	.assessment-card__time {
		display: flex;
		align-items: center;
		gap: var(--space-smaller);
		color: var(--color-heading);
		font-size: var(--typography--fontSize-small);
		font-weight: 700;
		line-height: var(--typography--lineHeight-tighter);
		white-space: nowrap;
	}

	.assessment-card__client {
		color: var(--color-heading);
		font-size: var(--typography--fontSize-small);
		font-weight: 700;
		line-height: var(--typography--lineHeight-tighter);
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}

	.assessment-card__work,
	.assessment-card__place,
	.assessment-card__assignment {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		line-height: var(--typography--lineHeight-tighter);
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}

	.assessment-card__work .assessment-card__client {
		overflow: visible;
	}

	.assessment-card__foot {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-small);
		margin-top: auto;
		min-width: 0;
	}

	.assessment-card__tag {
		flex-shrink: 0;
		padding: 0 var(--space-smaller);
		border-radius: var(--radius-small);
		background-color: var(--color-request--surface);
		color: var(--color-request--onSurface);
		font-size: var(--typography--fontSize-smaller);
		font-weight: 700;
		line-height: var(--typography--lineHeight-loose);
		white-space: nowrap;
	}

	.assessment-card--micro {
		justify-content: center;
		padding: 0 var(--space-smaller) 0 var(--space-small);

		.assessment-card__time {
			flex-shrink: 0;
		}

		.assessment-card__work {
			flex: 1 1 auto;
			min-width: 0;
			color: var(--color-text);
		}
	}
</style>
