<script lang="ts">
	import { goto } from '$app/navigation';
	import { resolve } from '$app/paths';
	import { page } from '$app/state';
	import { createInfiniteQuery, keepPreviousData } from '@tanstack/svelte-query';
	import plusIcon from '@tabler/icons/outline/plus.svg?raw';
	import targetIcon from '@tabler/icons/outline/target.svg?raw';
	import sparklesIcon from '@tabler/icons/outline/sparkles.svg?raw';
	import searchIcon from '@tabler/icons/outline/zoom-check.svg?raw';
	import eyeIcon from '@tabler/icons/outline/eye-check.svg?raw';
	import shieldCheckIcon from '@tabler/icons/outline/shield-check.svg?raw';
	import KpiCard from '$lib/components/data-display/KpiCard.svelte';
	import EmptyState from '$lib/components/data-display/EmptyState.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import Badge from '$lib/components/ui/Badge.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import LeadFilters from '$lib/components/jafar/leads/LeadFilters.svelte';
	import {
		CONTACT_METHOD_LABELS,
		LEAD_SOURCE_LABELS,
		LEAD_STATUS_LABELS,
		LEAD_STATUS_TONES,
		countryName,
		hasLeadFilters,
		leadFilterParams,
		readLeadFilters,
		type LeadFilters as Filters,
		type LeadListItem,
		type LeadListPage,
		type LeadListTotals
	} from '$lib/jafar/leads';
	import { jafarLeadsListKey } from '$lib/jafar/query-keys';

	// Jafar business management B1: the businesses Uplift has found before they applied or became a client.

	const emptyTotals: LeadListTotals = {
		all: 0,
		matching: 0,
		statuses: {},
		countries: [],
		sources: {}
	};

	// The filters live in the address, so a refresh, the Back button and a shared link all keep them.
	const filters = $derived(readLeadFilters(page.url.searchParams));
	const filterQuery = $derived(leadFilterParams(filters).toString());

	function setFilters(next: Filters, options?: { replace?: boolean }) {
		const query = leadFilterParams(next).toString();
		// eslint-disable-next-line svelte/no-navigation-without-resolve -- the path comes from resolve(); only the query string is added.
		void goto(`${resolve('/jafar/leads')}${query ? `?${query}` : ''}`, {
			keepFocus: true,
			noScroll: true,
			replaceState: options?.replace ?? false
		});
	}

	// One request per change, and the rows on screen stay until the new ones arrive, so changing a filter never
	// flashes a skeleton. No abort signal, for the same reason as the Organizations directory: the Svelte adapter
	// re-subscribes on every key change and a consumed signal turns that into two requests per click.
	const leads = createInfiniteQuery<LeadListPage>(() => ({
		queryKey: jafarLeadsListKey(filterQuery),
		queryFn: async ({ queryKey, pageParam }) => {
			const cursor = typeof pageParam === 'string' ? `cursor=${encodeURIComponent(pageParam)}` : '';
			const query = [queryKey[3], cursor].filter(Boolean).join('&');
			const response = await fetch(`/api/jafar/leads?${query}`);
			const result = (await response.json()) as LeadListPage & { error?: string };
			if (!response.ok) throw new Error(result.error ?? 'Leads could not be loaded.');
			return result;
		},
		initialPageParam: null as string | null,
		getNextPageParam: (lastPage) => lastPage.next_cursor ?? undefined,
		placeholderData: keepPreviousData
	}));

	const pages = $derived(leads.data?.pages ?? []);
	const leadList = $derived(pages.flatMap((entry) => entry.leads));
	const totals = $derived(pages[0]?.totals ?? emptyTotals);
	// B3: the review queue holds every Lead marked Ready for review, whatever the list's filters.
	const waitingForReview = $derived(totals.statuses.ready_for_review ?? 0);

	// Today in Jafar's own time zone, as `YYYY-MM-DD`, to compare with a due date without a time-zone shift.
	function localToday() {
		const now = new Date();
		return `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}-${String(now.getDate()).padStart(2, '0')}`;
	}
	const today = localToday();

	const countFormat = new Intl.NumberFormat();
	function formatCount(value: number) {
		return countFormat.format(value);
	}

	function formatDay(day: string) {
		const [year, month, date] = day.split('-').map(Number);
		return new Intl.DateTimeFormat(undefined, { day: 'numeric', month: 'short' }).format(
			new Date(year, month - 1, date)
		);
	}

	function dueLabel(lead: LeadListItem) {
		const due = lead.next_action_due_on;
		if (!due) return '';
		if (due < today) return `Overdue · ${formatDay(due)}`;
		if (due === today) return 'Due today';
		return `Due ${formatDay(due)}`;
	}

	// A Lead still being worked needs a next step; a Lead put aside does not.
	function needsNextAction(lead: LeadListItem) {
		return !lead.next_action && lead.lead_status !== 'unsuitable';
	}
</script>

<svelte:head><title>Leads · Control Room</title></svelte:head>

<!-- eslint-disable svelte/no-at-html-tags -->
<main class="leads">
	<header class="leads__header">
		<div>
			<p class="leads__eyebrow">Business management</p>
			<h1>Leads</h1>
			<p class="leads__description">
				Trade businesses Uplift has found or heard from, before they apply or become a client.
			</p>
		</div>
		<div class="leads__header-actions">
			<Button href={resolve('/jafar/leads/review')} variant="secondary">
				<span class="leads__button-icon" aria-hidden="true">{@html shieldCheckIcon}</span>To approve
				{#if waitingForReview > 0}<span class="leads__count">{formatCount(waitingForReview)}</span
					>{/if}
			</Button>
			<Button href={resolve('/jafar/leads/new')} variant="primary">
				<span class="leads__button-icon" aria-hidden="true">{@html plusIcon}</span>Add Lead
			</Button>
		</div>
	</header>

	<section class="leads__summary" aria-label="Lead summary">
		<KpiCard
			label="All Leads"
			value={formatCount(totals.all)}
			note="Every business on file"
			icon={targetIcon}
			variant="compact"
		/>
		<KpiCard
			label="New"
			value={formatCount(totals.statuses.new ?? 0)}
			note="Not looked into yet"
			icon={sparklesIcon}
			variant="compact"
		/>
		<KpiCard
			label="Researching"
			value={formatCount(totals.statuses.researching ?? 0)}
			note="Being checked"
			icon={searchIcon}
			variant="compact"
		/>
		<KpiCard
			label="Ready for review"
			value={formatCount(totals.statuses.ready_for_review ?? 0)}
			note="Waiting for your decision"
			icon={eyeIcon}
			tone="warning"
			variant="compact"
		/>
	</section>

	<LeadFilters {filters} {totals} onChange={setFilters} />

	<div class="leads__list-meta" aria-live="polite">
		<span
			><strong>{formatCount(leadList.length)}</strong> of {formatCount(totals.matching)}
			{totals.matching === 1 ? 'Lead' : 'Leads'} shown</span
		>
	</div>

	<section
		class={['leads__panel', leads.isPlaceholderData && 'leads__panel--refreshing']}
		aria-labelledby="lead-list-title"
		aria-busy={leads.isPlaceholderData}
	>
		<h2 id="lead-list-title" class="leads__sr-only">Lead list</h2>
		{#if leads.isPending}
			<div class="leads__state">
				<LoadingSkeleton variant="table" rows={6} label="Loading Leads" />
			</div>
		{:else if leads.isError}
			<div class="leads__state">
				<ErrorState
					title="Leads could not be loaded"
					description={leads.error.message}
					retry={() => leads.refetch()}
				/>
			</div>
		{:else if leadList.length === 0}
			<div class="leads__state">
				{#if hasLeadFilters(filters)}
					<EmptyState
						title="No matching Leads"
						description="Try another search term or loosen a filter."
					/>
				{:else}
					<EmptyState
						title="No Leads yet"
						description="Add a business you have found, with where you found it and what to do next."
					/>
				{/if}
			</div>
		{:else}
			<div class="leads__table-wrap">
				<table class="leads__table">
					<thead>
						<tr>
							<th scope="col">Business</th>
							<th scope="col">Country</th>
							<th scope="col">Source</th>
							<th scope="col">Contact</th>
							<th scope="col">Status</th>
							<th scope="col">Next action</th>
							<th scope="col">Owner</th>
						</tr>
					</thead>
					<tbody>
						{#each leadList as lead (lead.id)}
							<tr>
								<th scope="row" class="leads__business">
									<a
										class="leads__business-link"
										href={resolve('/jafar/(protected)/leads/[id]', { id: lead.id })}
										>{lead.business_name}</a
									>
									<small>{lead.trade}{lead.website_host ? ` · ${lead.website_host}` : ''}</small>
								</th>
								<td data-label="Country">{countryName(lead.country_code)}</td>
								<td data-label="Source">{LEAD_SOURCE_LABELS[lead.source]}</td>
								<td data-label="Contact">
									{#if lead.contact_name}<span class="leads__contact-name">{lead.contact_name}</span
										>{/if}
									{#if lead.contact_methods.length}
										<small class="leads__contact-method">
											{CONTACT_METHOD_LABELS[lead.contact_methods[0].kind]}: {lead
												.contact_methods[0].value}{lead.contact_methods.length > 1
												? ` +${lead.contact_methods.length - 1}`
												: ''}
										</small>
									{:else if !lead.contact_name}
										<span class="leads__muted">No contact details</span>
									{/if}
								</td>
								<td data-label="Status">
									<Badge status={LEAD_STATUS_TONES[lead.lead_status]} size="small"
										>{LEAD_STATUS_LABELS[lead.lead_status]}</Badge
									>
								</td>
								<td data-label="Next action">
									{#if lead.next_action}
										<span class="leads__next-action">{lead.next_action}</span>
										<small
											class={[
												'leads__due',
												lead.next_action_due_on &&
													lead.next_action_due_on < today &&
													'leads__due--overdue'
											]}>{dueLabel(lead)}</small
										>
									{:else if needsNextAction(lead)}
										<span class="leads__missing">No next action</span>
									{:else}
										<span class="leads__muted">&mdash;</span>
									{/if}
								</td>
								<td data-label="Owner">Jafar</td>
							</tr>
						{/each}
					</tbody>
				</table>
			</div>
		{/if}
		<footer class="leads__footer">
			{#if leads.hasNextPage}
				<Button
					type="button"
					variant="secondary"
					disabled={leads.isFetchingNextPage}
					onclick={() => leads.fetchNextPage()}
				>
					{leads.isFetchingNextPage ? 'Loading more…' : 'Load more'}
				</Button>
			{:else if leadList.length > 0}
				<span>That is every matching Lead.</span>
			{/if}
		</footer>
	</section>
</main>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.leads {
		min-width: 0;
		display: grid;
		gap: var(--space-large);
	}

	.leads h1,
	.leads h2,
	.leads p {
		margin: 0;
	}

	.leads h1 {
		color: var(--color-heading);
		font-family: var(--typography--fontFamily-display);
		font-size: var(--typography--fontSize-jumbo);
		font-weight: 900;
		line-height: var(--typography--lineHeight-minuscule);
	}

	.leads__header,
	.leads__list-meta,
	.leads__footer {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-base);
	}

	.leads__header {
		align-items: flex-start;
		padding-bottom: var(--space-large);
		border-bottom: var(--border-base) solid var(--color-border);
	}

	.leads__eyebrow {
		margin-bottom: var(--space-small) !important;
		color: var(--color-interactive);
		font-size: var(--typography--fontSize-small);
		font-weight: 700;
		letter-spacing: var(--typography--letterSpacing-loose);
		text-transform: uppercase;
	}

	.leads__description {
		max-width: 65ch;
		margin-top: var(--space-small) !important;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-large);
		line-height: var(--typography--lineHeight-large);
	}

	.leads__header-actions {
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-small);
	}

	.leads__count {
		min-width: 22px;
		margin-left: var(--space-small);
		padding: 0 var(--space-smaller);
		border-radius: var(--radius-circle);
		background: var(--color-warning--surface);
		color: var(--color-warning--onSurface);
		font-size: var(--typography--fontSize-small);
		font-weight: 700;
		line-height: 22px;
		text-align: center;
	}

	.leads__button-icon {
		display: inline-flex;
		margin-right: var(--space-smaller);

		:global(svg) {
			width: 18px;
			height: 18px;
		}
	}

	.leads__summary {
		display: grid;
		grid-template-columns: repeat(4, minmax(0, 1fr));
		gap: var(--space-base);
	}

	.leads__list-meta,
	.leads__footer {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}

	.leads__list-meta {
		padding: 0 var(--space-small);
	}

	.leads__list-meta strong {
		color: var(--color-heading);
		font-size: var(--typography--fontSize-large);
	}

	.leads__panel {
		overflow: hidden;
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface);
		box-shadow: var(--shadow-low);
		transition: opacity var(--timing-quick);
	}

	// While a changed filter is on its way, the rows already shown stay and soften instead of vanishing.
	.leads__panel--refreshing {
		opacity: 0.6;
	}

	.leads__table {
		width: 100%;
		border-collapse: collapse;
		color: var(--color-text);
		font-size: var(--typography--fontSize-base);
	}

	.leads__table th,
	.leads__table td {
		padding: var(--space-base) var(--space-large);
		border-bottom: var(--border-base) solid var(--color-border);
		text-align: left;
		vertical-align: top;
	}

	.leads__table thead {
		background: var(--color-surface--background--subtle);
	}

	.leads__table thead th {
		color: var(--color-text--secondary);
		font-weight: 700;
		white-space: nowrap;
	}

	.leads__table tbody tr {
		position: relative;
		cursor: pointer;
		transition: background-color var(--timing-quick);

		&:hover {
			background: var(--color-surface--hover);
		}

		&:last-child th,
		&:last-child td {
			border-bottom: 0;
		}
	}

	.leads__business {
		min-width: 220px;
		color: var(--color-heading);
		font-weight: 700;

		.leads__business-link,
		small {
			display: block;
		}

		// The whole row opens the Lead: the link's hit area stretches over it.
		.leads__business-link {
			color: inherit;
			text-decoration: none;

			&::after {
				content: '';
				position: absolute;
				inset: 0;
			}

			&:focus-visible {
				outline: none;

				&::after {
					box-shadow: inset var(--shadow-focus);
				}
			}
		}

		tr:hover & .leads__business-link {
			color: var(--color-interactive);
			text-decoration: underline;
			text-underline-offset: 3px;
		}

		small {
			margin-top: var(--space-smaller);
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			font-weight: 400;
			overflow-wrap: anywhere;
		}
	}

	.leads__contact-name,
	.leads__next-action {
		display: block;
		color: var(--color-heading);
	}

	.leads__contact-method,
	.leads__due {
		display: block;
		margin-top: var(--space-smaller);
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		overflow-wrap: anywhere;
	}

	.leads__due {
		white-space: nowrap;
	}

	.leads__due--overdue {
		color: var(--color-critical);
		font-weight: 600;
	}

	.leads__missing {
		color: var(--color-warning--onSurface);
		font-weight: 600;
	}

	.leads__muted {
		color: var(--color-text--secondary);
	}

	.leads__state {
		padding: var(--space-large);
	}

	.leads__footer {
		min-height: 24px;
		padding: var(--space-base) var(--space-large);
		border-top: var(--border-base) solid var(--color-border);
	}

	.leads__sr-only {
		position: absolute;
		width: 1px;
		height: 1px;
		padding: 0;
		margin: -1px;
		overflow: hidden;
		clip: rect(0, 0, 0, 0);
		white-space: nowrap;
		border: 0;
	}

	@media (max-width: 1100px) {
		.leads__table th,
		.leads__table td {
			padding: var(--space-slim) var(--space-base);
		}
	}

	@media (max-width: 900px) {
		.leads__summary {
			grid-template-columns: repeat(2, minmax(0, 1fr));
		}
	}

	// On a phone each Lead becomes a card: the business on top, then its details in labelled pairs.
	@media (max-width: 767px) {
		.leads__header,
		.leads__list-meta,
		.leads__footer {
			align-items: stretch;
			flex-direction: column;
		}

		.leads__table thead {
			position: absolute;
			width: 1px;
			height: 1px;
			overflow: hidden;
			clip: rect(0, 0, 0, 0);
		}

		.leads__table,
		.leads__table tbody,
		.leads__table tr,
		.leads__table th,
		.leads__table td {
			display: block;
		}

		.leads__table tbody tr {
			display: grid;
			grid-template-columns: minmax(0, 1fr) minmax(0, 1fr);
			gap: var(--space-slim) var(--space-base);
			padding: var(--space-base);
			border-bottom: var(--border-base) solid var(--color-border);

			&:last-child {
				border-bottom: 0;
			}
		}

		.leads__table th,
		.leads__table td,
		.leads__table tbody tr:last-child th,
		.leads__table tbody tr:last-child td {
			padding: 0;
			border-bottom: 0;
		}

		.leads__table .leads__business {
			grid-column: 1 / -1;
			min-width: 0;
		}

		.leads__table td::before {
			content: attr(data-label);
			display: block;
			margin-bottom: 2px;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			font-weight: 600;
		}
	}

	@media (max-width: 639px) {
		.leads h1 {
			font-size: 28px;
		}
	}
</style>
