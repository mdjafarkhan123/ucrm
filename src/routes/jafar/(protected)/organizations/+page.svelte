<script lang="ts">
	import { goto } from '$app/navigation';
	import { resolve } from '$app/paths';
	import { page } from '$app/state';
	import { createInfiniteQuery, keepPreviousData } from '@tanstack/svelte-query';
	import alertIcon from '@tabler/icons/outline/alert-triangle.svg?raw';
	import arrowRightIcon from '@tabler/icons/outline/arrow-right.svg?raw';
	import buildingIcon from '@tabler/icons/outline/building.svg?raw';
	import checkIcon from '@tabler/icons/outline/check.svg?raw';
	import pauseIcon from '@tabler/icons/outline/player-pause.svg?raw';
	import KpiCard from '$lib/components/data-display/KpiCard.svelte';
	import EmptyState from '$lib/components/data-display/EmptyState.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import Badge from '$lib/components/ui/Badge.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import DirectoryFilters from '$lib/components/jafar/organization/DirectoryFilters.svelte';
	import {
		directoryFilterParams,
		directoryFiltersAreComplete,
		readDirectoryFilters,
		type DirectoryAttentionReason as AttentionReason,
		type DirectoryFilters as Filters,
		type DirectoryLifecycle as LifecycleStatus,
		type DirectoryTotals
	} from '$lib/jafar/organization-directory-filters';
	import { jafarOrganizationsListKey } from '$lib/jafar/query-keys';

	type Organization = {
		id: string;
		name: string;
		slug: string;
		lifecycle_status: LifecycleStatus;
		created_at: string;
		updated_at: string;
		member_count: number;
		attention_reasons: AttentionReason[];
		// The package the organization is on today, or null when it has none.
		package: {
			package_id: string;
			name: string;
			edition_number: number | null;
			billing_interval: 'month' | 'year';
		} | null;
	};
	type DirectoryPage = {
		organizations: Organization[];
		next_cursor: string | null;
		totals: DirectoryTotals;
		error?: string;
	};

	// Urgency order matches the database function's own ordering, so a badge list here reads the
	// same way the attention-reason filter counts do.
	const attentionMeta: Record<AttentionReason, { label: string; tone: 'critical' | 'warning' }> = {
		access_overdue: { label: 'Access overdue', tone: 'critical' },
		payment_overdue: { label: 'Payment overdue', tone: 'critical' },
		renewal_due: { label: 'Renewal due', tone: 'warning' },
		administrator_missing: { label: 'No administrator', tone: 'critical' },
		administrator_ownership_unclear: { label: 'Multiple owners', tone: 'warning' },
		setup_or_recovery_failed: { label: 'Setup or recovery issue', tone: 'critical' },
		expiring_soon: { label: 'Expiring soon', tone: 'warning' },
		email_setup_requested: { label: 'Email setup requested', tone: 'warning' }
	};
	const attentionLabels = Object.fromEntries(
		Object.entries(attentionMeta).map(([reason, meta]) => [reason, meta.label])
	) as Record<AttentionReason, string>;

	const emptyTotals: DirectoryTotals = {
		all: 0,
		active: 0,
		suspended: 0,
		pending_closure: 0,
		closed: 0,
		no_package: 0,
		packages: [],
		matching: 0,
		attention: {
			access_overdue: 0,
			payment_overdue: 0,
			renewal_due: 0,
			expiring_soon: 0,
			administrator_missing: 0,
			administrator_ownership_unclear: 0,
			setup_or_recovery_failed: 0,
			email_setup_requested: 0
		}
	};

	// The filters live in the address, so a refresh, the Back button and a shared link all keep them. A link
	// that names something the page does not know falls back to "no filter" for that part.
	const filters = $derived(readDirectoryFilters(page.url.searchParams));
	// A custom range with no dates is not a question the server can answer yet; the list keeps what it had.
	const applied = $derived(
		directoryFiltersAreComplete(filters) ? filters : { ...filters, joined: '' as const }
	);
	const filterQuery = $derived(directoryFilterParams(applied).toString());

	function setFilters(next: Filters, options?: { replace?: boolean }) {
		const query = directoryFilterParams(next).toString();
		// Each change is its own history entry, so Back steps through the filters the way it steps through
		// pages. Typing a search is the exception: it replaces the entry. Focus stays where it was and the page
		// does not jump to the top.
		// eslint-disable-next-line svelte/no-navigation-without-resolve -- the path comes from resolve(); only the query string is added.
		void goto(`${resolve('/jafar/organizations')}${query ? `?${query}` : ''}`, {
			keepFocus: true,
			noScroll: true,
			replaceState: options?.replace ?? false
		});
	}

	// One request per change, and the rows already on screen stay until the new ones arrive, so ticking
	// filters never flashes a skeleton. The request does not take TanStack's abort signal: the Svelte adapter
	// re-subscribes on every key change, and a consumed signal turns that into cancel-and-fetch-again (two
	// requests per click). Without it the second subscribe joins the request already in flight.
	const organizations = createInfiniteQuery<DirectoryPage>(() => ({
		queryKey: jafarOrganizationsListKey(filterQuery),
		queryFn: async ({ queryKey, pageParam }) => {
			// The filters this answer is cached under, never whatever the page has moved on to since.
			const cursor = typeof pageParam === 'string' ? `cursor=${encodeURIComponent(pageParam)}` : '';
			const query = [queryKey[3], cursor].filter(Boolean).join('&');
			const response = await fetch(`/api/jafar/organizations?${query}`);
			const result = (await response.json()) as DirectoryPage;
			if (!response.ok) throw new Error(result.error ?? 'Organizations could not be loaded.');
			return result;
		},
		initialPageParam: null as string | null,
		getNextPageParam: (lastPage) => lastPage.next_cursor ?? undefined,
		placeholderData: keepPreviousData
	}));

	const pages = $derived(organizations.data?.pages ?? []);
	const organizationList = $derived(pages.flatMap((entry) => entry.organizations));
	const totals = $derived(pages[0]?.totals ?? emptyTotals);

	function lifecycleLabel(lifecycle: LifecycleStatus) {
		if (lifecycle === 'active') return 'Active';
		if (lifecycle === 'pending_closure') return 'Closing';
		if (lifecycle === 'closed') return 'Closed';
		return 'Suspended';
	}

	function lifecycleTone(lifecycle: LifecycleStatus): 'success' | 'critical' | 'warning' {
		if (lifecycle === 'active') return 'success';
		return 'critical';
	}

	function formatDate(value: string) {
		return new Intl.DateTimeFormat(undefined, { dateStyle: 'medium' }).format(new Date(value));
	}
</script>

<svelte:head><title>Organizations · Control Room</title></svelte:head>

<!-- eslint-disable svelte/no-at-html-tags -->
<main class="organization-directory">
	<header class="organization-directory__header">
		<div>
			<p class="organization-directory__eyebrow">Platform owner</p>
			<h1>Organizations</h1>
			<p class="organization-directory__description">
				Review every contractor organization on the platform.
			</p>
		</div>
	</header>

	<section class="organization-directory__summary" aria-label="Organization summary">
		<KpiCard
			label="Organizations"
			value={String(totals.all)}
			note="All organizations"
			icon={buildingIcon}
			variant="compact"
		/>
		<KpiCard
			label="Active"
			value={String(totals.active)}
			note="Contractor access allowed"
			icon={checkIcon}
			tone="success"
			variant="compact"
		/>
		<KpiCard
			label="Suspended"
			value={String(totals.suspended)}
			note="Contractor access blocked"
			icon={pauseIcon}
			tone="critical"
			variant="compact"
		/>
		<KpiCard
			label="Renewals due"
			value={String(totals.attention.renewal_due + totals.attention.payment_overdue)}
			note="Due within seven days or in the grace week"
			icon={alertIcon}
			tone="warning"
			variant="compact"
		/>
	</section>

	<DirectoryFilters {filters} {totals} {attentionLabels} onChange={setFilters} />

	<div class="organization-directory__list-meta" aria-live="polite">
		<span><strong>{organizationList.length}</strong> of {totals.matching} organizations shown</span>
	</div>

	<section
		class={[
			'organization-directory__table-panel',
			organizations.isPlaceholderData && 'organization-directory__table-panel--refreshing'
		]}
		aria-labelledby="organization-list-title"
		aria-busy={organizations.isPlaceholderData}
	>
		<h2 id="organization-list-title" class="organization-directory__sr-only">
			Organization directory
		</h2>
		{#if organizations.isPending}
			<div class="organization-directory__state">
				<LoadingSkeleton variant="table" rows={5} label="Loading organizations" />
			</div>
		{:else if organizations.isError}
			<div class="organization-directory__state">
				<ErrorState
					title="Organizations could not be loaded"
					description={organizations.error.message}
					retry={() => organizations.refetch()}
				/>
			</div>
		{:else if organizationList.length === 0}
			<div class="organization-directory__state">
				<EmptyState
					title={totals.all === 0 ? 'No organizations yet' : 'No matching organizations'}
					description={totals.all === 0
						? 'Organizations will appear here once they are provisioned.'
						: 'Try another search term or loosen a filter.'}
				/>
			</div>
		{:else}
			<div class="organization-directory__table-wrap">
				<table>
					<thead>
						<tr>
							<th scope="col">Organization</th>
							<th scope="col">Package</th>
							<th scope="col">Lifecycle</th>
							<th scope="col">Attention</th>
							<th scope="col">Team members</th>
							<th scope="col">Created</th>
							<th scope="col"><span class="organization-directory__sr-only">Open details</span></th>
						</tr>
					</thead>
					<tbody>
						{#each organizationList as organization (organization.id)}
							<tr>
								<th scope="row">
									<strong>{organization.name}</strong>
									<small>{organization.slug}</small>
								</th>
								<td>
									{#if organization.package}
										<strong class="organization-directory__package-name"
											>{organization.package.name}</strong
										>
										<small
											>{organization.package.billing_interval === 'year'
												? 'Yearly'
												: 'Monthly'}{organization.package.edition_number
												? ` · Edition ${organization.package.edition_number}`
												: ''}</small
										>
									{:else}
										<span class="organization-directory__no-attention">No package</span>
									{/if}
								</td>
								<td
									><Badge status={lifecycleTone(organization.lifecycle_status)}
										>{lifecycleLabel(organization.lifecycle_status)}</Badge
									></td
								>
								<td>
									{#if organization.attention_reasons.length === 0}
										<span class="organization-directory__no-attention">&mdash;</span>
									{:else}
										<div class="organization-directory__attention-badges">
											{#each organization.attention_reasons as reason (reason)}
												<Badge status={attentionMeta[reason].tone} size="small"
													>{attentionMeta[reason].label}</Badge
												>
											{/each}
										</div>
									{/if}
								</td>
								<td>{organization.member_count}</td>
								<td>{formatDate(organization.created_at)}</td>
								<td>
									<a
										class="organization-directory__row-action"
										href={resolve(`/jafar/organizations/${organization.id}`)}
										aria-label={`Open ${organization.name}`}
									>
										<span aria-hidden="true">{@html arrowRightIcon}</span>
									</a>
								</td>
							</tr>
						{/each}
					</tbody>
				</table>
			</div>
		{/if}
		<footer class="organization-directory__table-footer">
			{#if organizations.hasNextPage}
				<Button
					type="button"
					variant="secondary"
					disabled={organizations.isFetchingNextPage}
					onclick={() => organizations.fetchNextPage()}
				>
					{organizations.isFetchingNextPage ? 'Loading more…' : 'Load more'}
				</Button>
			{:else}
				<span>Open an organization to review its details.</span>
			{/if}
		</footer>
	</section>
</main>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.organization-directory {
		min-width: 0;
		display: grid;
		gap: var(--space-large);
	}

	.organization-directory h1,
	.organization-directory h2,
	.organization-directory p {
		margin: 0;
	}

	.organization-directory h1 {
		color: var(--color-heading);
		font-family: var(--typography--fontFamily-display);
		font-size: var(--typography--fontSize-jumbo);
		font-weight: 900;
		line-height: var(--typography--lineHeight-minuscule);
	}

	.organization-directory__header,
	.organization-directory__list-meta,
	.organization-directory__table-footer {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-base);
	}

	.organization-directory__header {
		align-items: flex-start;
		padding-bottom: var(--space-large);
		border-bottom: var(--border-base) solid var(--color-border);
	}

	.organization-directory__eyebrow {
		margin-bottom: var(--space-small) !important;
		color: var(--color-interactive);
		font-size: var(--typography--fontSize-small);
		font-weight: 700;
		letter-spacing: var(--typography--letterSpacing-loose);
		text-transform: uppercase;
	}

	.organization-directory__description {
		max-width: 65ch;
		margin-top: var(--space-small) !important;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-large);
		line-height: var(--typography--lineHeight-large);
	}

	.organization-directory__summary {
		display: grid;
		grid-template-columns: repeat(4, minmax(0, 1fr));
		gap: var(--space-base);
	}

	.organization-directory__list-meta,
	.organization-directory__table-footer {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}

	.organization-directory__list-meta {
		padding: 0 var(--space-small);
	}

	.organization-directory__list-meta strong {
		color: var(--color-heading);
		font-size: var(--typography--fontSize-large);
	}

	.organization-directory__table-panel {
		overflow: hidden;
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface);
		box-shadow: var(--shadow-low);
		transition: opacity var(--timing-quick);
	}

	// While a changed filter is on its way, the rows already shown stay and soften instead of vanishing.
	.organization-directory__table-panel--refreshing {
		opacity: 0.6;
	}

	.organization-directory__table-wrap {
		overflow-x: auto;
	}

	.organization-directory table {
		width: 100%;
		min-width: 1040px;
		border-collapse: collapse;
		color: var(--color-text);
		font-size: var(--typography--fontSize-base);
	}

	.organization-directory th,
	.organization-directory td {
		padding: var(--space-base) var(--space-large);
		border-bottom: var(--border-base) solid var(--color-border);
		text-align: left;
		vertical-align: middle;
	}

	.organization-directory thead {
		background: var(--color-surface--background--subtle);
	}

	.organization-directory thead th {
		color: var(--color-text--secondary);
		font-weight: 700;
		white-space: nowrap;
	}

	.organization-directory tbody th {
		color: var(--color-heading);
		font-weight: 700;
	}

	.organization-directory tbody th strong,
	.organization-directory tbody th small {
		display: block;
	}

	.organization-directory tbody th small {
		margin-top: var(--space-smaller);
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		font-weight: 400;
	}

	.organization-directory tbody tr {
		transition: background-color var(--timing-quick);

		&:hover {
			background: var(--color-surface--hover);
		}

		&:last-child th,
		&:last-child td {
			border-bottom: 0;
		}
	}

	.organization-directory__attention-badges {
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-smaller);
		max-width: 260px;
	}

	.organization-directory__no-attention {
		color: var(--color-text--secondary);
	}

	.organization-directory__package-name {
		display: block;
		color: var(--color-heading);
		font-weight: 600;
	}

	.organization-directory tbody td small {
		display: block;
		margin-top: var(--space-smaller);
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}

	.organization-directory__row-action {
		display: grid;
		width: 32px;
		height: 32px;
		place-items: center;
		border-radius: var(--radius-base);
		color: var(--color-interactive);
		text-decoration: none;

		&:hover {
			color: var(--color-interactive--hover);
			background: var(--color-surface--hover);
		}

		&:focus-visible {
			outline: none;
			box-shadow: var(--shadow-focus);
		}

		span,
		span :global(svg) {
			display: block;
			width: 18px;
			height: 18px;
		}
	}

	.organization-directory__state {
		padding: var(--space-large);
	}

	.organization-directory__table-footer {
		padding: var(--space-base) var(--space-large);
		border-top: var(--border-base) solid var(--color-border);
	}

	.organization-directory__sr-only {
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

	@media (max-width: 900px) {
		.organization-directory__summary {
			grid-template-columns: repeat(2, minmax(0, 1fr));
		}
	}

	@media (max-width: 767px) {
		.organization-directory__header,
		.organization-directory__list-meta,
		.organization-directory__table-footer {
			align-items: stretch;
			flex-direction: column;
		}
	}

	@media (max-width: 639px) {
		.organization-directory h1 {
			font-size: 28px;
		}

		.organization-directory__summary {
			grid-template-columns: 1fr;
		}
	}
</style>
