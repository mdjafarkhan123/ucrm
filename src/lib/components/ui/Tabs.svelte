<script lang="ts">
	import { Tabs as TabsPrimitive } from 'bits-ui';
	import { setContext, type Snippet } from 'svelte';

	// Approved soft capsule tabs. Use them to split one record's content into groups
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
		header,
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
		/** Compact capsule tabs with 14px labels inside a card. */
		compact?: boolean;
		/** Put the tab row somewhere else, e.g. at the foot of a card that sits above the panels. It is
		 * handed the row to draw, and the panels still follow as children. */
		header?: Snippet<[Snippet]>;
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

{#snippet list()}
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
{/snippet}

<TabsPrimitive.Root
	value={current}
	onValueChange={(next) => {
		if (onChange) onChange(next);
		else value = next;
	}}
	class={compact ? 'tabs tabs--compact' : 'tabs'}
>
	{#if header}
		{@render header(list)}
	{:else}
		{@render list()}
	{/if}
	{@render children()}
</TabsPrimitive.Root>

<style lang="scss">
	:global(.tabs) {
		--tabs-inset: 0px;
		width: 100%;
		min-width: 0;
	}
	:global(.tabs__list) {
		display: flex;
		gap: var(--space-smaller);
		padding: var(--space-smaller);
		width: 100%;
		box-sizing: border-box;
		overflow-x: auto;
		border-radius: var(--radius-circle);
		background: var(--color-surface--background);
	}
	:global(.tabs__tab) {
		display: inline-flex;
		align-items: center;
		gap: var(--space-small);
		flex: 0 0 auto;
		border: var(--border-base) solid transparent;
		border-radius: var(--radius-circle);
		padding: var(--space-small) 14px;
		color: var(--color-text--secondary);
		background: transparent;
		font-family: var(--typography--fontFamily-normal);
		font-size: var(--typography--fontSize-large);
		font-weight: 600;
		cursor: pointer;
	}
	:global(.tabs__tab:hover) {
		background: var(--color-surface--hover);
		color: var(--color-heading);
	}
	:global(.tabs__tab:focus-visible) {
		outline: 2px solid var(--color-focus);
		outline-offset: -2px;
	}
	:global(.tabs__tab:active) {
		background: var(--color-surface--active);
	}
	:global(.tabs__tab[data-state='active']) {
		border-color: var(--color-border--interactive);
		background: var(--color-surface);
		box-shadow: var(--shadow-button);
		color: var(--color-heading);
	}
	:global(.tabs--compact .tabs__tab) {
		padding: 6px var(--space-slim);
		font-size: var(--typography--fontSize-base);
	}
	:global(.tabs__badge) {
		padding: 2px 7px;
		border-radius: var(--radius-circle);
		color: var(--color-text--secondary);
		background: var(--color-surface--background--subtle);
		font-size: var(--typography--fontSize-small);
		font-variant-numeric: tabular-nums;
		line-height: 15px;
	}
	:global(.tabs__tab[data-state='active'] .tabs__badge:not(.tabs__badge--success)) {
		background: var(--color-interactive);
		color: var(--color-text--reverse);
	}
	:global(.tabs__badge--success) {
		color: var(--color-success--onSurface);
		background: var(--color-success--surface);
	}
	:global(.tabs > .tab-panel:not([hidden])) {
		padding-top: var(--space-medium);
	}
	:global(.tabs__tab:disabled) {
		color: var(--color-disabled);
		cursor: default;
		box-shadow: none;
	}
</style>
