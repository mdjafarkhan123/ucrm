<script lang="ts">
	import type { Snippet } from 'svelte';

	let {
		children,
		status,
		size = 'base',
		outlined = false
	}: {
		children: Snippet;
		status: 'success' | 'warning' | 'critical' | 'inactive' | 'informative';
		/** `compact` is retained as an alias for the small pill used by existing tables. `large` is the record
		 *  header's pill. */
		size?: 'base' | 'compact' | 'small' | 'large';
		/** White with an edge in the status colour, for a pill on a tinted card where a filled one would vanish. */
		outlined?: boolean;
	} = $props();
</script>

<span
	class={`status-badge status-badge--${status} status-badge--${size}`}
	class:status-badge--outlined={outlined}
	role="status"
>
	<span class="status-badge__dot" aria-hidden="true"></span>
	<span class="status-badge__text">{@render children()}</span>
</span>

<style lang="scss">
	.status-badge {
		display: inline-flex;
		align-items: center;
		gap: 6px;
		width: fit-content;
		padding: 5px 11px;
		border-radius: var(--radius-circle);
		font-size: var(--typography--fontSize-small);
		font-weight: 600;
		line-height: 1.2;
		white-space: nowrap;

		&--compact,
		&--small {
			padding: 3px 9px;
			font-size: var(--typography--fontSize-overline);
		}

		&--large {
			gap: var(--space-small);
			padding: 6px var(--space-slim);
		}

		&__dot {
			width: 6px;
			height: 6px;
			flex: 0 0 auto;
			border-radius: var(--radius-circle);
		}

		&--compact &__dot,
		&--small &__dot {
			width: 5px;
			height: 5px;
		}

		&--large &__dot {
			width: 8px;
			height: 8px;
		}
	}

	.status-badge__text {
		color: inherit;
	}

	// The edge takes the dot's colour (each status sets it below).
	.status-badge.status-badge--outlined {
		padding: 3px 8px;
		border: var(--border-base) solid var(--status-badge-main);
		background: var(--color-surface);
		font-size: var(--typography--fontSize-small);

		.status-badge__dot {
			width: 5px;
			height: 5px;
		}
	}

	.status-badge--success {
		--status-badge-main: var(--color-success);
		color: var(--color-success--onSurface);
		background: var(--color-success--surface);
	}

	.status-badge--success .status-badge__dot {
		background: var(--color-success);
	}

	.status-badge--warning {
		--status-badge-main: var(--color-warning);
		color: var(--color-warning--onSurface);
		background: var(--color-warning--surface);
	}

	.status-badge--warning .status-badge__dot {
		background: var(--color-warning);
	}

	.status-badge--critical {
		--status-badge-main: var(--color-critical);
		color: var(--color-critical--onSurface);
		background: var(--color-critical--surface);
	}

	.status-badge--critical .status-badge__dot {
		background: var(--color-critical);
	}

	.status-badge--inactive {
		--status-badge-main: var(--color-inactive);
		color: var(--color-inactive--onSurface);
		background: var(--color-inactive--surface);
	}

	.status-badge--inactive .status-badge__dot {
		background: var(--color-inactive);
	}

	.status-badge--informative {
		--status-badge-main: var(--color-informative);
		color: var(--color-informative--onSurface);
		background: var(--color-informative--surface);
	}

	.status-badge--informative .status-badge__dot {
		background: var(--color-informative);
	}
</style>
