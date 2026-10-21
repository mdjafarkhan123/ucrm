<script lang="ts">
	import IconTile from '$lib/components/ui/IconTile.svelte';
	import { createInfiniteQuery, createQuery } from '@tanstack/svelte-query';
	import { resolve } from '$app/paths';
	import SectionBlock from '$lib/components/layout/SectionBlock.svelte';
	import DataTable, { type DataTableColumn } from '$lib/components/data-display/DataTable.svelte';
	import EmptyState from '$lib/components/data-display/EmptyState.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import ListLoadMore from '$lib/components/data-display/ListLoadMore.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import StatusBadge from '$lib/components/ui/StatusBadge.svelte';
	import {
		CLIENT_RECENT_WORK_LIMIT,
		clientRecentWorkKey,
		clientWorkKindKey,
		fetchClientRecentWork,
		fetchClientWork,
		type ClientWorkItem,
		type ClientWorkKind,
		type ClientWorkPage
	} from '$lib/clients/work';
	import briefcaseIcon from '@tabler/icons/outline/briefcase.svg?raw';
	import clipboardListIcon from '@tabler/icons/outline/clipboard-list.svg?raw';
	import fileTextIcon from '@tabler/icons/outline/file-text.svg?raw';
	import hammerIcon from '@tabler/icons/outline/hammer.svg?raw';
	import receiptIcon from '@tabler/icons/outline/receipt.svg?raw';

	// The client page's Work overview: every request, quote, job and invoice for this client in one table,
	// newest first, with a type filter — Jobber's client-page pattern (jobber-08-screen-patterns.md).
	//
	// The work is edited on its own pages, never here, so this reads fresh every time the client page opens
	// (staleTime 0) while still painting the last answer straight away.

	let {
		clientId,
		clientName
	}: { clientId: string; /** The first name, for the line under the title. */ clientName: string } =
		$props();

	const KIND_ICONS: Record<ClientWorkKind, string> = {
		request: clipboardListIcon,
		quote: fileTextIcon,
		job: hammerIcon,
		invoice: receiptIcon
	};
	const KIND_PLURALS: Record<ClientWorkKind, string> = {
		request: 'Requests',
		quote: 'Quotes',
		job: 'Jobs',
		invoice: 'Invoices'
	};

	let kind = $state<'all' | ClientWorkKind>('all');

	const recentQuery = createQuery(() => ({
		queryKey: clientRecentWorkKey(clientId),
		queryFn: () => fetchClientRecentWork(clientId),
		staleTime: 0
	}));

	const kindQuery = createInfiniteQuery(() => ({
		queryKey: clientWorkKindKey(clientId, kind === 'all' ? 'request' : kind),
		queryFn: ({ pageParam }: { pageParam: string | undefined }) =>
			fetchClientWork(clientId, kind as ClientWorkKind, pageParam),
		initialPageParam: undefined as string | undefined,
		getNextPageParam: (lastPage: ClientWorkPage) => lastPage.next_cursor ?? undefined,
		enabled: kind !== 'all',
		staleTime: 0
	}));

	const kinds = $derived(recentQuery.data?.kinds ?? []);
	const kindOptions = $derived([
		{ value: 'all', label: 'All work' },
		...kinds.map((value) => ({ value, label: KIND_PLURALS[value] }))
	]);

	const activeQuery = $derived(kind === 'all' ? recentQuery : kindQuery);
	const items = $derived<ClientWorkItem[]>(
		kind === 'all'
			? (recentQuery.data?.items ?? [])
			: (kindQuery.data?.pages.flatMap((page) => page.items) ?? [])
	);
	const locale = $derived(
		(kind === 'all'
			? recentQuery.data?.locale
			: kindQuery.data?.pages.find((page) => page.locale)?.locale) ?? undefined
	);

	// Work from this year reads "Oct 6"; older work keeps its year so it cannot be mistaken for this year's.
	const shortFormat = $derived(new Intl.DateTimeFormat(locale, { day: 'numeric', month: 'short' }));
	const fullFormat = $derived(
		new Intl.DateTimeFormat(locale, { day: 'numeric', month: 'short', year: 'numeric' })
	);
	function formatDate(value: string) {
		const date = new Date(value);
		return (date.getFullYear() === new Date().getFullYear() ? shortFormat : fullFormat).format(
			date
		);
	}
	// One formatter per currency rather than one per figure. A plain object: nothing reads it reactively.
	const moneyFormatters: Record<string, Intl.NumberFormat> = {};
	function formatAmount(item: ClientWorkItem) {
		if (item.total_minor === null || !item.currency_code) return '—';
		const key = `${locale}:${item.currency_code}`;
		moneyFormatters[key] ??= new Intl.NumberFormat(locale, {
			style: 'currency',
			currency: item.currency_code
		});
		return moneyFormatters[key].format(item.total_minor / 100);
	}

	function recordHref(item: ClientWorkItem) {
		switch (item.kind) {
			case 'request':
				return resolve('/(app)/requests/[id=uuid]', { id: item.id });
			case 'quote':
				return resolve('/(app)/quotes/[id=uuid]', { id: item.id });
			case 'job':
				return resolve('/(app)/jobs/[id=uuid]', { id: item.id });
			case 'invoice':
				return resolve('/(app)/invoices/[id=uuid]', { id: item.id });
		}
	}

	const columns: DataTableColumn[] = [
		{ key: 'item', label: 'Item' },
		{ key: 'address', label: 'Address', width: '196px' },
		{ key: 'date', label: 'Date', width: '86px' },
		{ key: 'status', label: 'Status', width: '150px' },
		{ key: 'amount', label: 'Amount', align: 'end', width: '104px' }
	];

	// Each kind keeps its status-family colour on the list's tile.
	const KIND_TONES: Record<ClientWorkKind, string> = {
		job: 'success',
		quote: 'critical',
		request: 'warning',
		invoice: 'informative'
	};
</script>

<SectionBlock
	tone="client"
	title="Work overview"
	subtitle={`Latest work for ${clientName}`}
	icon={briefcaseIcon}
	level={2}
	class="section-block--flush client-work"
>
	{#snippet actions()}
		{#if kinds.length > 1}
			<Select
				id={`client-work-kind-${clientId}`}
				ariaLabel="Show work of type"
				options={kindOptions}
				bind:value={kind}
				class="client-work__kind"
			/>
		{/if}
	{/snippet}

	{#if activeQuery.isPending}
		<div class="client-work__pad">
			<LoadingSkeleton variant="table" label="Loading this client's work" rows={3} />
		</div>
	{:else if activeQuery.isError}
		<div class="client-work__pad">
			<ErrorState description="This client's work could not be loaded. Refresh and try again." />
		</div>
	{:else if items.length === 0}
		<div class="client-work__pad">
			<EmptyState
				icon={kind === 'all' ? briefcaseIcon : KIND_ICONS[kind]}
				title={kind === 'all' ? 'No work yet' : `No ${KIND_PLURALS[kind].toLowerCase()} yet`}
				description={kind === 'all'
					? 'Requests, quotes, jobs, and invoices for this client will all be listed here once you start creating them.'
					: `${KIND_PLURALS[kind]} for this client will be listed here.`}
			/>
		</div>
	{:else}
		<DataTable
			{columns}
			{items}
			rowId={(item) => `${item.kind}:${item.id}`}
			caption="This client's work"
			variant="card"
		>
			{#snippet row(item: ClientWorkItem)}
				<th scope="row" class="client-work__fluid client-work__fluid--item">
					<div class="client-work__item">
						<IconTile icon={KIND_ICONS[item.kind]} tone={KIND_TONES[item.kind]} size={32} />
						<div class="client-work__text">
							<a class="client-work__link" href={recordHref(item)}>{item.label}</a>
							{#if item.title}<span class="client-work__title">{item.title}</span>{/if}
						</div>
					</div>
				</th>
				<td class="client-work__fluid client-work__fluid--address" title={item.address ?? undefined}
					>{item.address ?? '—'}</td
				>
				<td class="client-work__nowrap client-work__date">{formatDate(item.created_at)}</td>
				<td>
					<StatusBadge status={item.status_tone} size="compact">{item.status_label}</StatusBadge>
				</td>
				<td
					class="align-end client-work__nowrap client-work__amount"
					class:client-work__amount--none={item.total_minor === null || !item.currency_code}
					>{formatAmount(item)}</td
				>
			{/snippet}
			{#snippet footer()}
				{#if kind === 'all'}
					{#if recentQuery.data?.has_more}
						<p class="client-work__more">
							Showing the latest {CLIENT_RECENT_WORK_LIMIT}. Pick a type above to see all of them.
						</p>
					{/if}
				{:else}
					<ListLoadMore
						count={items.length}
						recordName="items"
						recordColor="client"
						hasNextPage={kindQuery.hasNextPage}
						isFetchingNextPage={kindQuery.isFetchingNextPage}
						onLoadMore={() => kindQuery.fetchNextPage()}
						endLabel={`That is all of this client's ${KIND_PLURALS[kind].toLowerCase()}.`}
					/>
				{/if}
			{/snippet}
		</DataTable>
	{/if}
</SectionBlock>

<style lang="scss">
	// The card is 800px-ish wide, so the table fits it and never needs the list tables' 1040px floor.
	:global(.client-work) {
		--data-table-min-width: 640px;

		:global(.data-table--card tbody tr:last-child th),
		:global(.data-table--card tbody tr:last-child td) {
			border-bottom: 0;
		}
	}

	.client-work {
		&__pad {
			padding: 0 24px 24px;
		}

		&__item {
			display: flex;
			align-items: center;
			gap: 12px;
			min-width: 0;
		}

		// A tile in the colour of the record's kind, as on every list and summary elsewhere in the app.
		&__text {
			display: flex;
			flex-direction: column;
			gap: 2px;
			min-width: 0;
		}

		&__link {
			overflow: hidden;
			color: var(--color-interactive);
			font-weight: 600;
			text-decoration: none;
			text-overflow: ellipsis;

			&:hover {
				text-decoration: underline;
			}

			&:focus-visible {
				border-radius: var(--radius-small);
				outline: none;
				box-shadow: var(--shadow-focus);
			}
		}

		&__title {
			overflow: hidden;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			font-weight: 500;
			text-overflow: ellipsis;
			white-space: nowrap;
		}

		// Item and Address share whatever width Date, Status and Amount leave, and cut long text with an
		// ellipsis instead of pushing Amount off the edge. `max-width: 0` stops their text from setting the
		// column's width; the full address is on hover and on the record itself.
		&__fluid {
			max-width: 0;
			overflow: hidden;
			text-overflow: ellipsis;
			white-space: nowrap;

			&--item {
				min-width: 180px;
			}

			&--address {
				color: var(--color-text);
				font-size: var(--typography--fontSize-small);
				font-weight: 500;
			}
		}

		&__date {
			color: var(--color-text);
			font-size: var(--typography--fontSize-small);
			font-weight: 500;
		}

		&__nowrap {
			white-space: nowrap;
		}

		&__amount {
			color: var(--color-heading);
			font-variant-numeric: tabular-nums;
			font-weight: 600;

			&--none {
				color: var(--color-text--secondary);
			}
		}

		&__more {
			margin: 0;
			padding: var(--space-base);
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			text-align: center;
		}
	}

	:global(.client-work__kind) {
		min-width: 140px;
	}
</style>
