<script module lang="ts">
	import type { StatusTone } from './types';

	export type AttentionTile = {
		key: string;
		label: string;
		/** One line under the count saying what the status means. */
		hint: string;
		count: number;
		tone: StatusTone;
		/** Make the tile a link to another page instead of a list filter. Leave out to filter in place. */
		href?: string;
	};
	export type AttentionFact = {
		/** A Tabler icon (raw SVG). */
		icon: string;
		value: string;
		label: string;
	};
</script>

<script lang="ts">
	import arrowRightIcon from '@tabler/icons/outline/arrow-right.svg?raw';

	// The "Needs attention" card above a work list: the few statuses the office acts on, each as a tile
	// with its count. Picking a tile shows only those records in the list below; picking it again clears
	// it. A thin strip under the tiles carries two plain facts about today and the recent past.
	let {
		title = 'Needs attention',
		description,
		tiles,
		selectedKey = '',
		onSelect,
		facts = [],
		loading = false
	}: {
		title?: string;
		description: string;
		tiles: AttentionTile[];
		/** The tile whose records the list is showing, or empty for none. */
		selectedKey?: string;
		/** Called with a tile's key when it is picked, or with an empty key when the picked one is picked
		 *  again. Tiles that carry an `href` are links and never call it. */
		onSelect?: (key: string) => void;
		facts?: AttentionFact[];
		loading?: boolean;
	} = $props();

	const uid = $props.id();
	const titleId = `${uid}-title`;
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<section class="attention-card" aria-labelledby={titleId}>
	<header class="attention-card__header">
		<h2 id={titleId}>{title}</h2>
		<p>{description}</p>
	</header>
	<ul class="attention-card__tiles">
		{#each tiles as tile (tile.key)}
			{@const selected = selectedKey === tile.key}
			<li>
				<svelte:element
					this={tile.href ? 'a' : 'button'}
					type={tile.href ? undefined : 'button'}
					href={tile.href}
					class={[
						'attention-card__tile',
						`attention-card__tile--${tile.tone}`,
						tile.tone === 'critical' && tile.count > 0 && 'attention-card__tile--alert',
						selected && 'attention-card__tile--selected'
					]}
					aria-pressed={tile.href ? undefined : selected}
					aria-label={loading
						? `${tile.label}: ${tile.hint}`
						: `${tile.label}: ${tile.count}. ${tile.hint}`}
					onclick={tile.href ? undefined : () => onSelect?.(selected ? '' : tile.key)}
				>
					<span class="attention-card__label">
						<span class="attention-card__dot" aria-hidden="true"></span>{tile.label}
					</span>
					<span class="attention-card__count-row">
						<span class="attention-card__count">{loading ? '—' : tile.count}</span>
						<span class="attention-card__arrow" aria-hidden="true">{@html arrowRightIcon}</span>
					</span>
					<span class="attention-card__hint">{tile.hint}</span>
				</svelte:element>
			</li>
		{/each}
	</ul>
	{#if facts.length > 0}
		<ul class="attention-card__facts">
			{#each facts as fact (fact.label)}
				<li>
					<span class="attention-card__fact-icon" aria-hidden="true">{@html fact.icon}</span>
					<strong>{fact.value}</strong>
					<span>{fact.label}</span>
				</li>
			{/each}
		</ul>
	{/if}
</section>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.attention-card {
		container-type: inline-size;
		min-width: 0;
		overflow: hidden;
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface);

		&__header {
			display: grid;
			gap: 3px;
			padding: var(--space-large) var(--space-large) var(--space-base);
			border-bottom: var(--border-base) solid var(--color-border);

			h2 {
				color: var(--color-heading);
				font-size: var(--typography--fontSize-large);
				font-weight: 700;
				letter-spacing: -0.2px;
			}
			p {
				color: var(--color-text--secondary);
				font-size: 13px;
				font-weight: 500;
			}
		}

		&__tiles {
			display: grid;
			grid-template-columns: repeat(5, minmax(0, 1fr));
			gap: 0;
			margin: 0;
			padding: var(--space-small) 6px;
			list-style: none;

			@container (max-width: 700px) {
				grid-template-columns: repeat(3, minmax(0, 1fr));
			}
			@container (max-width: 440px) {
				grid-template-columns: repeat(2, minmax(0, 1fr));
			}
		}

		&__tile {
			display: grid;
			align-content: start;
			gap: 10px;
			width: 100%;
			height: 100%;
			padding: 14px var(--space-slim);
			border: 0;
			border-radius: var(--radius-large);
			color: inherit;
			text-decoration: none;
			background: transparent;
			font: inherit;
			text-align: start;
			cursor: pointer;
			transition:
				background-color var(--timing-quick),
				box-shadow var(--timing-quick);

			&:hover {
				background: var(--color-surface--hover);
			}
			&:focus-visible {
				outline: none;
				box-shadow: var(--shadow-focus);
			}
			&--alert {
				background: var(--color-critical--surface);

				&:hover {
					background: var(--color-critical--surface);
				}
			}
			&--selected {
				box-shadow: inset 0 0 0 2px var(--color-interactive);

				&:focus-visible {
					box-shadow:
						inset 0 0 0 2px var(--color-interactive),
						var(--shadow-focus);
				}
			}
		}

		&__label {
			display: flex;
			align-items: center;
			gap: 6px;
			color: var(--color-text);
			font-size: 13px;
			font-weight: 600;
			letter-spacing: -0.1px;
		}
		&__dot {
			flex: 0 0 auto;
			width: 7px;
			height: 7px;
			border-radius: var(--radius-circle);
			background: var(--color-inactive);
		}
		&__tile--warning &__dot {
			background: var(--color-warning);
		}
		&__tile--success &__dot {
			background: var(--color-success);
		}
		&__tile--critical &__dot {
			background: var(--color-critical);
		}
		&__tile--informative &__dot {
			background: var(--color-informative);
		}
		&__tile--critical &__label,
		&__tile--critical &__count {
			color: var(--color-critical);
		}

		&__count-row {
			display: flex;
			align-items: flex-end;
			justify-content: space-between;
			gap: var(--space-small);
		}
		&__count {
			color: var(--color-heading);
			font-size: 30px;
			font-variant-numeric: tabular-nums;
			font-weight: 700;
			letter-spacing: -0.6px;
			line-height: 1.2;
		}
		&__arrow {
			display: inline-flex;
			flex: 0 0 auto;
			margin-bottom: 6px;
			color: var(--color-icon--secondary);
			transition:
				color var(--timing-quick),
				transform var(--timing-quick);

			:global(svg) {
				display: block;
				width: 16px;
				height: 16px;
			}
		}
		&__tile:hover &__arrow {
			color: var(--color-interactive);
			transform: translateX(2px);
		}
		&__tile--critical &__arrow {
			color: var(--color-critical);
		}
		&__tile--selected &__arrow {
			color: var(--color-interactive);
		}
		&__hint {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			font-weight: 500;
			line-height: 1.25;
		}

		&__facts {
			display: flex;
			flex-wrap: wrap;
			align-items: center;
			gap: var(--space-small) var(--space-large);
			margin: 0;
			padding: var(--space-slim) var(--space-large);
			border-top: var(--border-base) solid var(--color-border);
			background: var(--color-surface--background--subtle);
			list-style: none;

			li {
				display: flex;
				align-items: center;
				gap: var(--space-small);
				color: var(--color-text--secondary);
				font-size: 13px;
				font-weight: 500;
			}
			strong {
				color: var(--color-heading);
				font-weight: 700;
			}
		}
		&__fact-icon {
			display: inline-flex;
			color: var(--color-icon--secondary);

			:global(svg) {
				display: block;
				width: 15px;
				height: 15px;
			}
		}
	}
</style>
