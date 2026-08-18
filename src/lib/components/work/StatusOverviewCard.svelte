<script lang="ts">
	import SectionBlock from '$lib/components/layout/SectionBlock.svelte';
	import type { StatusOverviewRow } from './types';

	// The Overview card that sits above a work list — requests today, quotes, jobs and invoices next.
	// It counts, it does not filter: clicking a row does nothing, the same as Jobber. Filtering belongs
	// to the Status chip on the toolbar below.
	let {
		title = 'Overview',
		rows,
		loading = false
	}: {
		title?: string;
		rows: StatusOverviewRow[];
		loading?: boolean;
	} = $props();
</script>

<SectionBlock {title}>
	<ul class="status-overview__list">
		{#each rows as row (row.label)}
			<li class={`status-overview__row status-overview__row--${row.tone}`}>
				<span class="status-overview__dot" aria-hidden="true"></span>
				<span class="status-overview__label">{row.label}</span>
				<span class="status-overview__count">{loading ? '—' : row.count}</span>
			</li>
		{/each}
	</ul>
</SectionBlock>

<style lang="scss">
	.status-overview__list {
		display: grid;
		gap: var(--space-small);
		margin: 0;
		padding: 0;
		list-style: none;
	}

	.status-overview__row {
		display: grid;
		align-items: center;
		gap: var(--space-small);
		grid-template-columns: 8px 1fr auto;
		color: var(--color-text);
		font-size: var(--typography--fontSize-base);
	}

	.status-overview__dot {
		width: 8px;
		height: 8px;
		border-radius: var(--radius-circle);
		background: var(--color-inactive);
	}

	.status-overview__row--success .status-overview__dot {
		background: var(--color-success);
	}
	.status-overview__row--warning .status-overview__dot {
		background: var(--color-warning);
	}
	.status-overview__row--critical .status-overview__dot {
		background: var(--color-critical);
	}
	.status-overview__row--informative .status-overview__dot {
		background: var(--color-informative);
	}

	.status-overview__count {
		color: var(--color-heading);
		font-variant-numeric: tabular-nums;
		font-weight: 600;
	}
</style>
