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

	// Rows of different lengths, so the shapes read as a list rather than a grid of bars.
	const LINE_WIDTHS = [160, 120, 180, 140];
</script>

{#if variant === 'table'}
	<div class="loading loading--table" role="status" aria-label={label} aria-busy="true">
		{#each Array(rows) as _, index (index)}<div class="loading__row">
				<span class="skeleton loading__tile"></span>
				<span class="loading__lines">
					<span class="skeleton loading__line" style:width={`${LINE_WIDTHS[index % 4]}px`}></span>
					<span
						class="skeleton loading__line loading__line--short"
						style:width={`${LINE_WIDTHS[index % 4] * 0.65}px`}
					></span>
				</span>
				<span class="skeleton loading__end"></span>
			</div>{/each}
	</div>
{:else}<div
		class={`skeleton skeleton--${variant}`}
		role="status"
		aria-label={label}
		aria-busy="true"
	></div>{/if}

<style lang="scss">
	// Row-shaped grey shapes where the rows will be (`concept.pen` → Pop-ups → Page states).
	.loading--table {
		display: grid;
		padding: var(--space-small);
	}
	.loading__row {
		display: flex;
		align-items: center;
		gap: 14px;
		padding: var(--space-slim) var(--space-base);
	}
	.loading__tile {
		flex: 0 0 auto;
		width: 32px;
		height: 32px;
		border-radius: var(--radius-base);
	}
	.loading__lines {
		display: grid;
		flex: 1 1 auto;
		gap: var(--space-small);
		min-width: 0;
	}
	.loading__line {
		max-width: 100%;
		height: 10px;
		min-height: 0;

		&--short {
			height: 8px;
		}
	}
	.loading__end {
		flex: 0 0 auto;
		width: 56px;
		height: 20px;
		min-height: 0;
	}
</style>
