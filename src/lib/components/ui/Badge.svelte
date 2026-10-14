<script lang="ts">
	import type { Snippet } from 'svelte';
	let {
		children,
		status,
		size = 'base',
		dot = true,
		class: className = ''
	}: {
		children: Snippet;
		status?: 'success' | 'warning' | 'critical' | 'inactive' | 'informative';
		size?: 'small' | 'base' | 'large' | 'larger';
		/** Colored badges show a leading dot by default; set false for a plain tinted pill. */
		dot?: boolean;
		class?: string;
	} = $props();
</script>

<span
	class={`badge badge--${size} ${className} ${status ? `badge--status badge--${status}` : ''} ${status && !dot ? 'badge--no-dot' : ''}`}
	role={status ? 'status' : undefined}
>
	{#if status && dot}<span class="badge__dot" aria-hidden="true"></span>{/if}
	<span>{@render children()}</span>
</span>

<style lang="scss">
	.badge {
		display: inline-flex;
		align-items: center;
		gap: var(--space-small);
		width: fit-content;
		color: var(--color-heading);
		background: var(--color-inactive--surface);
		border-radius: var(--radius-large);
		font-weight: 600;
		line-height: 1;
		text-transform: capitalize;
	}
	.badge--small {
		padding: var(--space-smallest) var(--space-small);
		font-size: var(--typography--fontSize-smaller);
	}
	.badge--base {
		padding: 6px 10px;
		font-size: var(--typography--fontSize-small);
	}
	.badge--large {
		padding: 10px var(--space-slim);
		border-radius: var(--radius-larger);
		font-size: var(--typography--fontSize-large);
	}
	.badge--larger {
		padding: var(--space-slim) var(--space-base);
		border-radius: var(--radius-larger);
		font-size: var(--typography--fontSize-large);
	}
	.badge--status {
		padding: 6px 10px 6px var(--space-small);
		border-radius: 12px;
		color: var(--badge-text);
		background: var(--badge-background);
	}
	/* Without the dot the asymmetric status padding reads off-center. */
	.badge--no-dot {
		padding: 6px 10px;
	}
	.badge__dot {
		width: var(--space-small);
		height: var(--space-small);
		flex: 0 0 auto;
		border-radius: var(--radius-circle);
		background: var(--badge-dot);
	}
	.badge--success {
		--badge-background: var(--color-success--surface);
		--badge-text: var(--color-success--onSurface);
		--badge-dot: var(--color-success);
	}
	.badge--warning {
		--badge-background: var(--color-warning--surface);
		--badge-text: var(--color-warning--onSurface);
		--badge-dot: var(--color-warning);
	}
	.badge--critical {
		--badge-background: var(--color-critical--surface);
		--badge-text: var(--color-critical--onSurface);
		--badge-dot: var(--color-critical);
	}
	.badge--inactive {
		--badge-background: var(--color-inactive--surface);
		--badge-text: var(--color-inactive--onSurface);
		--badge-dot: var(--color-inactive);
	}
	.badge--informative {
		--badge-background: var(--color-informative--surface);
		--badge-text: var(--color-informative--onSurface);
		--badge-dot: var(--color-informative);
	}

	:global(:root:has(.app-shell[data-presentation='classic'])) .badge {
		color: var(--classic2-body);
		background: var(--classic2-chip);
		font-family: var(--classic2-font);
	}

	:global(:root:has(.app-shell[data-presentation='classic'])) .badge--small {
		padding: 3px 8px;
		border-radius: 10px;
		font-size: var(--classic2-font-small);
	}

	:global(:root:has(.app-shell[data-presentation='classic'])) .badge--base {
		padding: 4px 10px;
		border-radius: 10px;
		font-size: var(--classic2-font-label);
	}

	:global(:root:has(.app-shell[data-presentation='classic'])) .badge--large,
	:global(:root:has(.app-shell[data-presentation='classic'])) .badge--larger {
		border-radius: 12px;
	}

	:global(:root:has(.app-shell[data-presentation='classic'])) .badge--status {
		gap: 5px;
		padding: 3px 8px;
		border-radius: 10px;
		font-size: var(--classic2-font-micro);
		font-weight: 700;
	}

	:global(:root:has(.app-shell[data-presentation='classic'])) .badge--no-dot {
		padding: 3px 8px;
	}

	:global(:root:has(.app-shell[data-presentation='classic'])) .badge__dot {
		width: 6px;
		height: 6px;
	}

	:global(:root:has(.app-shell[data-presentation='classic'])) .badge--success {
		--badge-background: var(--classic2-green-soft);
		--badge-text: var(--classic2-green);
		--badge-dot: var(--classic2-green-mid);
	}

	:global(:root:has(.app-shell[data-presentation='classic'])) .badge--warning {
		--badge-background: var(--classic2-amber-soft);
		--badge-text: var(--classic2-amber);
		--badge-dot: var(--classic2-amber-dot);
	}

	:global(:root:has(.app-shell[data-presentation='classic'])) .badge--critical {
		--badge-background: var(--classic2-rose-soft);
		--badge-text: var(--classic2-rose);
		--badge-dot: var(--classic2-rose);
	}

	:global(:root:has(.app-shell[data-presentation='classic'])) .badge--inactive {
		--badge-background: var(--classic2-chip);
		--badge-text: var(--classic2-secondary);
		--badge-dot: var(--classic2-icon-muted);
	}

	:global(:root:has(.app-shell[data-presentation='classic'])) .badge--informative {
		--badge-background: var(--classic2-blue-soft);
		--badge-text: var(--classic2-blue);
		--badge-dot: var(--classic2-blue-dot);
	}
</style>
