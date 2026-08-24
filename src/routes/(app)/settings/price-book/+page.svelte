<script lang="ts">
	import { createInfiniteQuery, createQuery, useQueryClient } from '@tanstack/svelte-query';
	import { resolve } from '$app/paths';
	import Breadcrumbs from '$lib/components/layout/Breadcrumbs.svelte';
	import PageContainer from '$lib/components/layout/PageContainer.svelte';
	import PageHeader from '$lib/components/layout/PageHeader.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import SearchInput from '$lib/components/ui/SearchInput.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import StatusBadge from '$lib/components/ui/StatusBadge.svelte';
	import DropdownMenu from '$lib/components/ui/DropdownMenu.svelte';
	import ConfirmDialog from '$lib/components/ui/ConfirmDialog.svelte';
	import DataTable, {
		type DataTableColumn,
		type DataTableSort
	} from '$lib/components/data-display/DataTable.svelte';
	import EmptyState from '$lib/components/data-display/EmptyState.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import FilterBar from '$lib/components/data-display/FilterBar.svelte';
	import FilterField from '$lib/components/data-display/FilterField.svelte';
	import ListLoadMore from '$lib/components/data-display/ListLoadMore.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import CatalogItemDialog from '$lib/components/quotes/CatalogItemDialog.svelte';
	import { relativeTime, exactTime } from '$lib/collaboration/format';
	import {
		catalogItemsKey,
		fetchCatalogItems,
		fetchQuoteOverview,
		quoteCountsKey,
		type CatalogItem,
		type CatalogItemPage,
		type CatalogSortKey,
		type PricingCategory
	} from '$lib/quotes/api';
	import { deletePriceBookItem } from '$lib/settings/api';
	import listIcon from '@tabler/icons/outline/list-details.svg?raw';
	import lockIcon from '@tabler/icons/outline/lock.svg?raw';
	import pencilIcon from '@tabler/icons/outline/pencil.svg?raw';
	import trashIcon from '@tabler/icons/outline/trash.svg?raw';

	// Settings → Price Book: the same `catalog_items` the Quote/Request picker already reads, managed here
	// with sort, filters, and permanent delete. `can_manage` rides on the very list fetch this page needs
	// anyway, so a person without `settings.price_book.manage` sees an access message instead of the table —
	// no separate round trip just to decide that.
	const queryClient = useQueryClient();
	const toast = getToastManager();

	let search = $state('');
	let debouncedSearch = $state('');
	let category = $state<'' | PricingCategory>('');
	let taxable = $state<'' | 'only' | 'exclude'>('');
	let sort = $state<DataTableSort>({ key: 'name', direction: 'asc' });
	let dialogState = $state<{ mode: 'create' | 'update'; itemId?: string } | null>(null);
	let deleteTarget = $state<CatalogItem | null>(null);
	let deleting = $state(false);

	// One row for the whole tenant, cached the same way `requests/new` already reuses it — nothing here
	// waits on it, and prices only ever need to fall back to a formatter while it is still loading.
	const overviewQuery = createQuery(() => ({
		queryKey: quoteCountsKey,
		queryFn: fetchQuoteOverview,
		staleTime: 60_000
	}));

	$effect(() => {
		const value = search;
		const handle = setTimeout(() => (debouncedSearch = value), 300);
		return () => clearTimeout(handle);
	});

	const filters = $derived({
		search: debouncedSearch,
		category: category || undefined,
		taxable: taxable || undefined,
		sort: sort.key as CatalogSortKey,
		dir: sort.direction
	});

	const itemsQuery = createInfiniteQuery(() => ({
		queryKey: catalogItemsKey(filters),
		queryFn: ({ pageParam }: { pageParam: string | undefined }) =>
			fetchCatalogItems(filters, pageParam),
		initialPageParam: undefined as string | undefined,
		getNextPageParam: (page: CatalogItemPage) => page.next_cursor ?? undefined,
		staleTime: 30_000
	}));

	const items = $derived(itemsQuery.data?.pages.flatMap((page) => page.items) ?? []);
	const canViewCost = $derived(itemsQuery.data?.pages[0]?.can_view_cost ?? false);
	const canManage = $derived(itemsQuery.data?.pages[0]?.can_manage ?? false);
	const hasFilters = $derived(Boolean(search.trim() || category || taxable));

	const moneyFormatter = $derived(
		new Intl.NumberFormat(overviewQuery.data?.locale ?? 'en-US', {
			style: 'currency',
			currency: overviewQuery.data?.currency_code ?? 'USD',
			minimumFractionDigits: 2
		})
	);
	const formatMoney = (minor: number) => moneyFormatter.format(minor / 100);

	function setCategory(value: string) {
		category = value as '' | PricingCategory;
	}
	function setTaxable(value: string) {
		taxable = value as '' | 'only' | 'exclude';
	}
	function clearFilters() {
		search = '';
		debouncedSearch = '';
		category = '';
		taxable = '';
	}
	function onSortChange(key: string) {
		sort =
			sort.key === key
				? { key, direction: sort.direction === 'asc' ? 'desc' : 'asc' }
				: { key, direction: 'asc' };
	}

	async function invalidate() {
		await queryClient.invalidateQueries({ queryKey: ['catalog-items'] });
	}

	function itemMenuItems(item: CatalogItem) {
		return [
			{
				label: 'Edit',
				icon: pencilIcon,
				onSelect: () => (dialogState = { mode: 'update', itemId: item.id })
			},
			{
				label: 'Delete',
				icon: trashIcon,
				destructive: true,
				onSelect: () => (deleteTarget = item)
			}
		];
	}

	function itemSaved() {
		const wasUpdate = dialogState?.mode === 'update';
		dialogState = null;
		void invalidate();
		toast.success(wasUpdate ? 'Item saved.' : 'Item added.');
	}

	async function confirmDelete() {
		if (!deleteTarget) return;
		deleting = true;
		try {
			await deletePriceBookItem(deleteTarget.id, { expected_revision: deleteTarget.revision });
			deleteTarget = null;
			await invalidate();
			toast.success('Item deleted.');
		} catch (cause) {
			toast.error(cause instanceof Error ? cause.message : 'That item could not be deleted.');
		} finally {
			deleting = false;
		}
	}

	const columns: DataTableColumn[] = [
		{ key: 'name', label: 'Name', sortable: true },
		{ key: 'type', label: 'Type' },
		{ key: 'price', label: 'Price', align: 'end', sortable: true },
		{ key: 'taxable', label: 'Taxable' },
		{ key: 'updated', label: 'Updated', sortable: true }
	];
</script>

<svelte:head><title>Price Book · Settings · Contractor CRM</title></svelte:head>

<div class="page-scroller">
	<PageContainer variant="fill">
		<Breadcrumbs
			items={[{ label: 'Settings', href: resolve('/(app)/settings') }, { label: 'Price Book' }]}
		/>

		<PageHeader
			eyebrow="Business"
			title="Price Book"
			description="The products and services you sell, ready to add to any quote or request."
		>
			{#snippet actions()}
				{#if canManage}
					<Button onclick={() => (dialogState = { mode: 'create' })}>Add item</Button>
				{/if}
			{/snippet}
		</PageHeader>

		{#if itemsQuery.isPending}
			<LoadingSkeleton variant="table" label="Loading the Price Book" rows={5} />
		{:else if itemsQuery.isError}
			<ErrorState
				description="The Price Book could not be loaded. Refresh and try again."
				retry={() => itemsQuery.refetch()}
			/>
		{:else if !canManage}
			<EmptyState
				icon={lockIcon}
				title="You don't have access to the Price Book"
				description="Only owners and administrators can manage it."
			/>
		{:else}
			<FilterBar onClear={hasFilters ? clearFilters : undefined}>
				<FilterField id="price-book-search" label="Search">
					<SearchInput
						id="price-book-search"
						bind:value={search}
						placeholder="Search name or description"
						ariaLabel="Search the Price Book"
					/>
				</FilterField>
				<FilterField id="price-book-category" label="Type">
					<Select
						id="price-book-category"
						value={category}
						onchange={setCategory}
						options={[
							{ value: '', label: 'Products & services' },
							{ value: 'product', label: 'Products only' },
							{ value: 'service', label: 'Services only' }
						]}
					/>
				</FilterField>
				<FilterField id="price-book-taxable" label="Taxable">
					<Select
						id="price-book-taxable"
						value={taxable}
						onchange={setTaxable}
						options={[
							{ value: '', label: 'All items' },
							{ value: 'only', label: 'Taxable only' },
							{ value: 'exclude', label: 'Tax exempt only' }
						]}
					/>
				</FilterField>
			</FilterBar>

			{#if items.length === 0}
				<EmptyState
					icon={listIcon}
					title={hasFilters ? 'Nothing matches that' : 'Your Price Book is empty'}
					description={hasFilters
						? 'Try a different search term or clear your filters.'
						: 'Add the products and services you sell often, and they will be one click away on a quote.'}
				>
					{#snippet action()}
						<Button variant="secondary" onclick={() => (dialogState = { mode: 'create' })}>
							Add item
						</Button>
					{/snippet}
				</EmptyState>
			{:else}
				<div class="price-book-page__table">
					<DataTable
						{columns}
						{items}
						rowId={(item) => item.id}
						caption="Price Book items"
						{sort}
						{onSortChange}
					>
						{#snippet row(item: CatalogItem)}
							<th scope="row">
								<div class="price-book-page__name">
									<strong>{item.name}</strong>
									{#if item.description}
										<span class="price-book-page__description">{item.description}</span>
									{/if}
								</div>
							</th>
							<td>
								<div class="price-book-page__type">
									<span>{item.category === 'product' ? 'Product' : 'Service'}</span>
									{#if item.is_labor}<span class="price-book-page__labor">Labor</span>{/if}
									{#if item.unit_label}<span>per {item.unit_label}</span>{/if}
								</div>
							</td>
							<td class="price-book-page__price">
								{formatMoney(item.unit_price_minor)}
								{#if canViewCost && item.unit_cost_minor !== undefined}
									<span class="price-book-page__cost">Cost {formatMoney(item.unit_cost_minor)}</span
									>
								{/if}
							</td>
							<td>
								<StatusBadge status={item.is_taxable ? 'success' : 'inactive'}>
									{item.is_taxable ? 'Taxable' : 'Exempt'}
								</StatusBadge>
							</td>
							<td>
								<span title={exactTime(item.updated_at)}>{relativeTime(item.updated_at)}</span>
							</td>
						{/snippet}
						{#snippet rowActions(item: CatalogItem)}
							<DropdownMenu triggerLabel={`Actions for ${item.name}`} items={itemMenuItems(item)} />
						{/snippet}
						{#snippet footer()}
							<ListLoadMore
								hasNextPage={itemsQuery.hasNextPage}
								isFetchingNextPage={itemsQuery.isFetchingNextPage}
								onLoadMore={() => itemsQuery.fetchNextPage()}
							/>
						{/snippet}
					</DataTable>
				</div>
			{/if}
		{/if}
	</PageContainer>
</div>

{#if dialogState}
	<CatalogItemDialog
		open={true}
		mode={dialogState.mode}
		itemId={dialogState.itemId}
		{canViewCost}
		managed
		onSaved={itemSaved}
		onClose={() => (dialogState = null)}
	/>
{/if}

<ConfirmDialog
	open={deleteTarget !== null}
	title="Delete this item?"
	tone="critical"
	destructive
	confirmLabel="Delete item"
	loading={deleting}
	onConfirm={() => void confirmDelete()}
	onClose={() => (deleteTarget = null)}
>
	{#if deleteTarget}
		<p>
			This can't be undone. "{deleteTarget.name}" will no longer be available to add to a quote or
			request. Existing quotes and requests that already used it keep what they already have.
		</p>
	{/if}
</ConfirmDialog>

<style lang="scss">
	.price-book-page__table {
		:global(td),
		:global(th) {
			vertical-align: top;
		}
	}

	.price-book-page__name {
		display: grid;
		gap: 2px;
	}

	.price-book-page__description {
		display: -webkit-box;
		overflow: hidden;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		font-weight: 400;
		-webkit-box-orient: vertical;
		-webkit-line-clamp: 2;
		line-clamp: 2;
	}

	.price-book-page__type {
		display: flex;
		flex-direction: column;
		gap: 2px;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}

	.price-book-page__labor {
		color: var(--color-informative--onSurface);
		font-weight: 600;
	}

	.price-book-page__price {
		font-variant-numeric: tabular-nums;
		text-align: end;
	}

	.price-book-page__cost {
		display: block;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}

	@media (max-width: 767px) {
		.price-book-page__table :global(th:nth-child(2)),
		.price-book-page__table :global(td:nth-child(2)),
		.price-book-page__table :global(th:nth-child(4)),
		.price-book-page__table :global(td:nth-child(4)),
		.price-book-page__table :global(th:nth-child(5)),
		.price-book-page__table :global(td:nth-child(5)) {
			display: none;
		}
	}
</style>
