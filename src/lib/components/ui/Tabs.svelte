<script lang="ts">
	import { Tabs as TabsPrimitive } from 'bits-ui';
	import { setContext, type Snippet } from 'svelte';

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
	export type Tab = {
		value: string;
		label: string;
		count?: number;
		/** Warms a tab's query before it is opened, matching Button's own `onhover` convention. Fires on
		 * mouse hover and keyboard focus so revealed content (CLAUDE.md rule 9) is ready by the time the
		 * tab is actually selected. */
		onhover?: () => void;
	};

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

	// Bits UI renders every panel's content and only hides the closed ones, so a closed tab would still
	// mount its components and fire their queries with the page. `TabPanel` reads the open tab from here
	// and renders only its own content, the way Radix Tabs unmounts inactive content by default.
	setContext('tabs:current', {
		get value() {
			return current;
		}
	});
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
			<TabsPrimitive.Trigger
				value={tab.value}
				class="tabs__tab"
				onmouseenter={tab.onhover}
				onfocus={tab.onhover}
			>
				<span>{tab.label}</span>
				{#if tab.count !== undefined}
					<span class="tabs__count">{tab.count}</span>
				{/if}
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

	:global {
		:root:has(.app-shell[data-presentation='classic']) .tabs__list {
			gap: 8px;
			border-color: var(--classic2-divider);
		}
		:root:has(.app-shell[data-presentation='classic']) .tabs__tab {
			display: inline-flex;
			align-items: center;
			gap: 6px;
			height: 42px;
			padding: 0 12px;
			border-radius: 10px 10px 0 0;
			background: transparent;
			color: var(--classic2-secondary);
			font-family: var(--classic2-font);
			font-size: var(--classic2-font-label);
			line-height: 1;
		}
		:root:has(.app-shell[data-presentation='classic']) .tabs__tab:hover {
			color: var(--classic2-ink);
			background: var(--classic2-surface-soft);
		}
		:root:has(.app-shell[data-presentation='classic']) .tabs__tab:focus-visible {
			background: var(--classic2-surface-soft);
			outline: 3px solid var(--classic2-green-soft);
			outline-offset: -3px;
		}
		:root:has(.app-shell[data-presentation='classic']) .tabs__tab[data-state='active'] {
			color: var(--classic2-ink);
		}
		:root:has(.app-shell[data-presentation='classic']) .tabs__tab[data-state='active']::after {
			height: 3px;
			border-radius: 3px 3px 0 0;
			background: var(--classic2-solid-green);
		}
		:root:has(.app-shell[data-presentation='classic']) .tabs__count {
			display: inline-grid;
			min-width: 18px;
			height: 18px;
			place-items: center;
			padding: 0 5px;
			border-radius: 999px;
			background: var(--classic2-chip);
			color: var(--classic2-muted);
			font-size: var(--classic2-font-micro);
			font-weight: 700;
			font-variant-numeric: tabular-nums;
		}
		:root:has(.app-shell[data-presentation='classic'])
			.tabs__tab[data-state='active']
			.tabs__count {
			background: var(--classic2-chip);
			color: var(--classic2-green);
		}
	}
</style>
