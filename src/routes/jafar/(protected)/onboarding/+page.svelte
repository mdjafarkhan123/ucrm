<script lang="ts">
	import { goto } from '$app/navigation';
	import { resolve } from '$app/paths';
	import { createInfiniteQuery } from '@tanstack/svelte-query';
	import clockIcon from '@tabler/icons/outline/clock-pause.svg?raw';
	import headsetIcon from '@tabler/icons/outline/headset.svg?raw';
	import rocketIcon from '@tabler/icons/outline/rocket.svg?raw';
	import userIcon from '@tabler/icons/outline/user.svg?raw';
	import DataTable, { type DataTableColumn } from '$lib/components/data-display/DataTable.svelte';
	import EmptyState from '$lib/components/data-display/EmptyState.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import KpiCard from '$lib/components/data-display/KpiCard.svelte';
	import ListLoadMore from '$lib/components/data-display/ListLoadMore.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import PageHeader from '$lib/components/layout/PageHeader.svelte';
	import Badge from '$lib/components/ui/Badge.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import SearchInput from '$lib/components/ui/SearchInput.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import { jafarOnboardingListKey } from '$lib/jafar/query-keys';
	import {
		onboardingNextActionLabel,
		onboardingStage,
		onboardingWaitingOnLabel,
		type OnboardingClient,
		type OnboardingFilter,
		type OnboardingListPage
	} from '$lib/setup/onboarding-list';

	// Every paid client and how far they are through setup (client onboarding C1, plan §8). Onboarding
	// workspaces such as GuideCX and Rocketlane lead with the same three questions: how far along, whose move
	// it is, and how long it has been quiet.

	let searchInput = $state('');
	let debouncedSearch = $state('');
	let waitingFilter = $state<'' | OnboardingFilter>('');

	$effect(() => {
		const value = searchInput;
		const timeout = setTimeout(() => {
			debouncedSearch = value;
		}, 300);
		return () => clearTimeout(timeout);
	});

	const clients = createInfiniteQuery<OnboardingListPage>(() => ({
		queryKey: jafarOnboardingListKey(debouncedSearch.trim(), waitingFilter),
		queryFn: async ({ pageParam }) => {
			// Built once per request and thrown away, so it needs no reactivity.
			// eslint-disable-next-line svelte/prefer-svelte-reactivity
			const params = new URLSearchParams();
			if (debouncedSearch.trim()) params.set('search', debouncedSearch.trim());
			if (waitingFilter) params.set('waiting_on', waitingFilter);
			if (typeof pageParam === 'string') params.set('cursor', pageParam);
			const response = await fetch(`/api/jafar/onboarding?${params.toString()}`);
			const result = await response.json();
			if (!response.ok) throw new Error(result.error ?? 'The client list could not be loaded.');
			return result as OnboardingListPage;
		},
		initialPageParam: null as string | null,
		getNextPageParam: (lastPage) => lastPage.next_cursor ?? undefined
	}));

	const pages = $derived(clients.data?.pages ?? []);
	const clientList = $derived(pages.flatMap((page) => page.clients));
	const totals = $derived(
		pages[0]?.totals ?? { all: 0, uplift: 0, client: 0, quiet: 0, matching: 0 }
	);
	const setupSize = $derived(pages[0]?.setup_size ?? { sections: 0, facts: 0 });
	const filtersApplied = $derived(Boolean(searchInput || waitingFilter));

	const filterOptions = $derived([
		{ value: '', label: 'All clients' },
		{ value: 'uplift', label: `Waiting on Uplift (${totals.uplift})` },
		{ value: 'client', label: `Waiting on the client (${totals.client})` },
		{ value: 'quiet', label: `Quiet for 3+ days (${totals.quiet})` }
	]);

	const columns: DataTableColumn[] = [
		{ key: 'client', label: 'Client' },
		{ key: 'stage', label: 'Stage' },
		{ key: 'setup', label: 'Setup' },
		{ key: 'next', label: 'Next step' },
		{ key: 'activity', label: 'Last activity' },
		{ key: 'support', label: 'Support' }
	];

	function clientHref(client: OnboardingClient) {
		return resolve(`/jafar/organizations/${client.id}`);
	}

	function percent(done: number, total: number) {
		return total > 0 ? Math.round((done / total) * 100) : 0;
	}

	const dayFormat = new Intl.DateTimeFormat(undefined, { dateStyle: 'medium' });
	const relative = new Intl.RelativeTimeFormat(undefined, { numeric: 'auto' });

	function ago(value: string) {
		const minutes = Math.round((Date.now() - new Date(value).getTime()) / 60_000);
		if (minutes < 60) return relative.format(-Math.max(minutes, 0), 'minute');
		const hours = Math.round(minutes / 60);
		if (hours < 24) return relative.format(-hours, 'hour');
		return relative.format(-Math.round(hours / 24), 'day');
	}

	function clearFilters() {
		searchInput = '';
		waitingFilter = '';
	}
</script>

<svelte:head><title>Onboarding · Control Room</title></svelte:head>

<!-- eslint-disable svelte/no-at-html-tags -->
<main class="onboarding-list">
	<PageHeader
		eyebrow="Platform owner"
		title="Onboarding"
		description="Every paid client on their way through setup: how far they are, and whose move it is next."
	/>

	<section class="onboarding-list__summary" aria-label="Onboarding summary">
		<KpiCard
			label="Paid clients"
			value={String(totals.all)}
			note="Accounts created after payment"
			icon={rocketIcon}
			variant="compact"
		/>
		<KpiCard
			label="Waiting on Uplift"
			value={String(totals.uplift)}
			note="Unread support or a help request"
			icon={headsetIcon}
			tone="critical"
			variant="compact"
		/>
		<KpiCard
			label="Waiting on the client"
			value={String(totals.client)}
			note="Their next setup step"
			icon={userIcon}
			tone="informative"
			variant="compact"
		/>
		<KpiCard
			label="Quiet for 3+ days"
			value={String(totals.quiet)}
			note="No setup activity lately"
			icon={clockIcon}
			tone="warning"
			variant="compact"
		/>
	</section>

	<section class="onboarding-list__filters" aria-label="Client filters">
		<div class="onboarding-list__field onboarding-list__field--search">
			<label for="onboarding-search">Search clients</label>
			<SearchInput
				id="onboarding-search"
				bind:value={searchInput}
				placeholder="Search by business name"
				ariaLabel="Search clients"
			/>
		</div>
		<div class="onboarding-list__field">
			<label for="onboarding-waiting">Show</label>
			<Select
				id="onboarding-waiting"
				bind:value={waitingFilter}
				options={filterOptions}
				ariaLabel="Filter clients by whose move it is"
			/>
		</div>
		<Button
			type="button"
			variant="secondary"
			variation="destructive"
			disabled={!filtersApplied}
			onclick={clearFilters}>Clear filters</Button
		>
	</section>

	{#if clients.isPending}
		<LoadingSkeleton variant="table" rows={5} label="Loading clients" />
	{:else if clients.isError}
		<ErrorState
			title="The client list could not be loaded"
			description={clients.error.message}
			retry={() => clients.refetch()}
		/>
	{:else if clientList.length === 0}
		<EmptyState
			title={totals.all === 0 ? 'No paid clients yet' : 'No matching clients'}
			description={totals.all === 0
				? 'A client appears here once you confirm their payment and their account is created.'
				: 'Try another search or filter.'}
		/>
	{:else}
		<p class="onboarding-list__meta" aria-live="polite">
			<strong>{clientList.length}</strong> of {totals.matching} clients shown
		</p>
		<DataTable
			{columns}
			items={clientList}
			rowId={(client) => client.id}
			caption="Paid clients in onboarding"
			onRowActivate={(client) => void goto(clientHref(client))}
		>
			{#snippet row(client: OnboardingClient)}
				{@const stage = onboardingStage(client)}
				{@const progress = percent(client.facts_answered, setupSize.facts)}
				<th scope="row">
					<div class="onboarding-list__cell">
						<a class="onboarding-list__name" href={clientHref(client)}>{client.name}</a>
						<span class="onboarding-list__sub">
							{client.package_name ?? 'No package'} · paid {dayFormat.format(
								new Date(client.account_created_at)
							)}
						</span>
					</div>
				</th>
				<td><Badge status={stage.tone} size="small">{stage.label}</Badge></td>
				<td>
					<div class="onboarding-list__cell onboarding-list__progress">
						<div
							class="onboarding-list__bar"
							role="progressbar"
							aria-label={`${client.name} setup answers`}
							aria-valuemin={0}
							aria-valuemax={100}
							aria-valuenow={progress}
						>
							<span style:width={`${progress}%`}></span>
						</div>
						<span class="onboarding-list__sub">
							{client.sections_done} of {setupSize.sections}
							{setupSize.sections === 1 ? 'task' : 'tasks'} done · {client.facts_answered} of {setupSize.facts}
							answers
						</span>
					</div>
				</td>
				<td>
					<div class="onboarding-list__cell">
						<span
							class="onboarding-list__owner"
							class:onboarding-list__owner--uplift={client.waiting_on === 'uplift'}
							class:onboarding-list__owner--client={client.waiting_on === 'client'}
							>{onboardingWaitingOnLabel[client.waiting_on]}</span
						>
						<span class="onboarding-list__action">{onboardingNextActionLabel(client)}</span>
					</div>
				</td>
				<td>
					<div class="onboarding-list__cell">
						<span class:onboarding-list__quiet={client.quiet}>{ago(client.last_activity_at)}</span>
						{#if client.quiet}<span class="onboarding-list__sub">Quiet — check in</span>{/if}
					</div>
				</td>
				<td>
					{#if client.unread_support > 0}
						<a class="onboarding-list__unread" href={resolve('/jafar/support')}>
							{client.unread_support} unread
						</a>
					{:else}
						<span class="onboarding-list__sub">—</span>
					{/if}
				</td>
			{/snippet}
			{#snippet footer()}
				<ListLoadMore
					hasNextPage={clients.hasNextPage}
					isFetchingNextPage={clients.isFetchingNextPage}
					onLoadMore={() => clients.fetchNextPage()}
					endLabel="That is every matching client."
				/>
			{/snippet}
		</DataTable>
	{/if}
</main>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.onboarding-list {
		min-width: 0;
		display: grid;
		gap: var(--space-large);
	}

	.onboarding-list__summary {
		display: grid;
		grid-template-columns: repeat(4, minmax(0, 1fr));
		gap: var(--space-base);
	}

	.onboarding-list__filters {
		display: flex;
		align-items: flex-end;
		gap: var(--space-base);
		padding: var(--space-base);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface);
		box-shadow: var(--shadow-low);

		:global(.button) {
			margin-left: auto;
		}
	}

	.onboarding-list__field {
		display: grid;
		width: min(280px, 100%);
		gap: var(--space-small);

		label {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			font-weight: 700;
		}
	}

	.onboarding-list__field--search {
		width: min(420px, 100%);
		flex: 1 1 320px;
	}

	.onboarding-list__meta {
		margin: 0;
		padding: 0 var(--space-small);
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);

		strong {
			color: var(--color-heading);
			font-size: var(--typography--fontSize-large);
		}
	}

	.onboarding-list__cell {
		display: grid;
		gap: var(--space-smallest);
		min-width: 0;
	}

	.onboarding-list__name {
		color: var(--color-heading);
		font-weight: 700;
		text-decoration: none;

		&:hover {
			color: var(--color-interactive);
			text-decoration: underline;
		}

		&:focus-visible {
			outline: none;
			border-radius: var(--radius-small);
			box-shadow: var(--shadow-focus);
		}
	}

	.onboarding-list__sub {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		font-weight: 400;
		white-space: nowrap;
	}

	.onboarding-list__progress {
		min-width: 200px;
	}

	.onboarding-list__bar {
		height: 6px;
		overflow: hidden;
		border-radius: var(--radius-circle);
		background: var(--color-surface--background--subtle);
		box-shadow: inset 0 0 0 var(--border-base) var(--color-border);

		span {
			display: block;
			height: 100%;
			border-radius: inherit;
			background: var(--color-interactive);
			transition: width var(--timing-base);
		}
	}

	.onboarding-list__owner {
		justify-self: start;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-smaller);
		font-weight: 700;
		letter-spacing: var(--typography--letterSpacing-loose);
		text-transform: uppercase;

		&--uplift {
			color: var(--color-critical);
		}

		&--client {
			color: var(--color-informative);
		}
	}

	.onboarding-list__action {
		color: var(--color-heading);
		white-space: nowrap;
	}

	.onboarding-list__quiet {
		color: var(--color-warning--onSurface);
		font-weight: 700;
	}

	.onboarding-list__unread {
		color: var(--color-critical);
		font-weight: 700;
		white-space: nowrap;
		text-decoration: none;

		&:hover {
			text-decoration: underline;
		}

		&:focus-visible {
			outline: none;
			border-radius: var(--radius-small);
			box-shadow: var(--shadow-focus);
		}
	}

	@media (max-width: 900px) {
		.onboarding-list__summary {
			grid-template-columns: repeat(2, minmax(0, 1fr));
		}
	}

	@media (max-width: 767px) {
		.onboarding-list__filters {
			align-items: stretch;
			flex-direction: column;

			:global(.button) {
				margin-left: 0;
			}
		}

		.onboarding-list__field,
		.onboarding-list__field--search {
			width: 100%;
			flex: none;
		}
	}
</style>
