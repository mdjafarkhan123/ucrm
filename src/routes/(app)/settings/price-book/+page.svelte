<script lang="ts">
	import { createInfiniteQuery, createQuery, useQueryClient } from '@tanstack/svelte-query';
	import { resolve } from '$app/paths';
	import { goto } from '$app/navigation';
	import PageContainer from '$lib/components/layout/PageContainer.svelte';
	import SettingsPageHeader from '$lib/components/settings/SettingsPageHeader.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import SearchInput from '$lib/components/ui/SearchInput.svelte';
	import FilterChip from '$lib/components/ui/FilterChip.svelte';
	import StatusBadge from '$lib/components/ui/StatusBadge.svelte';
	import DropdownMenu from '$lib/components/ui/DropdownMenu.svelte';
	import ConfirmDialog from '$lib/components/ui/ConfirmDialog.svelte';
	import DataTable, {
		type DataTableColumn,
		type DataTableSort
	} from '$lib/components/data-display/DataTable.svelte';
	import EmptyState from '$lib/components/data-display/EmptyState.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import RecordListCard from '$lib/components/data-display/RecordListCard.svelte';
	import ListLoadMore from '$lib/components/data-display/ListLoadMore.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import CatalogItemDialog from '$lib/components/quotes/CatalogItemDialog.svelte';
	import FileThumb from '$lib/components/files/FileThumb.svelte';
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
	import bookIcon from '@tabler/icons/outline/book.svg?raw';
	import dotsIcon from '@tabler/icons/outline/dots.svg?raw';
	import plusIcon from '@tabler/icons/outline/plus.svg?raw';
	import boxIcon from '@tabler/icons/outline/box.svg?raw';
	import receiptTaxIcon from '@tabler/icons/outline/receipt-tax.svg?raw';
	import listIcon from '@tabler/icons/outline/list-details.svg?raw';
	import lockIcon from '@tabler/icons/outline/lock.svg?raw';
	import pencilIcon from '@tabler/icons/outline/pencil.svg?raw';
	import trashIcon from '@tabler/icons/outline/trash.svg?raw';
	import uploadIcon from '@tabler/icons/outline/upload.svg?raw';
	import downloadIcon from '@tabler/icons/outline/download.svg?raw';

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

	// Import/export live in More Actions, the same spot the Clients list uses -- both require
	// settings.price_book.manage, which `canManage` already reflects.
	const moreActions = $derived(
		canManage
			? [
					{
						label: 'Import Price Book',
						icon: uploadIcon,
						onSelect: () => goto(resolve('/(app)/settings/price-book/import'))
					},
					{
						label: 'Export Price Book',
						icon: downloadIcon,
						onSelect: () => {
							window.location.href = '/api/exports/price-book';
						}
					}
				]
			: []
	);

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
		{ key: 'type', label: 'Type', width: '150px' },
		{ key: 'price', label: 'Price', align: 'end', sortable: true, width: '130px' },
		{ key: 'taxable', label: 'Taxable', width: '120px' },
		{ key: 'updated', label: 'Updated', sortable: true, width: '150px' }
	];
</script>

<svelte:head><title>Price Book · Settings · Contractor CRM</title></svelte:head>

<div class="page-scroller">
	<PageContainer variant="open">
		<SettingsPageHeader
			title="Price Book"
			description="The products and services you sell, ready to add to any quote or request."
			icon={bookIcon}
		>
			{#snippet actions()}
				{#if canManage}
					<DropdownMenu
						triggerLabel="More Price Book actions"
						triggerIcon={dotsIcon}
						triggerClass="price-book-page__more"
						items={moreActions}
					/>
					<Button onclick={() => (dialogState = { mode: 'create' })}>
						<!-- eslint-disable-next-line svelte/no-at-html-tags -->
						<span class="price-book-page__button-icon" aria-hidden="true">{@html plusIcon}</span>
						Add item
					</Button>
				{/if}
			{/snippet}
		</SettingsPageHeader>

		{#if itemsQuery.isPending}
			<RecordListCard title="Price Book items" padBody>
				<LoadingSkeleton variant="table" label="Loading the Price Book" rows={5} />
			</RecordListCard>
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
			<RecordListCard title="Price Book items" padBody={items.length === 0}>
				{#snippet toolbar()}
					<div class="price-book-page__search">
						<SearchInput
							id="price-book-search"
							bind:value={search}
							placeholder="Search name or description"
							ariaLabel="Search the Price Book"
							size="compact"
						/>
					</div>
					<FilterChip
						id="price-book-category"
						variant="toolbar"
						icon={boxIcon}
						label="Type"
						value={category}
						options={[
							{ value: '', label: 'Products & services' },
							{ value: 'product', label: 'Products only' },
							{ value: 'service', label: 'Services only' }
						]}
						restValue=""
						onchange={setCategory}
					/>
					<FilterChip
						id="price-book-taxable"
						variant="toolbar"
						icon={receiptTaxIcon}
						label="Taxable"
						value={taxable}
						options={[
							{ value: '', label: 'All items' },
							{ value: 'only', label: 'Taxable only' },
							{ value: 'exclude', label: 'Tax exempt only' }
						]}
						restValue=""
						onchange={setTaxable}
					/>
					{#if hasFilters}
						<Button variant="tertiary" size="small" onclick={clearFilters}>Clear filters</Button>
					{/if}
				{/snippet}

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
							variant="card"
							{columns}
							{items}
							rowId={(item) => item.id}
							caption="Price Book items"
							{sort}
							{onSortChange}
						>
							{#snippet row(item: CatalogItem)}
								<th scope="row">
									<div class="price-book-page__item">
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
										{/if}
										<div class="price-book-page__name">
											<strong>{item.name}</strong>
											{#if item.description}
												<span class="price-book-page__description">{item.description}</span>
											{/if}
										</div>
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
									<strong>{formatMoney(item.unit_price_minor)}</strong>
									{#if canViewCost && item.unit_cost_minor !== undefined}
										<span class="price-book-page__cost"
											>Cost {formatMoney(item.unit_cost_minor)}</span
										>
									{/if}
								</td>
								<td>
									<StatusBadge size="compact" status={item.is_taxable ? 'success' : 'inactive'}>
										{item.is_taxable ? 'Taxable' : 'Exempt'}
									</StatusBadge>
								</td>
								<td>
									<span title={exactTime(item.updated_at)}>{relativeTime(item.updated_at)}</span>
								</td>
							{/snippet}
							{#snippet rowActions(item: CatalogItem)}
								<DropdownMenu
									triggerLabel={`Actions for ${item.name}`}
									triggerIcon={dotsIcon}
									items={itemMenuItems(item)}
								/>
							{/snippet}
							{#snippet footer()}
								<ListLoadMore
									count={items.length}
									recordName="items"
									recordColor="inactive"
									variant="card"
									hasNextPage={itemsQuery.hasNextPage}
									isFetchingNextPage={itemsQuery.isFetchingNextPage}
									onLoadMore={() => itemsQuery.fetchNextPage()}
								/>
							{/snippet}
						</DataTable>
					</div>
				{/if}
			</RecordListCard>
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
	.price-book-page__search {
		width: 260px;
		max-width: 100%;
	}

	.price-book-page__button-icon {
		display: inline-flex;
		:global(svg) {
			width: 18px;
			height: 18px;
		}
	}

	:global(.price-book-page__more) {
		display: inline-grid;
		place-items: center;
		width: 44px;
		height: 44px;
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface);
		color: var(--color-icon);
		cursor: pointer;
		&:hover {
			background: var(--color-surface--hover);
		}
	}

	.price-book-page__table {
		:global(td),
		:global(th) {
			vertical-align: top;
		}
	}

	.price-book-page__item {
		display: flex;
		align-items: flex-start;
		gap: var(--space-small);
	}

	.price-book-page__name {
		display: grid;
		min-width: 0;
		gap: 2px;
		strong {
			color: var(--color-heading);
			font-size: var(--typography--fontSize-base);
			font-weight: 700;
		}
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
		strong {
			color: var(--color-heading);
			font-weight: 700;
		}
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
