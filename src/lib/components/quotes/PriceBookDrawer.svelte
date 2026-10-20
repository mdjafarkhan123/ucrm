<script lang="ts">
	import { createInfiniteQuery, useQueryClient } from '@tanstack/svelte-query';
	import SidePanel from '$lib/components/layout/SidePanel.svelte';
	import bookIcon from '@tabler/icons/outline/book.svg?raw';
	import SearchInput from '$lib/components/ui/SearchInput.svelte';
	import SegmentedControl from '$lib/components/ui/SegmentedControl.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import ListLoadMore from '$lib/components/data-display/ListLoadMore.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import EmptyState from '$lib/components/data-display/EmptyState.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import CatalogItemDialog from './CatalogItemDialog.svelte';
	import FileThumb from '$lib/components/files/FileThumb.svelte';
	import {
		catalogItemsPagesKey,
		fetchCatalogItems,
		type CatalogItem,
		type CatalogItemPage,
		type PricingCategory
	} from '$lib/quotes/api';
	import listIcon from '@tabler/icons/outline/list-details.svg?raw';
	import plusIcon from '@tabler/icons/outline/plus.svg?raw';
	import imageIcon from '@tabler/icons/outline/photo.svg?raw';
	import checkIcon from '@tabler/icons/outline/check.svg?raw';

	// The price book: browse what this business already sells and drop it onto the document you are
	// editing. It stays open while you pick, so a job needing six usual items is six clicks, not six
	// round trips.
	//
	// It owns nothing on the document. Every pick is handed to the caller, which decides what a line is
	// and when it is saved — that is what lets the Request editor and the Quote workspace share this.
	let {
		open,
		currencyCode,
		locale,
		addedCounts = {},
		onAdd,
		onAddCustomLine,
		onClose
	}: {
		open: boolean;
		/** The organization's currency, so each result can show its price. */
		currencyCode?: string;
		locale?: string;
		/** How many lines on the document came from each saved item, so a pick can read as "Added". */
		addedCounts?: Record<string, number>;
		/** Appends a line from this item. Called again for a deliberate second copy. */
		onAdd: (item: CatalogItem) => void;
		/** Closes the drawer and starts a blank one-off line instead. */
		onAddCustomLine: () => void;
		onClose: () => void;
	} = $props();

	const queryClient = useQueryClient();
	const toast = getToastManager();

	let search = $state('');
	let debouncedSearch = $state('');
	let filter = $state<'all' | PricingCategory>('all');
	let creating = $state(false);
	let sessionAdded = $state(0);
	$effect(() => {
		if (open) sessionAdded = 0;
	});
	function addItem(item: CatalogItem) {
		onAdd(item);
		sessionAdded += 1;
	}

	$effect(() => {
		const term = search.trim();
		const handle = setTimeout(() => (debouncedSearch = term), 300);
		return () => clearTimeout(handle);
	});

	// Typing and the Product/Service pick are both in the key, so a change asks a new question instead of
	// filtering an answer to the old one in the browser. The catalog is never downloaded whole.
	const query = $derived({
		search: debouncedSearch,
		category: filter === 'all' ? undefined : filter
	});

	const itemsQuery = createInfiniteQuery(() => ({
		queryKey: catalogItemsPagesKey(query),
		queryFn: ({ pageParam }: { pageParam: string | undefined }) =>
			fetchCatalogItems(query, pageParam),
		initialPageParam: undefined as string | undefined,
		getNextPageParam: (page: CatalogItemPage) => page.next_cursor ?? undefined,
		enabled: open,
		// The price list is somebody's settings screen, not live data. Half a minute stops a search being
		// re-asked every time the person tabs back to a term they already tried.
		staleTime: 30_000
	}));

	const items = $derived(itemsQuery.data?.pages.flatMap((page) => page.items) ?? []);
	// Cost is internal. An empty page carries no item to infer it from, so the API says it outright.
	const canViewCost = $derived(itemsQuery.data?.pages[0]?.can_view_cost ?? false);

	const filterOptions = [
		{ value: 'all', label: 'All' },
		{ value: 'product', label: 'Products' },
		{ value: 'service', label: 'Services' }
	];

	// Built once per currency rather than once per row — a long price list would otherwise make a fresh
	// formatter for every result on every keystroke.
	const moneyFormatter = $derived(
		currencyCode
			? new Intl.NumberFormat(locale ?? 'en-US', {
					style: 'currency',
					currency: currencyCode,
					minimumFractionDigits: 2
				})
			: null
	);
	const formatMoney = (minor: number) => moneyFormatter?.format(minor / 100) ?? '';

	function created(item: CatalogItem) {
		creating = false;
		toast.success(`“${item.name}” added to the price book`);
		// The new item has to turn up the next time anybody searches for it, here or on a line's name.
		void queryClient.invalidateQueries({ queryKey: ['catalog-items'] });
		addItem(item);
	}
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<SidePanel {open} icon={bookIcon} title="Price book" subtitle="Add what you already sell" {onClose}>
	<div class="price-book">
		<div class="price-book__controls">
			<SearchInput
				id="price-book-search"
				bind:value={search}
				placeholder="Search products and services"
				ariaLabel="Search the price book"
			/>
			<div class="price-book__filters">
				<SegmentedControl
					size="small"
					value={filter}
					options={filterOptions}
					onchange={(next) => (filter = next as 'all' | PricingCategory)}
				/>
				<Button size="small" variant="tertiary" onclick={() => (creating = true)}>
					<span class="price-book__plus" aria-hidden="true">{@html plusIcon}</span>
					Create new item
				</Button>
			</div>
		</div>

		{#if itemsQuery.isPending}
			<LoadingSkeleton variant="table" rows={4} label="Loading the price book" />
		{:else if itemsQuery.isError}
			<p class="price-book__error" role="alert">
				The price book could not be loaded. You can still add a one-off line.
			</p>
		{:else if items.length === 0}
			<EmptyState
				icon={listIcon}
				title={debouncedSearch ? 'Nothing matches that' : 'Your price book is empty'}
				description={debouncedSearch
					? 'Try a shorter word, or add this as a one-off line instead.'
					: 'Save the products and services you sell often, and they will be one click away.'}
			>
				{#snippet action()}
					<Button variant="secondary" onclick={() => (creating = true)}>Create new item</Button>
				{/snippet}
			</EmptyState>
		{:else}
			<ul class="price-book__list">
				{#each items as item (item.id)}
					{@const added = addedCounts[item.id] ?? 0}
					<li class="price-book__item" class:price-book__item--added={added > 0}>
						{#if item.image_file_id}
							<FileThumb
								fileId={item.image_file_id}
								displayName={item.name}
								mimeType="image/jpeg"
								kind="image"
								processingState="available"
								hasThumbnail
								size="row"
							/>
						{:else}<span class="price-book__spot" aria-hidden="true">{@html imageIcon}</span>{/if}
						<div class="price-book__copy">
							<strong>{item.name}</strong>
							{#if item.description}<span class="price-book__description">{item.description}</span
								>{/if}
							<span class="price-book__meta">
								<span class="price-book__category price-book__category--{item.category}">
									{item.category === 'product' ? 'Product' : 'Service'}
								</span>
								{#if item.unit_label}<span>per {item.unit_label}</span>{/if}
								{#if canViewCost && item.unit_cost_minor !== undefined}
									<span class="price-book__cost">Cost {formatMoney(item.unit_cost_minor)}</span>
								{/if}
							</span>
						</div>
						<div class="price-book__figures">
							{#if moneyFormatter}
								<span class="price-book__price">{formatMoney(item.unit_price_minor)}</span>
							{/if}
							{#if added > 0}
								<!-- The button under the cursor stops being an Add the moment one lands, so a
								     second click on the same spot cannot quietly add the item twice. Wanting two
								     of something is a different, deliberate control. -->
								<span class="price-book__added">
									<span aria-hidden="true">{@html checkIcon}</span>
									{added}
								</span>
								<Button
									variant="secondary"
									size="small"
									iconOnly
									label={`Add another ${item.name}`}
									onclick={() => addItem(item)}
								>
									{@html plusIcon}
								</Button>
							{:else}
								<Button
									size="small"
									iconOnly
									label={`Add ${item.name}`}
									onclick={() => addItem(item)}>{@html plusIcon}</Button
								>
							{/if}
						</div>
					</li>
				{/each}
			</ul>
			{#if itemsQuery.hasNextPage}
				<ListLoadMore
					count={items.length}
					recordName="items"
					recordColor="quote"
					hasNextPage={itemsQuery.hasNextPage}
					isFetchingNextPage={itemsQuery.isFetchingNextPage}
					onLoadMore={() => itemsQuery.fetchNextPage()}
					endLabel="That is the whole price book."
				/>
			{/if}
		{/if}
	</div>

	{#snippet footer()}
		<div class="price-book__footer">
			<span class="price-book__session"
				><span aria-hidden="true">{@html checkIcon}</span>{sessionAdded}
				{sessionAdded === 1 ? 'line' : 'lines'} added</span
			><Button variant="secondary" size="small" onclick={onAddCustomLine}
				>{@html plusIcon}Custom line</Button
			>
			<Button variant="primary" onclick={onClose}>Done</Button>
		</div>
	{/snippet}
</SidePanel>

{#if creating}
	<CatalogItemDialog
		open={creating}
		{canViewCost}
		category={filter === 'all' ? 'service' : filter}
		onSaved={created}
		onClose={() => (creating = false)}
	/>
{/if}

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.price-book {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);

		&__controls {
			position: sticky;
			top: 0;
			z-index: var(--elevation-base);
			display: flex;
			flex-direction: column;
			gap: var(--space-small);
			padding-bottom: var(--space-small);
			background: var(--color-surface);
		}

		&__filters {
			display: flex;
			align-items: center;
			justify-content: space-between;
			gap: var(--space-small);
		}

		&__plus :global(svg) {
			display: block;
			width: 16px;
			height: 16px;
		}

		&__footer {
			display: flex;
			align-items: center;
			justify-content: space-between;
			gap: var(--space-small);
		}

		&__error {
			padding: var(--space-small) var(--space-base);
			border-radius: var(--radius-base);
			color: var(--color-critical--onSurface);
			background: var(--color-critical--surface);
			font-size: var(--typography--fontSize-small);
		}

		&__list {
			margin: 0;
			padding: 0;
			list-style: none;
		}

		&__item {
			display: flex;
			align-items: flex-start;
			justify-content: space-between;
			gap: var(--space-base);
			padding: var(--space-small) 0;

			&:not(:last-child) {
				border-bottom: var(--border-base) solid var(--color-border);
			}
		}

		&__copy {
			display: grid;
			min-width: 0;
			flex: 1;
			gap: 2px;

			strong {
				color: var(--color-heading);
				font-size: var(--typography--fontSize-base);
				font-weight: 500;
			}
		}

		&__description {
			display: -webkit-box;
			overflow: hidden;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			-webkit-box-orient: vertical;
			-webkit-line-clamp: 2;
			line-clamp: 2;
		}

		&__meta {
			display: flex;
			flex-wrap: wrap;
			gap: var(--space-small);
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__category {
			font-weight: 500;
		}

		&__cost {
			font-variant-numeric: tabular-nums;
		}

		&__figures {
			display: flex;
			flex-direction: column;
			align-items: flex-end;
			flex-shrink: 0;
			gap: var(--space-smaller);
		}

		&__price {
			color: var(--color-heading);
			font-size: var(--typography--fontSize-base);
			font-variant-numeric: tabular-nums;
			white-space: nowrap;
		}

		&__added {
			display: inline-flex;
			align-items: center;
			gap: var(--space-smaller);
			color: var(--color-success);
			font-size: var(--typography--fontSize-small);
			font-weight: 600;
			white-space: nowrap;

			:global(svg) {
				display: block;
				width: 16px;
				height: 16px;
			}
		}
	}

	.price-book__item {
		align-items: center;
		padding: 10px 0;
		gap: var(--space-slim);
	}
	.price-book__item--added {
		background: var(--color-surface--hover);
		box-shadow: inset 2px 0 0 var(--color-success);
	}
	.price-book__spot {
		display: grid;
		place-items: center;
		width: 40px;
		height: 40px;
		flex-shrink: 0;
		background: var(--color-surface--background);
		border-radius: var(--radius-tile-large);
		color: var(--color-icon--secondary);
		:global(svg) {
			width: 20px;
			height: 20px;
		}
	}
	.price-book__copy strong,
	.price-book__price {
		font-weight: 600;
	}
	.price-book__category {
		border-radius: var(--radius-circle);
		padding: 2px var(--space-small);
		font-size: var(--typography--fontSize-overline);
		font-weight: 600;
	}
	.price-book__category--product {
		background: var(--color-quote--surface);
		color: var(--color-quote--onSurface);
	}
	.price-book__category--service {
		background: var(--color-job--surface);
		color: var(--color-job--onSurface);
	}
	.price-book__added {
		background: var(--color-success);
		color: var(--color-text--reverse);
		border-radius: var(--radius-circle);
		padding: 0 10px;
		height: 32px;
	}
	.price-book__figures {
		flex-direction: row;
		align-items: center;
		flex-wrap: wrap;
		justify-content: flex-end;
		max-width: 42%;
	}
	.price-book__price {
		width: 100%;
		text-align: right;
	}
	.price-book__figures :global(button) {
		border-radius: var(--radius-circle);
	}
	.price-book__footer {
		width: 100%;
		gap: var(--space-small);
		flex-wrap: wrap;
	}
	.price-book__session {
		margin-right: auto;
		display: flex;
		gap: var(--space-small);
		align-items: center;
		font-size: var(--typography--fontSize-label);
		font-weight: 600;
		span {
			display: grid;
			place-items: center;
			width: 24px;
			height: 24px;
			border-radius: var(--radius-tile-small);
			background: var(--color-success--surface);
			color: var(--color-success);
			:global(svg) {
				width: 14px;
				height: 14px;
			}
		}
	}
	@media (max-width: 479px) {
		.price-book__filters {
			flex-wrap: wrap;
		}
		.price-book__session {
			flex-basis: 100%;
		}
	}
</style>
