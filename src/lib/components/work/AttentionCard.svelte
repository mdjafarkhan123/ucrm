<script module lang="ts">
	import type { StatusTone } from './types';

	export type AttentionTile = {
		key: string;
		label: string;
		/** One line under the count saying what the status means. */
		hint: string;
		/** A money figure drawn in bold before the hint ("$8,920 not sent yet"). Leave out to show the hint alone. */
		amount?: string;
		count: number;
		tone: StatusTone;
		/** A Tabler icon (raw SVG) drawn on a soft tile in the status colour, above the count. */
		icon: string;
		/** Make the tile a link to another page instead of a list filter. Leave out to filter in place. */
		href?: string;
	};
	export type AttentionFact = {
		/** A Tabler icon (raw SVG). */
		icon: string;
		/** The bold part. Leave empty for a fact that is all plain words. */
		value: string;
		label: string;
		/** Push this fact to the far end of the strip, away from the counted facts. */
		align?: 'end';
		/** Colour the icon, for a fact about something switched on. `time` and `success` put the icon on a
		 *  small tile in that colour (visits booked, work done). */
		tone?: 'warning' | 'time' | 'success';
	};
	/** One slice of the proportion bar under the header; only the shares between slices matter. */
	export type AttentionBarPart = {
		key: string;
		label: string;
		share: number;
		tone: StatusTone;
	};
</script>

<script lang="ts">
	import IconTile from '$lib/components/ui/IconTile.svelte';
	import KpiCard from '$lib/components/data-display/KpiCard.svelte';
	import type { Snippet } from 'svelte';

	let {
		title = 'Needs attention',
		description,
		icon,
		tone = 'inactive',
		tiles,
		selectedKey = '',
		onSelect,
		facts = [],
		footer,
		summary,
		feature,
		loading = false
	}: {
		title?: string;
		description: string;
		icon?: string;
		tone?: string;
		tiles: AttentionTile[];
		selectedKey?: string;
		onSelect?: (key: string) => void;
		facts?: AttentionFact[];
		footer?: Snippet;
		summary?: { value: string; label: string };
		/** The final card in the row, using KpiCard's green feature tone. */
		feature?: Snippet;
		loading?: boolean;
	} = $props();

	const uid = $props.id();
	const titleId = `${uid}-title`;
</script>

<section class="attention-card" aria-labelledby={titleId}>
	<header class="attention-card__header">
		<div class="attention-card__heading">
			{#if icon}<IconTile {icon} {tone} size={32} />{/if}
			<div>
				<h2 id={titleId}>{title}</h2>
				<p>{description}</p>
			</div>
		</div>
		{#if summary}<p class="attention-card__summary">
				<strong>{summary.value}</strong>
				{summary.label}
			</p>{/if}
		{#if facts.length > 0}
			<ul class="attention-card__facts">
				{#each facts as fact (`${fact.value}|${fact.label}`)}
					<li>
						<IconTile icon={fact.icon} tone={fact.tone ?? 'inactive'} size={24} />
						{#if fact.value}<strong>{fact.value}</strong>{/if}<span>{fact.label}</span>
					</li>
				{/each}
			</ul>
		{/if}
	</header>
	<ul
		class="attention-card__tiles"
		style:--kpi-template={`repeat(${tiles.length}, minmax(0, 1fr))${feature ? ' minmax(0, 1.4fr)' : ''}`}
		style:--kpi-columns={tiles.length + (feature ? 1 : 0)}
	>
		{#each tiles as tile (tile.key)}
			<li>
				<KpiCard
					label={tile.label}
					value={String(tile.count)}
					icon={tile.icon}
					tone={tile.tone}
					note={`${tile.amount && !loading ? `${tile.amount} ` : ''}${tile.hint}`}
					href={tile.href}
					onclick={onSelect ? () => onSelect(selectedKey === tile.key ? '' : tile.key) : undefined}
					selected={selectedKey === tile.key}
					alert={tile.tone === 'critical' && tile.count > 0 && !loading}
					{loading}
				/>
			</li>
		{/each}
		{#if feature}<li>{@render feature()}</li>{/if}
	</ul>
	{#if footer}<div class="attention-card__footer">{@render footer()}</div>{/if}
</section>

<style lang="scss">
	.attention-card {
		container-type: inline-size;
		display: grid;
		gap: var(--space-base);
		min-width: 0;
		&__header {
			display: flex;
			flex-wrap: wrap;
			align-items: center;
			justify-content: space-between;
			gap: var(--space-base);
		}
		&__heading {
			display: flex;
			align-items: center;
			gap: var(--space-slim);
			h2 {
				margin: 0;
				color: var(--color-heading);
				font-size: var(--space-base);
				font-weight: 600;
			}
			p {
				margin: var(--space-smallest) 0 0;
				color: var(--color-text--secondary);
				font-size: var(--typography--fontSize-small);
			}
		}
		&__summary {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-label);
			strong {
				color: var(--color-heading);
			}
		}
		&__facts {
			display: flex;
			flex-wrap: wrap;
			gap: var(--space-small) var(--space-medium);
			margin: 0;
			padding: 0;
			list-style: none;
			li {
				display: flex;
				align-items: center;
				gap: var(--space-small);
				font-size: var(--typography--fontSize-label);
				color: var(--color-text--secondary);
			}
			strong {
				color: var(--color-heading);
			}
		}
		&__tiles {
			display: grid;
			grid-template-columns: var(--kpi-template);
			align-items: stretch;
			gap: var(--space-slim);
			margin: 0;
			padding: 0;
			list-style: none;
			li {
				display: flex;
				min-width: 0;
			}
		}
		&__footer {
			display: flex;
			flex-wrap: wrap;
			align-items: center;
			gap: var(--space-slim);
		}
	}
	@container (max-width: 1000px) {
		.attention-card__tiles {
			grid-template-columns: repeat(3, minmax(0, 1fr));
		}
	}
	@container (max-width: 580px) {
		.attention-card__tiles {
			grid-template-columns: repeat(2, minmax(0, 1fr));
		}
	}
	@container (max-width: 280px) {
		.attention-card__tiles {
			grid-template-columns: minmax(0, 1fr);
		}
	}
</style>
