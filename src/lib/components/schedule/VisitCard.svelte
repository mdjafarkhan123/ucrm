<script lang="ts">
	import { visitDerivedStatus } from '$lib/schedule/status';
	import { VISIT_STATUS_LABELS } from '$lib/schedule/statuses';
	import {
		visitAccentColor,
		visitAssignmentLabel,
		visitClientLabel,
		visitPlaceLabel,
		visitStartLabel,
		visitTimeLabel,
		visitWorkLabel
	} from '$lib/schedule/labels';
	import type { CardDensity } from '$lib/schedule/layout';
	import type { ScheduleVisit } from '$lib/schedule/api';
	import type { TeamMember } from '$lib/team/api';
	import usersIcon from '@tabler/icons/outline/users.svg?raw';

	// One visit, drawn at whatever size the calendar could give it.
	//
	// The card does not choose its own size: the grid measured the space and says which form fits, so a
	// fifteen-minute visit keeps its true fifteen minutes and simply shows less, rather than being grown to
	// fit its own text. Everything it can say comes from the shared labels, so the Week grid, the Day board
	// and the Month cell describe a visit identically.

	let {
		visit,
		density,
		today,
		employeesById,
		selected = false,
		showAssignment = true,
		onselect,
		onpickup
	}: {
		visit: ScheduleVisit;
		density: CardDensity;
		today: string;
		employeesById: Map<string, TeamMember>;
		selected?: boolean;
		/** The card was pressed: the calendar decides whether that becomes a drag or stays a click. */
		onpickup?: (event: PointerEvent) => void;
		/** False where the surface itself already says who is going, as the Day board's employee row does.
		 * The card never repeats identity the row has already given. */
		showAssignment?: boolean;
		/** The element is handed back so the page can anchor the preview to this exact card. */
		onselect: (visit: ScheduleVisit, element: HTMLElement) => void;
	} = $props();

	const status = $derived(visitDerivedStatus(visit, today));
	const accent = $derived(visitAccentColor(visit, employeesById));
	const shared = $derived(visit.assignee_ids.length > 1);
	const unassigned = $derived(visit.assignee_ids.length === 0);
	const place = $derived(visitPlaceLabel(visit));

	// The whole card in words, for a screen reader and for the smallest form, where most of it is not drawn.
	const summary = $derived(
		[
			visitTimeLabel(visit),
			visitClientLabel(visit),
			visitWorkLabel(visit),
			visitAssignmentLabel(visit, employeesById),
			status ? VISIT_STATUS_LABELS[status] : null
		]
			.filter(Boolean)
			.join(', ')
	);
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<button
	type="button"
	class="visit-card visit-card--{density}"
	class:visit-card--selected={selected}
	class:visit-card--completed={status === 'completed'}
	class:visit-card--late={status === 'late'}
	class:visit-card--unassigned={unassigned}
	style:--visit-card-accent={accent ?? undefined}
	aria-label={summary}
	aria-pressed={selected}
	title={summary}
	onclick={(event) => onselect(visit, event.currentTarget)}
	onpointerdown={onpickup}
>
	<span class="visit-card__accent" aria-hidden="true"></span>

	{#if density === 'micro'}
		<span class="visit-card__line">
			{#if status}<span class="visit-card__dot visit-card__dot--{status}" aria-hidden="true"
				></span>{/if}
			<span class="visit-card__time">{visitStartLabel(visit)}</span>
			<!-- One truncating line: whose it is comes before what it is, and whatever is left of the title
			     rides along behind it. -->
			<span class="visit-card__work">{visitClientLabel(visit)} · {visitWorkLabel(visit)}</span>
		</span>
	{:else}
		<span class="visit-card__time">
			{density === 'standard' ? visitTimeLabel(visit) : visitStartLabel(visit)}
			{#if shared}
				<span class="visit-card__shared" title="Shared visit">
					{@html usersIcon}
					{visit.assignee_ids.length}
				</span>
			{/if}
		</span>
		{#if density === 'standard'}
			<span class="visit-card__client">{visitClientLabel(visit)}</span>
			<span class="visit-card__work">{visitWorkLabel(visit)}</span>
		{:else}
			<!-- A compact block is only ever tall enough for two lines. Client and title share the second
			     one, exactly as they do on a micro card, rather than being squeezed onto half a line each. -->
			<span class="visit-card__work">
				<span class="visit-card__client">{visitClientLabel(visit)}</span> ·
				{visitWorkLabel(visit)}
			</span>
		{/if}

		{#if density === 'standard'}
			{#if place}
				<span class="visit-card__place">{place}</span>
			{/if}
			<span class="visit-card__foot">
				{#if showAssignment}
					<span class="visit-card__assignment">{visitAssignmentLabel(visit, employeesById)}</span>
				{/if}
				{#if status}
					<span class="visit-card__status">
						<span class="visit-card__dot visit-card__dot--{status}" aria-hidden="true"></span>
						{VISIT_STATUS_LABELS[status]}
					</span>
				{/if}
			</span>
		{/if}
	{/if}
</button>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.visit-card {
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
		// The accent is a narrow stripe, never a saturated fill: a wall of colour stops being readable the
		// moment a day has more than a few visits on it.
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

	.visit-card__accent {
		position: absolute;
		top: 0;
		bottom: 0;
		left: 0;
		width: var(--space-smaller);
		// The employee's own colour when exactly one person is going; the neutral work colour when the crew
		// is shared, because no one employee owns that visit.
		background-color: var(--visit-card-accent, var(--color-visit));
	}

	.visit-card--unassigned .visit-card__accent {
		background-color: var(--color-warning);
	}

	.visit-card--selected {
		background-color: var(--color-surface--active);
		box-shadow: var(--shadow-focus);
	}

	.visit-card--completed {
		border-style: dashed;
		color: var(--color-text--secondary);

		.visit-card__client {
			color: var(--color-text--secondary);
		}
		.visit-card__accent {
			opacity: 0.5;
		}
	}

	.visit-card--late {
		border-color: var(--color-critical);
	}

	.visit-card__line {
		display: flex;
		align-items: center;
		gap: var(--space-smaller);
		min-width: 0;
	}

	.visit-card__time {
		display: flex;
		align-items: center;
		gap: var(--space-smaller);
		color: var(--color-heading);
		font-size: var(--typography--fontSize-small);
		font-weight: 700;
		line-height: var(--typography--lineHeight-tighter);
		white-space: nowrap;
	}

	.visit-card__client {
		color: var(--color-heading);
		font-size: var(--typography--fontSize-small);
		font-weight: 700;
		line-height: var(--typography--lineHeight-tighter);
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}

	.visit-card__work,
	.visit-card__place,
	.visit-card__assignment {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		line-height: var(--typography--lineHeight-tighter);
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}

	// On a compact card the client rides inside the work line, so it is plain inline text and the line
	// around it owns the truncation.
	.visit-card__work .visit-card__client {
		overflow: visible;
	}

	.visit-card--unassigned .visit-card__assignment {
		color: var(--color-warning--onSurface);
		font-weight: 700;
	}

	.visit-card__shared {
		display: inline-flex;
		align-items: center;
		gap: var(--space-smallest);
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-smaller);
		font-weight: 700;

		:global(svg) {
			width: 12px;
			height: 12px;
		}
	}

	.visit-card__foot {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-small);
		margin-top: auto;
		min-width: 0;
	}

	.visit-card__status {
		display: inline-flex;
		flex-shrink: 0;
		align-items: center;
		gap: var(--space-smaller);
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-smaller);
		line-height: var(--typography--lineHeight-tight);
		white-space: nowrap;
	}

	// Status never travels as colour alone -- every card that shows a dot shows its word beside it, or
	// carries the whole summary in its accessible label when it is too small for either.
	.visit-card__dot {
		display: inline-block;
		flex-shrink: 0;
		width: 8px;
		height: 8px;
		border-radius: var(--radius-circle);

		&--upcoming {
			background-color: var(--color-informative);
		}
		&--today {
			background-color: var(--color-success);
		}
		&--late {
			background-color: var(--color-critical);
		}
		&--completed {
			background-color: var(--color-inactive);
		}
	}

	.visit-card--micro {
		justify-content: center;
		padding: 0 var(--space-smaller) 0 var(--space-small);

		.visit-card__time {
			flex-shrink: 0;
		}

		.visit-card__work {
			// The line gives the time whatever it needs and truncates the rest, so the start of a visit is
			// never the part that disappears.
			flex: 1 1 auto;
			min-width: 0;
			color: var(--color-text);
		}
	}
</style>
