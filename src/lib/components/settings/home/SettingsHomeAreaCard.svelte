<script lang="ts">
	import CardHeader from '$lib/components/ui/CardHeader.svelte';
	import IconTile from '$lib/components/ui/IconTile.svelte';
	import StatusBadge from '$lib/components/ui/StatusBadge.svelte';
	import chevronRightIcon from '@tabler/icons/outline/chevron-right.svg?raw';
	import type { SettingsHomeRow } from '$lib/settings/home-rows';

	// One area of the Settings home (Pencil: "Batch 63 · Settings home", area cards): a Card header and a row
	// for each setting, each showing how that setting is set right now.
	let {
		id,
		title,
		hint,
		icon,
		tone,
		rows
	}: {
		id: string;
		title: string;
		hint: string;
		icon: string;
		tone: string;
		rows: SettingsHomeRow[];
	} = $props();
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<section class="home-area" aria-labelledby={id}>
	<CardHeader {id} {title} {hint} {icon} {tone} />
	<ul class="home-area__rows">
		{#each rows as row (row.key)}
			<li>
				<!-- eslint-disable-next-line svelte/no-navigation-without-resolve -- callers pass hrefs already built with resolve() -->
				<a class="home-area__row" href={row.href}>
					<IconTile icon={row.icon} tone={row.tone} size={32} />
					<span class="home-area__name">{row.title}</span>
					{#if row.pill}
						<StatusBadge status={row.pill.tone}>{row.pill.label}</StatusBadge>
					{:else if row.value}
						<span class="home-area__value">{row.value}</span>
					{/if}
					<span class="home-area__chevron" aria-hidden="true">{@html chevronRightIcon}</span>
				</a>
			</li>
		{/each}
	</ul>
</section>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.home-area {
		background: var(--color-surface);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-large);
		overflow: hidden;

		&__rows {
			display: flex;
			flex-direction: column;
			margin: 0;
			padding: 6px var(--space-small);
			list-style: none;
		}
		&__row {
			display: flex;
			align-items: center;
			gap: var(--space-slim);
			padding: 10px var(--space-small);
			border-radius: var(--radius-base);
			color: inherit;
			text-decoration: none;

			&:hover {
				background: var(--color-surface--hover);
			}
			&:active {
				background: var(--color-surface--active);
			}
			&:focus-visible {
				outline: none;
				box-shadow: var(--shadow-focus);
			}
		}
		&__name {
			flex: 1 0 auto;
			color: var(--color-heading);
			font-size: var(--typography--fontSize-base);
			font-weight: 600;
			white-space: nowrap;
		}
		&__value {
			flex: 0 1 auto;
			min-width: 0;
			overflow: hidden;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-base);
			font-weight: 500;
			text-align: right;
			text-overflow: ellipsis;
			white-space: nowrap;
		}
		&__chevron {
			display: grid;
			color: var(--color-icon--secondary);

			:global(svg) {
				width: 16px;
				height: 16px;
			}
		}
	}
</style>
