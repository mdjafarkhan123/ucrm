<script lang="ts">
	import IconTile from '$lib/components/ui/IconTile.svelte';
	import StatusBadge from '$lib/components/ui/StatusBadge.svelte';
	import PaperworkFlag from '$lib/components/communications/paperwork/PaperworkFlag.svelte';
	import {
		STATUS_LABELS,
		STATUS_ORDER,
		summaryCount,
		summaryLine,
		type NumberCard,
		type ReadinessStatus,
		type ReadinessSummary
	} from '$lib/communications/number-readiness';
	import messageCircleIcon from '@tabler/icons/outline/message-circle.svg?raw';

	// "Can you text yet?" at the top of Phone & SMS (`concept.pen` board `NbWfA`): how many numbers can text
	// today, the one line naming what needs the business, a bar with a segment per number in its status colour,
	// and the countries the business can text.
	let { summary, cards }: { summary: ReadinessSummary; cards: NumberCard[] } = $props();

	const TONES: Record<ReadinessStatus, string> = {
		ready_to_text: 'success',
		action_needed: 'critical',
		texting_paused: 'critical',
		business_details_needed: 'informative',
		under_review: 'warning',
		getting_ready: 'warning'
	};

	const segments = $derived(
		[...cards]
			.filter((card) => card.status)
			.sort(
				(a, b) =>
					STATUS_ORDER.indexOf(a.status as ReadinessStatus) -
					STATUS_ORDER.indexOf(b.status as ReadinessStatus)
			)
	);
	const legend = $derived(
		STATUS_ORDER.filter((status) => summary.counts[status]).map((status) => ({
			status,
			count: summary.counts[status] ?? 0
		}))
	);
</script>

<section class="readiness-summary" aria-labelledby="readiness-summary-title">
	<div class="readiness-summary__main">
		<div class="readiness-summary__eyebrow">
			<IconTile icon={messageCircleIcon} tone="conversation" />
			<h2 id="readiness-summary-title">Can you text yet?</h2>
		</div>
		<p class="readiness-summary__count">
			<strong>{summaryCount(summary)}</strong>
			<span>{summary.total === 1 ? 'number' : 'numbers'} can text today</span>
		</p>
		<p class="readiness-summary__line">{summaryLine(summary)}</p>
		<div class="readiness-summary__bar" aria-hidden="true">
			{#each segments as card (card.key)}
				<span
					class="readiness-summary__segment"
					style:background={`var(--color-${TONES[card.status as ReadinessStatus]})`}
				></span>
			{/each}
		</div>
		<ul class="readiness-summary__legend">
			{#each legend as entry (entry.status)}
				<li>
					<span
						class="readiness-summary__dot"
						style:background={`var(--color-${TONES[entry.status]})`}
						aria-hidden="true"
					></span>
					{entry.count}
					{STATUS_LABELS[entry.status]}
				</li>
			{/each}
		</ul>
	</div>

	<div class="readiness-summary__reach">
		<h3>Where you can text</h3>
		<ul>
			{#each summary.countries as country (country.code)}
				<li>
					<PaperworkFlag code={country.code} size={24} />
					<span class="readiness-summary__country">{country.name}</span>
					<StatusBadge status={country.ready ? 'success' : 'warning'}>
						{country.ready ? 'Ready' : 'Setting up'}
					</StatusBadge>
				</li>
			{/each}
		</ul>
	</div>
</section>

<style lang="scss">
	.readiness-summary {
		display: flex;
		align-items: flex-start;
		gap: var(--space-larger);
		padding: var(--space-large);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-large);
		background: var(--color-surface);

		&__main {
			display: grid;
			flex: 1 1 auto;
			gap: var(--space-slim);
			min-width: 0;
		}

		&__eyebrow {
			display: flex;
			align-items: center;
			gap: var(--space-slim);

			h2 {
				margin: 0;
				color: var(--color-text--secondary);
				font-size: var(--typography--fontSize-overline);
				font-weight: 600;
				letter-spacing: 0.6px;
				text-transform: uppercase;
			}
		}

		&__count {
			display: flex;
			align-items: baseline;
			gap: var(--space-slim);
			margin: var(--space-smaller) 0 0;

			strong {
				color: var(--color-heading);
				font-size: var(--typography--fontSize-stat);
				font-weight: 700;
				line-height: var(--typography--lineHeight-tight);
			}

			span {
				color: var(--color-heading);
				font-size: var(--typography--fontSize-large);
				font-weight: 600;
			}
		}

		&__line {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-base);
		}

		&__bar {
			display: flex;
			gap: var(--space-smaller);
		}

		&__segment {
			flex: 1 1 0;
			height: 10px;
			border-radius: var(--radius-circle);
		}

		&__legend {
			display: flex;
			flex-wrap: wrap;
			gap: var(--space-base);
			margin: 0;
			padding: 0;
			list-style: none;

			li {
				display: inline-flex;
				align-items: center;
				gap: 6px;
				color: var(--color-text--secondary);
				font-size: var(--typography--fontSize-smaller);
				font-weight: 500;
			}
		}

		&__dot {
			width: 8px;
			height: 8px;
			border-radius: var(--radius-circle);
		}

		&__reach {
			display: grid;
			flex: 0 0 440px;
			gap: var(--space-slim);
			padding: 14px var(--space-base);
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-tile-large);
			background: var(--color-surface--background--subtle);

			h3 {
				margin: 0;
				color: var(--color-text--secondary);
				font-size: var(--typography--fontSize-overline);
				font-weight: 600;
				letter-spacing: 0.6px;
				text-transform: uppercase;
			}

			ul {
				display: grid;
				gap: var(--space-slim);
				margin: 0;
				padding: 0;
				list-style: none;
			}

			li {
				display: flex;
				align-items: center;
				gap: var(--space-small);
			}
		}

		&__country {
			flex: 1 1 auto;
			color: var(--color-heading);
			font-size: var(--typography--fontSize-base);
			font-weight: 600;
		}
	}

	@media (max-width: 1100px) {
		.readiness-summary {
			flex-direction: column;
			align-items: stretch;

			&__reach {
				flex-basis: auto;
			}
		}
	}
</style>
