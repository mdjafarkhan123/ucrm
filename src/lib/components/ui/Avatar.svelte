<script lang="ts">
	import { Avatar as AvatarPrimitive } from 'bits-ui';
	import { initials, colorForId, type TagColor } from '$lib/collaboration/format';

	let {
		id,
		name,
		src,
		size = 'base'
	}: {
		id: string;
		name: string | null | undefined;
		src?: string | null;
		size?: 'small' | 'base' | 'medium' | 'large' | 'xlarge';
	} = $props();

	let color = $derived<TagColor>(colorForId(id));
</script>

<AvatarPrimitive.Root class="avatar avatar--{size} avatar--{color}" delayMs={100}>
	{#if src}
		<AvatarPrimitive.Image class="avatar__image" {src} alt={name ?? 'User'} />
	{/if}
	<AvatarPrimitive.Fallback class="avatar__fallback">{initials(name)}</AvatarPrimitive.Fallback>
</AvatarPrimitive.Root>

<style lang="scss">
	:global(:root:has(.app-shell[data-presentation='classic']) .avatar) {
		border: 2px solid var(--classic2-surface);
		font-family: var(--classic2-font);
		font-weight: 700;
		font-weight: 700;
	}
	:global(:root:has(.app-shell[data-presentation='classic']) .avatar--small),
	:global(:root:has(.app-shell[data-presentation='classic']) .avatar--base) {
		font-size: 11px;
	}
	:global(:root:has(.app-shell[data-presentation='classic']) .avatar--red),
	:global(:root:has(.app-shell[data-presentation='classic']) .avatar--pink) {
		--avatar-bg: var(--classic2-rose-soft);
		--avatar-fg: var(--classic2-rose);
	}
	:global(:root:has(.app-shell[data-presentation='classic']) .avatar--orange) {
		--avatar-bg: var(--classic2-amber-soft);
		--avatar-fg: var(--classic2-amber);
	}
	:global(:root:has(.app-shell[data-presentation='classic']) .avatar--green),
	:global(:root:has(.app-shell[data-presentation='classic']) .avatar--yellowGreen) {
		--avatar-bg: var(--classic2-green-soft);
		--avatar-fg: var(--classic2-green);
	}
	:global(:root:has(.app-shell[data-presentation='classic']) .avatar--teal) {
		--avatar-bg: var(--classic2-teal-soft);
		--avatar-fg: var(--classic2-teal);
	}
	:global(:root:has(.app-shell[data-presentation='classic']) .avatar--blue) {
		--avatar-bg: var(--classic2-blue-soft);
		--avatar-fg: var(--classic2-blue);
	}
	:global(:root:has(.app-shell[data-presentation='classic']) .avatar--purple) {
		--avatar-bg: var(--classic2-violet-soft);
		--avatar-fg: var(--classic2-violet);
	}

	:global(.avatar) {
		position: relative;
		display: inline-flex;
		flex: 0 0 auto;
		align-items: center;
		justify-content: center;
		overflow: hidden;
		border-radius: var(--radius-circle);
		background: var(--avatar-bg, var(--color-surface--active));
		color: var(--avatar-fg, var(--color-brand));
		font-weight: 600;
	}

	:global(.avatar--small) {
		width: 24px;
		height: 24px;
		font-size: var(--typography--fontSize-smaller);
	}

	:global(.avatar--base) {
		width: 32px;
		height: 32px;
		font-size: var(--typography--fontSize-small);
	}

	:global(.avatar--medium) {
		width: 40px;
		height: 40px;
		font-size: var(--typography--fontSize-base);
	}

	:global(.avatar--large) {
		width: 44px;
		height: 44px;
		font-size: var(--typography--fontSize-base);
	}

	:global(.avatar--xlarge) {
		width: 64px;
		height: 64px;
		font-size: var(--typography--fontSize-larger);
	}

	:global(.avatar__image) {
		width: 100%;
		height: 100%;
		object-fit: cover;
	}

	:global(.avatar__fallback) {
		display: inline-flex;
		align-items: center;
		justify-content: center;
		width: 100%;
		height: 100%;
	}

	:global(.avatar--red) {
		--avatar-bg: var(--color-critical--surface);
		--avatar-fg: var(--color-critical--onSurface);
	}
	:global(.avatar--orange) {
		--avatar-bg: var(--color-base-orange--200);
		--avatar-fg: var(--color-base-orange--600);
	}
	:global(.avatar--green) {
		--avatar-bg: var(--color-success--surface);
		--avatar-fg: var(--color-success--onSurface);
	}
	:global(.avatar--teal) {
		--avatar-bg: var(--color-base-teal--200);
		--avatar-fg: var(--color-base-teal--700);
	}
	:global(.avatar--blue) {
		--avatar-bg: var(--color-inactive--surface);
		--avatar-fg: var(--color-inactive--onSurface);
	}
	:global(.avatar--purple) {
		--avatar-bg: var(--color-dataViz--categorical--1--subtle);
		--avatar-fg: var(--color-surface);
	}
	:global(.avatar--pink) {
		--avatar-bg: var(--color-quote--surface);
		--avatar-fg: var(--color-quote--onSurface);
	}
	:global(.avatar--yellowGreen) {
		--avatar-bg: var(--color-job--surface);
		--avatar-fg: var(--color-job--onSurface);
	}
</style>
