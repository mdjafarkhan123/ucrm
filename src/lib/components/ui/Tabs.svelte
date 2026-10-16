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
		/** A small count or figure in a pill after the label, e.g. "1" or "$2,500.00". */
		badge?: string;
		/** `success` tints the pill green, for money that came in. */
		badgeTone?: 'neutral' | 'success';
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
		compact = false,
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
		/** The App look's card tabs: 14px labels, set in the card's own side padding, with a pill for each
		 *  tab's badge and no space reserved above the panel. */
		compact?: boolean;
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
	class={compact ? 'tabs tabs--compact' : 'tabs'}
>
	<TabsPrimitive.List class="tabs__list" aria-label={label}>
		{#each tabs as tab (tab.value)}
			<TabsPrimitive.Trigger
				value={tab.value}
				class="tabs__tab"
				onmouseenter={tab.onhover}
				onfocus={tab.onhover}
			>
				{tab.label}
				{#if tab.badge}
					<span class={['tabs__badge', tab.badgeTone === 'success' && 'tabs__badge--success']}
						>{tab.badge}</span
					>
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

	// App look card tabs: set inside a card, the row takes the card's side padding and each tab can carry a
	// pill. The active marker is a thinner line in the brand colour.
	:global(.tabs--compact .tabs__list) {
		gap: 24px;
		padding-inline: 24px;
		margin-bottom: 0;
	}
	:global(.tabs--compact .tabs__tab) {
		display: inline-flex;
		align-items: center;
		gap: 8px;
		height: auto;
		padding: 0 0 12px;
		border-radius: 0;
		background: transparent;
		font-size: var(--typography--fontSize-base);
		line-height: var(--typography--lineHeight-base);
	}
	:global(.tabs--compact .tabs__tab:focus-visible) {
		background: transparent;
		box-shadow: var(--shadow-focus);
	}
	:global(.tabs--compact .tabs__tab[data-state='active'])::after {
		height: 2px;
	}
	:global(.tabs--compact .tab-panel:not([hidden])) {
		padding: 0;
	}
	:global(.tabs__badge) {
		padding: 2px 8px;
		border-radius: 999px;
		color: var(--color-text--secondary);
		background: var(--color-surface--background--subtle);
		font-size: var(--typography--fontSize-small);
		font-variant-numeric: tabular-nums;
		line-height: 15px;
	}
	:global(.tabs__badge--success) {
		color: var(--color-interactive);
		background: var(--color-success--surface);
	}
</style>
