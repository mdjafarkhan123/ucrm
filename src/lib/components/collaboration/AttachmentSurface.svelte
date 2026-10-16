<script lang="ts">
	import type { Snippet } from 'svelte';
	import RailCard from '$lib/components/layout/RailCard.svelte';
	import SectionBlock from '$lib/components/layout/SectionBlock.svelte';

	let {
		surface = 'rail',
		title,
		icon,
		count,
		description,
		flush = false,
		actions: actionSnippet,
		children
	}: {
		surface?: 'rail' | 'section';
		title: string;
		icon?: string;
		count?: number;
		/** One quiet line under the title that stands in for the count, in the App look. */
		description?: string;
		/** App look: the body runs edge to edge under the header; see `RailCard`. */
		flush?: boolean;
		actions?: Snippet;
		children: Snippet;
	} = $props();
</script>

{#if surface === 'section'}
	<SectionBlock {title} {icon} level={2} actions={actionSnippet}>
		{@render children()}
	</SectionBlock>
{:else}
	<RailCard {title} {icon} {count} {description} {flush} actions={actionSnippet}>
		{@render children()}
	</RailCard>
{/if}
