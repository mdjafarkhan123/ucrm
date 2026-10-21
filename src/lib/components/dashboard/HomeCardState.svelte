<script lang="ts">
	import IconTile from '$lib/components/ui/IconTile.svelte';
	import alertCircleIcon from '@tabler/icons/outline/alert-circle.svg?raw';
	import refreshIcon from '@tabler/icons/outline/refresh.svg?raw';
	import Button from '$lib/components/ui/Button.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import type { Snippet } from 'svelte';

	// What the inside of a Home card says when it is not showing its figures: placeholder lines while loading,
	// a "Couldn't load" message with Try again when its read failed (the rest of Home keeps working), or a
	// friendly empty line. The icon is passed in so the empty state can name the card's own subject.
	let {
		state,
		label,
		title,
		description,
		icon,
		onretry,
		rows = 3,
		children
	}: {
		state: 'loading' | 'error' | 'empty';
		/** The spoken name while loading, and the subject of the error: "money owed". */
		label: string;
		title?: string;
		description?: string;
		icon?: string;
		onretry?: () => void;
		rows?: number;
		children?: Snippet;
	} = $props();
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
{#if state === 'loading'}
	<div class="home-state home-state--loading">
		{#each Array(rows) as _, index (index)}
			<LoadingSkeleton variant="text" label={index === 0 ? `Loading ${label}` : 'Loading'} />
		{/each}
	</div>
{:else}
	<div class="home-state home-state--message" role={state === 'error' ? 'alert' : undefined}>
		<IconTile
			icon={state === 'error' ? alertCircleIcon : (icon ?? '')}
			tone={state === 'error' ? 'critical' : 'informative'}
		/>
		<p class="home-state__title">{state === 'error' ? `Couldn’t load ${label}` : title}</p>
		{#if state === 'empty' && description}<p class="home-state__description">{description}</p>{/if}
		{#if state === 'error' && onretry}
			<Button variant="secondary" size="small" onclick={onretry}>
				<span class="home-state__retry-icon" aria-hidden="true">{@html refreshIcon}</span>
				Try again
			</Button>
		{/if}
		{@render children?.()}
	</div>
{/if}

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.home-state {
		&--loading {
			display: grid;
			gap: var(--space-base);
			padding: var(--space-base) var(--space-large) var(--space-large);
		}
		&--message {
			display: grid;
			justify-items: center;
			gap: var(--space-small);
			padding: var(--space-large) var(--space-large);
			text-align: center;
		}
		&__title {
			color: var(--color-heading);
			font-size: var(--typography--fontSize-base);
			font-weight: 700;
		}
		&__description {
			max-width: 36ch;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			font-weight: 500;
		}
		&__retry-icon {
			display: inline-flex;

			:global(svg) {
				width: 16px;
				height: 16px;
			}
		}
	}
</style>
