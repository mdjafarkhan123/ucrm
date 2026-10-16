<script lang="ts">
	import type { Snippet } from 'svelte';
	import RailCard from '$lib/components/layout/RailCard.svelte';
	import SectionBlock from '$lib/components/layout/SectionBlock.svelte';

	let {
		surface = 'rail',
		title,
		icon,
		count,
		subtitle,
		actions: actionSnippet,
		children
	}: {
		surface?: 'rail' | 'section';
		title: string;
		icon?: string;
		count?: number;
		/** A line under the title that stands in for the count, in the App look. */
		subtitle?: string;
		actions?: Snippet;
		children: Snippet;
	} = $props();
</script>

{#if surface === 'section'}
	<SectionBlock {title} {icon} level={2} actions={actionSnippet}>
		{@render children()}
	</SectionBlock>
{:else}
	<RailCard {title} {icon} count={subtitle ? undefined : count} {subtitle} actions={actionSnippet}>
		{@render children()}
	</RailCard>
{/if}
