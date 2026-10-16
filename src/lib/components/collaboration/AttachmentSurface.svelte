<script lang="ts">
	import type { Snippet } from 'svelte';
	import RailCard from '$lib/components/layout/RailCard.svelte';
	import SectionBlock from '$lib/components/layout/SectionBlock.svelte';

	let {
		surface = 'rail',
		title,
		icon,
		count,
		sub,
		flush = false,
		actions: actionSnippet,
		children
	}: {
		surface?: 'rail' | 'section';
		title: string;
		icon?: string;
		count?: number;
		sub?: string;
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
	<RailCard {title} {icon} {count} {sub} {flush} actions={actionSnippet}>
		{@render children()}
	</RailCard>
{/if}
