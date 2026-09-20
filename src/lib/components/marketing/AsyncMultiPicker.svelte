<script lang="ts">
	import { untrack } from 'svelte';
	import { SvelteMap } from 'svelte/reactivity';
	import { Combobox } from 'bits-ui';
	import { createQuery } from '@tanstack/svelte-query';
	import checkIcon from '@tabler/icons/outline/check.svg?raw';
	import xIcon from '@tabler/icons/outline/x.svg?raw';
	import searchIcon from '@tabler/icons/outline/search.svg?raw';

	// A search-as-you-type multi-select shared by every rule condition that resolves to a bounded set of
	// ids from a server search -- catalog items, Customers. `search` is the only thing that differs between
	// uses; everything else (debounce, chips, empty/error copy) is the same combobox shape as the single-value
	// pickers (`work/ClientPicker.svelte`, `quotes/CatalogItemPicker.svelte`) but for many values at once.
	type Item = { id: string; label: string };

	let {
		ids = $bindable<string[]>([]),
		id,
		max,
		placeholder = 'Search…',
		search,
		queryKey,
		initialItems = [],
		onChange
	}: {
		ids?: string[];
		id: string;
		max: number;
		placeholder?: string;
		search: (term: string) => Promise<Item[]>;
		/** Namespaces this picker's own search cache from every other picker using the same fetcher shape. */
		queryKey: string;
		/** Labels for ids already chosen before this picker mounted (a saved rule being reopened), so their
		 *  chips read a name instead of a raw id while the matching search page may not include them. */
		initialItems?: Item[];
		onChange?: (next: string[]) => void;
	} = $props();

	// Chosen items keep their own label once picked, from either `initialItems` or a search result, so a
	// chip never has to re-resolve its name after the search that found it has moved on. A plain `Map`
	// isn't deeply reactive under `$state` -- only reassigning the variable is tracked -- so `.set()` here
	// would silently stop chips from updating; `SvelteMap` makes its own mutations reactive.
	let chosen = new SvelteMap<string, string>(
		untrack(() => initialItems.map((item) => [item.id, item.label]))
	);

	// The label-hydration fetch that produces `initialItems` for a reopened saved group resolves after this
	// component has already mounted (it's a network round trip started in the parent dialog's onMount), so
	// the once-only seed above is usually empty for those ids. Merge newly-available labels in as they
	// arrive, without touching ids a chip already has a label for.
	$effect(() => {
		const items = initialItems;
		untrack(() => {
			for (const item of items) {
				if (!chosen.has(item.id)) chosen.set(item.id, item.label);
			}
		});
	});

	function setIds(next: string[]) {
		ids = next;
		onChange?.(next);
	}

	function add(item: Item) {
		if (ids.includes(item.id) || ids.length >= max) return;
		chosen.set(item.id, item.label);
		setIds([...ids, item.id]);
		query = '';
	}

	function remove(itemId: string) {
		setIds(ids.filter((entry) => entry !== itemId));
	}

	let open = $state(false);
	let query = $state('');
	let debouncedQuery = $state('');

	$effect(() => {
		const term = query.trim();
		const handle = setTimeout(() => (debouncedQuery = term), 300);
		return () => clearTimeout(handle);
	});

	const resultsQuery = createQuery(() => ({
		queryKey: ['marketing', 'rule-search', queryKey, debouncedQuery],
		queryFn: () => search(debouncedQuery),
		enabled: open,
		staleTime: 15_000,
		gcTime: 60_000
	}));
	const results = $derived(resultsQuery.data ?? []);
	const comboboxItems = $derived(results.map((item) => ({ value: item.id, label: item.label })));
	const atMax = $derived(ids.length >= max);
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<div class="async-multi-picker">
	{#if ids.length > 0}
		<div class="async-multi-picker__chips">
			{#each ids as itemId (itemId)}
				<span class="async-multi-picker__chip">
					{chosen.get(itemId) ?? itemId}
					<button
						type="button"
						class="async-multi-picker__chip-remove"
						aria-label={`Remove ${chosen.get(itemId) ?? 'selection'}`}
						onclick={() => remove(itemId)}
					>
						{@html xIcon}
					</button>
				</span>
			{/each}
		</div>
	{/if}

	{#if !atMax}
		<Combobox.Root
			type="single"
			value=""
			{open}
			onOpenChange={(next) => (open = next)}
			inputValue={query}
			items={comboboxItems}
			onValueChange={(itemId) => {
				const item = results.find((entry) => entry.id === itemId);
				if (item) add(item);
				open = false;
			}}
		>
			<div class="async-multi-picker__control">
				<span class="async-multi-picker__search" aria-hidden="true">{@html searchIcon}</span>
				<Combobox.Input
					{id}
					{placeholder}
					autocomplete="off"
					onfocus={() => (open = true)}
					onclick={() => (open = true)}
					oninput={(event) => {
						query = event.currentTarget.value;
						open = true;
					}}
				/>
			</div>
			<Combobox.Portal>
				<Combobox.Content
					class="async-multi-picker__menu"
					data-elevation="elevated"
					align="start"
					sideOffset={4}
					collisionPadding={8}
				>
					<Combobox.Viewport class="async-multi-picker__viewport">
						{#if resultsQuery.isPending}
							<div class="async-multi-picker__empty">Searching…</div>
						{:else if resultsQuery.isError}
							<div class="async-multi-picker__empty" role="alert">Could not search. Try again.</div>
						{:else}
							{#each results as item (item.id)}
								<Combobox.Item
									value={item.id}
									label={item.label}
									class="async-multi-picker__option"
								>
									<span class="async-multi-picker__option-label">{item.label}</span>
									{#if ids.includes(item.id)}
										<span class="async-multi-picker__check" aria-hidden="true"
											>{@html checkIcon}</span
										>
									{/if}
								</Combobox.Item>
							{:else}
								<div class="async-multi-picker__empty">
									{debouncedQuery
										? `No matches for “${debouncedQuery}”.`
										: 'Start typing to search.'}
								</div>
							{/each}
						{/if}
					</Combobox.Viewport>
				</Combobox.Content>
			</Combobox.Portal>
		</Combobox.Root>
	{/if}
</div>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.async-multi-picker {
		display: flex;
		flex-direction: column;
		gap: var(--space-small);

		&__chips {
			display: flex;
			flex-wrap: wrap;
			gap: var(--space-small);
		}

		&__chip {
			display: inline-flex;
			align-items: center;
			gap: var(--space-smaller);
			padding: 6px 10px;
			border-radius: var(--radius-large);
			color: var(--color-inactive--onSurface);
			background: var(--color-inactive--surface);
			font-size: var(--typography--fontSize-small);
		}

		&__chip-remove {
			display: grid;
			width: 16px;
			height: 16px;
			place-items: center;
			border: 0;
			border-radius: var(--radius-circle);
			color: inherit;
			background: transparent;
			cursor: pointer;
			opacity: 0.7;

			&:hover {
				background: rgba(0, 0, 0, 0.08);
				opacity: 1;
			}

			:global(svg) {
				display: block;
				width: 12px;
				height: 12px;
			}
		}

		&__control {
			position: relative;
			display: flex;
			min-height: var(--space-largest);
			align-items: center;
			border: var(--border-base) solid var(--color-border--interactive);
			border-radius: var(--radius-base);
			background: var(--color-surface);
		}

		&__control:focus-within {
			z-index: var(--elevation-base);
			box-shadow: var(--shadow-focus);
		}

		&__control :global(input) {
			width: 100%;
			min-width: 0;
			padding: var(--space-small) var(--space-base) var(--space-small) var(--space-largest);
			border: 0;
			outline: 0;
			color: var(--color-heading);
			background: transparent;
			font: inherit;
		}

		&__search {
			position: absolute;
			left: var(--space-base);
			display: grid;
			width: 16px;
			height: 16px;
			place-items: center;
			color: var(--color-icon--secondary);
			pointer-events: none;
		}

		&__search :global(svg) {
			display: block;
			width: 16px;
			height: 16px;
		}
	}

	:global(.async-multi-picker__menu) {
		z-index: var(--elevation-modal);
		width: var(--bits-floating-anchor-width);
		max-height: min(280px, var(--bits-floating-available-height));
		overflow: hidden;
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface);
		box-shadow: var(--shadow-base);
	}

	:global(.async-multi-picker__viewport) {
		max-height: inherit;
		overflow-y: auto;
		padding: var(--space-small);
	}

	:global(.async-multi-picker__option) {
		display: flex;
		width: 100%;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-small);
		padding: var(--space-small);
		border: 0;
		border-radius: var(--radius-small);
		outline: 0;
		color: var(--color-text);
		background: transparent;
		text-align: left;
		cursor: pointer;
	}

	:global(.async-multi-picker__option[data-highlighted]) {
		color: var(--color-heading);
		background: var(--color-surface--hover);
	}

	.async-multi-picker__option-label {
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}

	.async-multi-picker__check {
		display: grid;
		width: 16px;
		height: 16px;
		flex: 0 0 auto;
		place-items: center;
		color: var(--color-interactive);
	}

	.async-multi-picker__check :global(svg) {
		display: block;
		width: 16px;
		height: 16px;
	}

	.async-multi-picker__empty {
		padding: var(--space-base);
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		text-align: center;
	}
</style>
