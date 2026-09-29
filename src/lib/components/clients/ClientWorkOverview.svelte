<script lang="ts">
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
	import inboxIcon from '@tabler/icons/outline/inbox.svg?raw';
	import fileTextIcon from '@tabler/icons/outline/file-text.svg?raw';
	import toolsIcon from '@tabler/icons/outline/tools.svg?raw';
	import fileInvoiceIcon from '@tabler/icons/outline/file-invoice.svg?raw';

	// The client page's Work overview: every request, quote, job and invoice for this client in one table,
	// newest first, with a type filter — Jobber's client-page pattern (jobber-08-screen-patterns.md).
	//
	// The work is edited on its own pages, never here, so this reads fresh every time the client page opens
	// (staleTime 0) while still painting the last answer straight away.

	let { clientId }: { clientId: string } = $props();

	const KIND_ICONS: Record<ClientWorkKind, string> = {
		request: inboxIcon,
		quote: fileTextIcon,
		job: toolsIcon,
		invoice: fileInvoiceIcon
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

	const dateFormat = $derived(
		new Intl.DateTimeFormat(locale, { day: 'numeric', month: 'short', year: 'numeric' })
	);
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
		{ key: 'address', label: 'Address' },
		{ key: 'date', label: 'Date' },
		{ key: 'status', label: 'Status' },
		{ key: 'amount', label: 'Amount', align: 'end' }
	];
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<SectionBlock title="Work overview" icon={briefcaseIcon} level={2}>
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
		<LoadingSkeleton variant="table" label="Loading this client's work" rows={3} />
	{:else if activeQuery.isError}
		<ErrorState description="This client's work could not be loaded. Refresh and try again." />
	{:else if items.length === 0}
		<EmptyState
			icon={kind === 'all' ? briefcaseIcon : KIND_ICONS[kind]}
			title={kind === 'all' ? 'No work yet' : `No ${KIND_PLURALS[kind].toLowerCase()} yet`}
			description={kind === 'all'
				? 'Requests, quotes, jobs, and invoices for this client will all be listed here once you start creating them.'
				: `${KIND_PLURALS[kind]} for this client will be listed here.`}
		/>
	{:else}
		<DataTable
			{columns}
			{items}
			rowId={(item) => `${item.kind}:${item.id}`}
			caption="This client's work"
		>
			{#snippet row(item: ClientWorkItem)}
				<th scope="row" class="client-work__fluid client-work__fluid--item">
					<div class="client-work__item">
						<span class="client-work__icon" aria-hidden="true">{@html KIND_ICONS[item.kind]}</span>
						<div class="client-work__text">
							<a class="client-work__link" href={recordHref(item)}>{item.label}</a>
							{#if item.title}<span class="client-work__title">{item.title}</span>{/if}
						</div>
					</div>
				</th>
				<td class="client-work__fluid client-work__fluid--address" title={item.address ?? undefined}
					>{item.address ?? '—'}</td
				>
				<td class="client-work__nowrap">{dateFormat.format(new Date(item.created_at))}</td>
				<td>
					<StatusBadge status={item.status_tone}>{item.status_label}</StatusBadge>
				</td>
				<td class="align-end client-work__nowrap">{formatAmount(item)}</td>
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
	.client-work {
		&__item {
			display: flex;
			align-items: center;
			gap: var(--space-small);
			min-width: 0;
		}

		&__icon {
			display: inline-flex;
			flex-shrink: 0;
			color: var(--color-text--secondary);

			:global(svg) {
				width: 18px;
				height: 18px;
			}
		}

		&__text {
			display: flex;
			flex-direction: column;
			min-width: 0;
		}

		&__link {
			color: var(--color-heading);
			font-weight: 600;
			text-decoration: none;

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
			font-weight: 400;
			text-overflow: ellipsis;
			white-space: nowrap;
		}

		// Item and Address share whatever width Date, Status and Amount leave, and cut long text with an
		// ellipsis instead of pushing Amount off the edge. `max-width: 0` stops their text from setting the
		// column's width; the full address is on hover and on the record itself. Below the minimums the
		// table scrolls sideways, as every DataTable does on a phone.
		&__fluid {
			max-width: 0;
			overflow: hidden;
			text-overflow: ellipsis;
			white-space: nowrap;

			&--item {
				width: 45%;
				min-width: 150px;
			}

			&--address {
				width: 35%;
				min-width: 100px;
			}
		}

		&__nowrap {
			white-space: nowrap;
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
