<script lang="ts">
	import type { Snippet } from 'svelte';
	import IconTile from '$lib/components/ui/IconTile.svelte';

	// One row of a closed section: a 32 tile in the fact's meaning colour, the label over its value, and
	// whatever state or action belongs to it at the right.
	let {
		icon,
		tone,
		label,
		value,
		aside
	}: {
		icon: string;
		tone: string;
		label: string;
		value: string;
		aside?: Snippet;
	} = $props();
</script>

<div class="profile-fact">
	<IconTile {icon} {tone} size={32} />
	<div class="profile-fact__copy">
		<span class="profile-fact__label">{label}</span>
		<span class="profile-fact__value">{value}</span>
	</div>
	{#if aside}<div class="profile-fact__aside">{@render aside()}</div>{/if}
</div>

<style lang="scss">
	.profile-fact {
		display: flex;
		align-items: center;
		gap: var(--space-slim);
		padding: var(--space-slim) var(--space-medium);

		&:not(:first-child) {
			border-top: var(--border-base) solid var(--color-border);
		}
		&__copy {
			display: flex;
			flex: 1;
			flex-direction: column;
			gap: var(--space-smaller);
			min-width: 0;
		}
		&__label {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-smaller);
			font-weight: 500;
		}
		&__value {
			color: var(--color-heading);
			font-size: var(--typography--fontSize-base);
			font-weight: 600;
			overflow-wrap: anywhere;
		}
		&__aside {
			display: flex;
			flex: none;
			align-items: center;
			gap: var(--space-small);
		}
	}
</style>
