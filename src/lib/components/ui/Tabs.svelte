<script lang="ts">
	import { Tabs as TabsPrimitive } from 'bits-ui';
	import type { Snippet } from 'svelte';

	// Underline tabs — the only tab style this app has. Use them to split one record's content into groups
	// the user opens one at a time, never for moving between pages.
	//
	// Panels are `TabPanel.svelte`, passed as children:
	//
	//   <Tabs {tabs} bind:value label="Client sections">
	//     <TabPanel value="details">…</TabPanel>
	//     <TabPanel value="communication">…</TabPanel>
	//   </Tabs>
	//
	// The row sits flush with its container by default, because the shells it lives in (RecordDetailLayout,
	// Card) are already padded. Set `--tabs-inset` on the wrapper if a caller ever needs it pulled in.
	export type Tab = { value: string; label: string };

	let {
		tabs,
		value = $bindable(),
		label,
		onChange,
		children
	}: {
		tabs: Tab[];
		/** The open tab. Defaults to the first one. */
		value?: string;
		/** Names the tab row for screen readers, e.g. "Client sections". */
		label: string;
		/** Give this when the caller owns the open tab itself — a page keeping it in the URL, say. It then
		 * takes over from `bind:value`, and `value` is only ever read. */
		onChange?: (value: string) => void;
		children: Snippet;
	} = $props();

	// A caller that does not track the open tab itself still gets a working strip.
	const current = $derived(value ?? tabs[0]?.value);
</script>

<TabsPrimitive.Root
	value={current}
	onValueChange={(next) => {
		if (onChange) onChange(next);
		else value = next;
	}}
	class="tabs"
>
	<TabsPrimitive.List class="tabs__list" aria-label={label}>
		{#each tabs as tab (tab.value)}
			<TabsPrimitive.Trigger value={tab.value} class="tabs__tab">
				{tab.label}
			</TabsPrimitive.Trigger>
		{/each}
	</TabsPrimitive.List>
	{@render children()}
</TabsPrimitive.Root>

<style lang="scss">
	:global(.tabs) {
		--tabs-inset: 0px;
		--tabs-height: 40px;

		width: 100%;
	}

	:global(.tabs__list) {
		display: flex;
		gap: var(--space-large);
		padding-inline: var(--tabs-inset);
		overflow-x: auto;
		border-bottom: var(--border-base) solid var(--color-border);
		// Pulls the row down so its divider sits flush on the panel's top edge.
		margin-bottom: calc(-1 * var(--border-base));
		-webkit-overflow-scrolling: touch;
	}

	:global(.tabs__tab) {
		position: relative;
		flex: 0 0 auto;
		height: var(--tabs-height);
		padding: var(--space-smaller) var(--space-small);
		border: none;
		border-radius: var(--radius-base) var(--radius-base) 0 0;
		background: var(--color-surface);
		color: var(--color-text--secondary);
		font-family: var(--typography--fontFamily-normal);
		font-size: var(--typography--fontSize-large);
		font-weight: 600;
		line-height: var(--typography--lineHeight-large);
		cursor: pointer;
		transition: all var(--timing-base) ease;
	}

	:global(.tabs__tab:hover),
	:global(.tabs__tab:focus) {
		color: var(--color-heading);
	}

	:global(.tabs__tab:focus-visible) {
		background: var(--color-surface--hover);
		outline: var(--border-base) solid transparent;
	}

	:global(.tabs__tab[data-state='active']) {
		color: var(--color-heading);
	}

	// The active marker sits over the row divider, spanning the full width of its tab.
	:global(.tabs__tab[data-state='active'])::after {
		content: '';
		position: absolute;
		right: 0;
		bottom: 0;
		left: 0;
		height: var(--space-smaller);
		background: var(--color-interactive);
	}
</style>
