<script lang="ts">
	import type { Snippet } from 'svelte';

	let {
		children,
		status
	}: {
		children: Snippet;
		status: 'success' | 'warning' | 'critical' | 'inactive' | 'informative';
	} = $props();
</script>

<span class={`status-badge status-badge--${status}`} role="status">
	<span class="status-badge__dot" aria-hidden="true"></span>
	<span class="status-badge__text">{@render children()}</span>
</span>

<style lang="scss">
	.status-badge {
		display: inline-flex;
		align-items: center;
		gap: 6px;
		width: fit-content;
		padding: 6px 10px 6px 8px;
		border-radius: 12px;
		font-size: var(--typography--fontSize-small);
		line-height: 1;
		white-space: nowrap;
	}

	.status-badge__dot {
		width: 8px;
		height: 8px;
		flex: 0 0 auto;
		border-radius: var(--radius-circle);
	}

	.status-badge__text {
		color: inherit;
	}

	.status-badge--success {
		color: var(--color-success--onSurface);
		background: var(--color-success--surface);
	}

	.status-badge--success .status-badge__dot {
		background: var(--color-success);
	}

	.status-badge--warning {
		color: var(--color-warning--onSurface);
		background: var(--color-warning--surface);
	}

	.status-badge--warning .status-badge__dot {
		background: var(--color-warning);
	}

	.status-badge--critical {
		color: var(--color-critical--onSurface);
		background: var(--color-critical--surface);
	}

	.status-badge--critical .status-badge__dot {
		background: var(--color-critical);
	}

	.status-badge--inactive {
		color: var(--color-inactive--onSurface);
		background: var(--color-inactive--surface);
	}

	.status-badge--inactive .status-badge__dot {
		background: var(--color-inactive);
	}

	.status-badge--informative {
		color: var(--color-informative--onSurface);
		background: var(--color-informative--surface);
	}

	.status-badge--informative .status-badge__dot {
		background: var(--color-informative);
	}
</style>
