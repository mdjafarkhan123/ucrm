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
		status?:
			| 'success'
			| 'warning'
			| 'critical'
			| 'inactive'
			| 'informative'
			| 'request'
			| 'quote'
			| 'job'
			| 'invoice'
			| 'client';
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
		gap: 6px;
		width: fit-content;
		padding: 5px 11px;
		border-radius: var(--radius-circle);
		color: var(--color-heading);
		background: var(--color-inactive--surface);
		font-size: var(--typography--fontSize-small);
		font-weight: 600;
		line-height: 1.2;
		&--small {
			padding: 3px 9px;
			font-size: var(--typography--fontSize-overline);
		}
		&--large {
			padding: 10px var(--space-slim);
			font-size: var(--typography--fontSize-large);
		}
		&--larger {
			padding: var(--space-slim) var(--space-base);
			font-size: var(--typography--fontSize-large);
		}
		&--status {
			color: var(--badge-text);
			background: var(--badge-background);
		}
		&__dot {
			width: 6px;
			height: 6px;
			flex: 0 0 auto;
			border-radius: var(--radius-circle);
			background: var(--badge-dot);
		}
	}
	@each $tone in success, warning, critical, inactive, informative, request, quote, job, invoice,
		client
	{
		.badge--#{$tone} {
			--badge-background: var(--color-#{$tone}--surface);
			--badge-text: var(--color-#{$tone}--onSurface);
			--badge-dot: var(--color-#{$tone});
		}
	}
</style>
