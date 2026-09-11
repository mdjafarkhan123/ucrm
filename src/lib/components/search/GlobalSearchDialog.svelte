<script lang="ts">
	import { createQuery } from '@tanstack/svelte-query';
	import { resolve } from '$app/paths';
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import SearchInput from '$lib/components/ui/SearchInput.svelte';
	import EmptyState from '$lib/components/data-display/EmptyState.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import {
		fetchGlobalSearch,
		globalSearchKey,
		type GlobalSearchGroup,
		type GlobalSearchResult,
		type GlobalSearchResultType
	} from '$lib/search/api';
	import searchIcon from '@tabler/icons/outline/search.svg?raw';
	import userIcon from '@tabler/icons/outline/user.svg?raw';
	import routeIcon from '@tabler/icons/outline/route.svg?raw';
	import quoteIcon from '@tabler/icons/outline/file-invoice.svg?raw';
	import jobIcon from '@tabler/icons/outline/tools.svg?raw';
	import invoiceIcon from '@tabler/icons/outline/receipt.svg?raw';
	import conversationIcon from '@tabler/icons/outline/messages.svg?raw';
	import arrowIcon from '@tabler/icons/outline/arrow-up-right.svg?raw';

	let { open, userId, onClose }: { open: boolean; userId: string; onClose: () => void } = $props();

	let query = $state('');
	let debouncedQuery = $state('');
	let resultsElement: HTMLDivElement;

	$effect(() => {
		const value = query.trim();
		const handle = setTimeout(() => (debouncedQuery = value), 300);
		return () => clearTimeout(handle);
	});

	const searchQuery = createQuery(() => ({
		queryKey: globalSearchKey(userId, debouncedQuery),
		queryFn: () => fetchGlobalSearch(debouncedQuery),
		enabled: open && debouncedQuery.length >= 2
	}));

	const groupOrder: { key: GlobalSearchGroup; label: string }[] = [
		{ key: 'clients', label: 'Clients' },
		{ key: 'requests', label: 'Requests' },
		{ key: 'quotes', label: 'Quotes' },
		{ key: 'jobs', label: 'Jobs' },
		{ key: 'invoices', label: 'Invoices' },
		{ key: 'conversations', label: 'Conversations' }
	];
	const visibleGroups = $derived(
		groupOrder
			.map((group) => ({ ...group, results: searchQuery.data?.groups[group.key] ?? [] }))
			.filter((group) => group.results.length > 0)
	);
	const resultCount = $derived(
		visibleGroups.reduce((total, group) => total + group.results.length, 0)
	);

	const resultIcons: Record<GlobalSearchResultType, string> = {
		client: userIcon,
		request: routeIcon,
		quote: quoteIcon,
		job: jobIcon,
		invoice: invoiceIcon,
		conversation: conversationIcon
	};

	function resultLinks() {
		return [
			...(resultsElement?.querySelectorAll<HTMLAnchorElement>('.global-search__result') ?? [])
		];
	}

	function focusFirstResult(event: KeyboardEvent) {
		if (event.key !== 'ArrowDown') return;
		const first = resultLinks()[0];
		if (!first) return;
		event.preventDefault();
		first.focus();
	}

	function moveResultFocus(event: KeyboardEvent) {
		const links = resultLinks();
		const current = event.currentTarget as HTMLAnchorElement;
		const index = links.indexOf(current);
		if (index < 0) return;

		let nextIndex: number | null = null;
		if (event.key === 'ArrowDown') nextIndex = (index + 1) % links.length;
		if (event.key === 'ArrowUp') nextIndex = (index - 1 + links.length) % links.length;
		if (event.key === 'Home') nextIndex = 0;
		if (event.key === 'End') nextIndex = links.length - 1;
		if (nextIndex === null) return;

		event.preventDefault();
		links[nextIndex]?.focus();
	}

	function selectResult(_result: GlobalSearchResult) {
		onClose();
	}

	function resultHref(result: GlobalSearchResult) {
		switch (result.type) {
			case 'client':
				return resolve('/(app)/clients/[id=uuid]', { id: result.id });
			case 'request':
				return resolve('/(app)/requests/[id=uuid]', { id: result.id });
			case 'quote':
				return resolve('/(app)/quotes/[id=uuid]', { id: result.id });
			case 'job':
				return resolve('/(app)/jobs/[id=uuid]', { id: result.id });
			case 'invoice':
				return resolve('/(app)/invoices/[id=uuid]', { id: result.id });
			case 'conversation': {
				const params = new URLSearchParams({
					search: debouncedQuery,
					conversation: result.id
				});
				return `${resolve('/(app)/communications')}?${params.toString()}`;
			}
		}
	}
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<Dialog {open} title="Search" size="large" initialFocusId="global-search-dialog-input" {onClose}>
	<div class="global-search">
		<SearchInput
			id="global-search-dialog-input"
			placeholder="Search clients, work, or conversations"
			ariaLabel="Search clients, work, or conversations"
			bind:value={query}
			onkeydown={focusFirstResult}
		/>

		<div class="global-search__results" bind:this={resultsElement} aria-live="polite">
			{#if query.trim().length < 2}
				<div class="global-search__prompt">
					<span aria-hidden="true">{@html searchIcon}</span>
					<p>Enter at least 2 characters to search your records.</p>
				</div>
			{:else if debouncedQuery !== query.trim() || searchQuery.isPending}
				<div class="global-search__loading" aria-label="Searching" aria-busy="true">
					<LoadingSkeleton variant="card" label="Searching" />
					<LoadingSkeleton variant="card" label="Searching" />
					<LoadingSkeleton variant="card" label="Searching" />
				</div>
			{:else if searchQuery.isError}
				<ErrorState
					title="Search is unavailable"
					description="We could not search right now. Try again."
					retry={() => void searchQuery.refetch()}
				/>
			{:else if resultCount === 0}
				<EmptyState
					title="No matches found"
					description={`No records match “${debouncedQuery}”. Try a name, number, email, or title.`}
					icon={searchIcon}
				/>
			{:else}
				<p class="global-search__summary">
					{resultCount}
					{resultCount === 1 ? 'result' : 'results'}
				</p>
				{#each visibleGroups as group (group.key)}
					<section class="global-search__group" aria-labelledby={`global-search-${group.key}`}>
						<h3 id={`global-search-${group.key}`}>{group.label}</h3>
						<ul>
							{#each group.results as result (`${result.type}-${result.id}`)}
								<li>
									<a
										class="global-search__result"
										href={resultHref(result)}
										onkeydown={moveResultFocus}
										onclick={() => selectResult(result)}
									>
										<span class="global-search__result-icon" aria-hidden="true"
											>{@html resultIcons[result.type]}</span
										>
										<span class="global-search__result-copy">
											<strong>{result.title}</strong>
											{#if result.subtitle}<small>{result.subtitle}</small>{/if}
										</span>
										<span class="global-search__result-arrow" aria-hidden="true"
											>{@html arrowIcon}</span
										>
									</a>
								</li>
							{/each}
						</ul>
					</section>
				{/each}
			{/if}
		</div>
	</div>
</Dialog>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.global-search {
		display: grid;
		gap: var(--space-base);
	}
	.global-search__results {
		min-height: 240px;
		max-height: min(56dvh, 560px);
		overflow-y: auto;
	}
	.global-search__prompt {
		display: grid;
		min-height: 240px;
		place-items: center;
		align-content: center;
		gap: var(--space-base);
		color: var(--color-text--secondary);
		text-align: center;
	}
	.global-search__prompt span,
	.global-search__prompt span :global(svg) {
		display: block;
		width: 32px;
		height: 32px;
	}
	.global-search__loading {
		display: grid;
		gap: var(--space-small);
	}
	.global-search__summary {
		padding: 0 var(--space-small) var(--space-small);
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}
	.global-search__group + .global-search__group {
		margin-top: var(--space-large);
	}
	.global-search__group h3 {
		padding: var(--space-small) var(--space-small);
		border-bottom: var(--border-base) solid var(--color-border--section);
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		font-weight: 700;
		text-transform: uppercase;
		letter-spacing: 0.04em;
	}
	.global-search__group ul {
		padding: 0;
		margin: 0;
		list-style: none;
	}
	.global-search__group li:not(:last-child) {
		border-bottom: var(--border-base) solid var(--color-border);
	}
	.global-search__result {
		display: flex;
		align-items: center;
		gap: var(--space-small);
		min-height: 56px;
		padding: var(--space-small) var(--space-base);
		border-radius: var(--radius-base);
		color: var(--color-heading);
		text-decoration: none;
		transition: background var(--timing-quick);
	}
	.global-search__result:hover,
	.global-search__result:focus-visible {
		background: var(--color-surface--hover);
	}
	.global-search__result:focus-visible {
		outline: none;
		box-shadow: var(--shadow-focus);
	}
	.global-search__result-icon {
		display: grid;
		flex: 0 0 auto;
		width: 36px;
		height: 36px;
		place-items: center;
		border-radius: var(--radius-base);
		color: var(--color-interactive--subtle);
		background: var(--color-surface--active);
	}
	.global-search__result-icon :global(svg) {
		width: 18px;
		height: 18px;
	}
	.global-search__result-copy {
		display: grid;
		flex: 1 1 auto;
		min-width: 0;
		gap: var(--space-smallest);
	}
	.global-search__result-copy strong,
	.global-search__result-copy small {
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}
	.global-search__result-copy strong {
		font-size: var(--typography--fontSize-base);
		font-weight: 600;
	}
	.global-search__result-copy small {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}
	.global-search__result-arrow {
		display: grid;
		flex: 0 0 auto;
		width: 24px;
		height: 24px;
		place-items: center;
		color: var(--color-icon--secondary);
	}
	.global-search__result-arrow :global(svg) {
		width: 16px;
		height: 16px;
	}
	@media (max-width: 639px) {
		.global-search__results {
			max-height: 62dvh;
		}
	}
</style>
