<script lang="ts">
	import type { Snippet } from 'svelte';
	let {
		children,
		status,
		size = 'base',
		class: className = ''
	}: {
		children: Snippet;
		status?: 'success' | 'warning' | 'critical' | 'inactive' | 'informative';
		size?: 'small' | 'base' | 'large' | 'larger';
		class?: string;
	} = $props();
</script>

<span
	class={`badge badge--${size} ${className} ${status ? `badge--status badge--${status}` : ''}`}
	role={status ? 'status' : undefined}
>
	{#if status}<span class="badge__dot" aria-hidden="true"></span>{/if}
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
</style>
