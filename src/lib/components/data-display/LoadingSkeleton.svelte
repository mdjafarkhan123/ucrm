<script lang="ts">
	let {
		variant = 'card',
		label = 'Loading',
		rows = 3
	}: {
		variant?: 'text' | 'heading' | 'button' | 'card' | 'table';
		label?: string;
		rows?: number;
	} = $props();
</script>

{#if variant === 'table'}
	<div class="loading loading--table" role="status" aria-label={label} aria-busy="true">
		{#each Array(rows) as _, index (index)}<div class="loading__row">
				<span class="skeleton skeleton--text"></span><span
					class="skeleton skeleton--text skeleton--text-short"
				></span><span class="skeleton skeleton--text"></span>
			</div>{/each}
	</div>
{:else}<div
		class={`skeleton skeleton--${variant}`}
		role="status"
		aria-label={label}
		aria-busy="true"
	></div>{/if}

<style lang="scss">
	.loading--table {
		display: grid;
		gap: var(--space-small);
	}
	.loading__row {
		display: grid;
		grid-template-columns: 1fr 1fr 1fr;
		gap: var(--space-base);
		padding: var(--space-base) var(--space-large);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-small);
		background: var(--color-surface);
	}
	@media (prefers-reduced-motion: reduce) {
		.loading__row {
			animation: none;
		}
	}
</style>
