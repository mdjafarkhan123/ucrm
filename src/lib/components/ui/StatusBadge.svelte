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

	:global(:root:has(.app-shell[data-presentation='classic'])) .status-badge {
		gap: 5px;
		padding: 3px 8px;
		border-radius: 10px;
		font-family: var(--classic2-font);
		font-size: var(--classic2-font-micro);
		font-weight: 700;
	}

	:global(:root:has(.app-shell[data-presentation='classic'])) .status-badge__dot {
		width: 6px;
		height: 6px;
	}

	:global(:root:has(.app-shell[data-presentation='classic'])) .status-badge--success {
		color: var(--classic2-green);
		background: var(--classic2-green-soft);
	}

	:global(:root:has(.app-shell[data-presentation='classic']))
		.status-badge--success
		.status-badge__dot {
		background: var(--classic2-green-mid);
	}

	:global(:root:has(.app-shell[data-presentation='classic'])) .status-badge--warning {
		color: var(--classic2-amber);
		background: var(--classic2-amber-soft);
	}

	:global(:root:has(.app-shell[data-presentation='classic']))
		.status-badge--warning
		.status-badge__dot {
		background: var(--classic2-amber-dot);
	}

	:global(:root:has(.app-shell[data-presentation='classic'])) .status-badge--critical {
		color: var(--classic2-rose);
		background: var(--classic2-rose-soft);
	}

	:global(:root:has(.app-shell[data-presentation='classic']))
		.status-badge--critical
		.status-badge__dot {
		background: var(--classic2-rose);
	}

	:global(:root:has(.app-shell[data-presentation='classic'])) .status-badge--inactive {
		color: var(--classic2-secondary);
		background: var(--classic2-chip);
	}

	:global(:root:has(.app-shell[data-presentation='classic']))
		.status-badge--inactive
		.status-badge__dot {
		background: var(--classic2-icon-muted);
	}

	:global(:root:has(.app-shell[data-presentation='classic'])) .status-badge--informative {
		color: var(--classic2-blue);
		background: var(--classic2-blue-soft);
	}

	:global(:root:has(.app-shell[data-presentation='classic']))
		.status-badge--informative
		.status-badge__dot {
		background: var(--classic2-blue-dot);
	}
</style>
