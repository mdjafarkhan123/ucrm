<script lang="ts">
	import { Tabs as TabsPrimitive } from 'bits-ui';
	import { getContext, type Snippet } from 'svelte';

	// One tab's content. Always a child of `Tabs.svelte`, with a `value` matching one of its tabs.
	// Stacks whatever it holds in the same rhythm as a detail page's main column.
	let {
		value,
		children
	}: {
		value: string;
		children: Snippet;
	} = $props();

	// Only the open tab's content exists, so a closed tab's queries stay off until it is opened — pair the
	// tab with `Tab.onhover` to warm them. Keep unsaved edits in the page, not in a panel's own state.
	const tabs = getContext<{ value: string | undefined }>('tabs:current');
	const open = $derived(tabs.value === value);
</script>

<TabsPrimitive.Content {value} class="tab-panel">
	{#if open}
		{@render children()}
	{/if}
</TabsPrimitive.Content>

<style lang="scss">
	// The closed panel is hidden by the primitive with the `hidden` attribute, and a bare `display: flex`
	// here would outrank the browser's own `[hidden]` rule and leave every panel on screen at once.
	:global(.tab-panel:not([hidden])) {
		display: flex;
		flex-direction: column;
		gap: var(--space-large);
		padding: var(--space-base) var(--tabs-inset, 0px) 0;
	}
</style>
