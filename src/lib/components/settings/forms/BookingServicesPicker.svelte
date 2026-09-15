<script lang="ts">
	import { createQuery } from '@tanstack/svelte-query';
	import { SvelteMap } from 'svelte/reactivity';
	import Card from '$lib/components/ui/Card.svelte';
	import SearchInput from '$lib/components/ui/SearchInput.svelte';
	import { catalogItemsKey, fetchCatalogItems } from '$lib/quotes/api';
	import { BOOKING_MAX_SERVICES, type BookableService } from '$lib/forms/types';
	import plusIcon from '@tabler/icons/outline/plus.svg?raw';
	import xIcon from '@tabler/icons/outline/x.svg?raw';
	import chevronUpIcon from '@tabler/icons/outline/chevron-up.svg?raw';
	import chevronDownIcon from '@tabler/icons/outline/chevron-down.svg?raw';

	// Which of the business's own Price Book services (category = 'service') a customer can pick when
	// booking, and their display order — reuses the same catalog the picker on quotes already searches,
	// rather than a second list (20260913160000 § 2).
	let {
		selectedIds = $bindable(),
		initialServices,
		disabled = false
	}: {
		selectedIds: string[];
		initialServices: BookableService[];
		disabled?: boolean;
	} = $props();

	// Name lookup for every id currently selected, seeded once from what the server sent (this component
	// remounts under the owning page's `{#key}` whenever fresh data is reseeded) and topped up whenever a
	// search result is added.
	function createKnownServices() {
		return new SvelteMap(initialServices.map((service) => [service.catalog_item_id, service]));
	}
	const known = createKnownServices();

	let search = $state('');
	let debounced = $state('');
	$effect(() => {
		const term = search.trim();
		const handle = setTimeout(() => (debounced = term), 300);
		return () => clearTimeout(handle);
	});

	const resultsQuery = createQuery(() => ({
		queryKey: catalogItemsKey({ category: 'service', search: debounced }),
		queryFn: () => fetchCatalogItems({ category: 'service', search: debounced }),
		staleTime: 15_000,
		retry: false
	}));

	const results = $derived(
		(resultsQuery.data?.items ?? []).filter((item) => !selectedIds.includes(item.id))
	);
	const atCap = $derived(selectedIds.length >= BOOKING_MAX_SERVICES);
	const selected = $derived(
		selectedIds.map(
			(id) =>
				known.get(id) ?? {
					catalog_item_id: id,
					name: 'Unknown service',
					unit_price_minor: 0,
					archived_at: null
				}
		)
	);

	function add(id: string, name: string) {
		if (disabled || atCap || selectedIds.includes(id)) return;
		known.set(id, { catalog_item_id: id, name, unit_price_minor: 0, archived_at: null });
		selectedIds = [...selectedIds, id];
	}

	function remove(id: string) {
		if (disabled) return;
		selectedIds = selectedIds.filter((x) => x !== id);
	}

	function move(index: number, by: number) {
		if (disabled) return;
		const target = index + by;
		if (target < 0 || target >= selectedIds.length) return;
		const next = [...selectedIds];
		[next[index], next[target]] = [next[target], next[index]];
		selectedIds = next;
	}
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<Card heading="Bookable services">
	<p class="booking-services__hint">
		Which Price Book services customers can pick when booking. Up to {BOOKING_MAX_SERVICES}.
	</p>
	{#if selected.length > 0}
		<ol class="booking-services__list">
			{#each selected as service, index (service.catalog_item_id)}
				<li class="booking-services__row">
					<span class="booking-services__name">{service.name}</span>
					<span class="booking-services__actions">
						<button
							type="button"
							class="booking-services__icon-btn"
							disabled={disabled || index === 0}
							onclick={() => move(index, -1)}
							aria-label={`Move ${service.name} up`}>{@html chevronUpIcon}</button
						>
						<button
							type="button"
							class="booking-services__icon-btn"
							disabled={disabled || index === selected.length - 1}
							onclick={() => move(index, 1)}
							aria-label={`Move ${service.name} down`}>{@html chevronDownIcon}</button
						>
						<button
							type="button"
							class="booking-services__icon-btn"
							{disabled}
							onclick={() => remove(service.catalog_item_id)}
							aria-label={`Remove ${service.name}`}>{@html xIcon}</button
						>
					</span>
				</li>
			{/each}
		</ol>
	{:else}
		<p class="booking-services__hint">
			No services chosen yet. Search below and add the ones customers should be able to book.
		</p>
	{/if}

	{#if !disabled}
		{#if atCap}
			<p class="booking-services__hint">
				You've reached the {BOOKING_MAX_SERVICES}-service limit. Remove one to add another.
			</p>
		{:else}
			<SearchInput
				id="booking-services-search"
				bind:value={search}
				placeholder="Search your services"
			/>
			{#if debounced}
				{#if resultsQuery.isPending}
					<p class="booking-services__hint">Searching…</p>
				{:else if resultsQuery.isError}
					<p class="booking-services__hint">Your price list could not be searched right now.</p>
				{:else if results.length === 0}
					<p class="booking-services__hint">No matching service.</p>
				{:else}
					<ul class="booking-services__results">
						{#each results as item (item.id)}
							<li>
								<button
									type="button"
									class="booking-services__add"
									onclick={() => add(item.id, item.name)}
								>
									<span aria-hidden="true">{@html plusIcon}</span>
									{item.name}
								</button>
							</li>
						{/each}
					</ul>
				{/if}
			{/if}
		{/if}
	{/if}
</Card>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.booking-services {
		&__list {
			display: flex;
			flex-direction: column;
			gap: var(--space-smaller);
			margin: 0 0 var(--space-small);
			padding: 0;
			list-style: none;
		}
		&__row {
			display: flex;
			align-items: center;
			justify-content: space-between;
			gap: var(--space-small);
			padding: var(--space-small);
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-base);
			background: var(--color-surface);
		}
		&__name {
			overflow: hidden;
			color: var(--color-heading);
			font-weight: 500;
			text-overflow: ellipsis;
			white-space: nowrap;
		}
		&__actions {
			display: flex;
			flex-shrink: 0;
			gap: var(--space-smallest);
		}
		&__icon-btn {
			display: grid;
			width: 28px;
			height: 28px;
			place-items: center;
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-small);
			color: var(--color-text--secondary);
			background: var(--color-surface);
			cursor: pointer;

			:global(svg) {
				width: 16px;
				height: 16px;
			}
			&:hover:not(:disabled) {
				color: var(--color-heading);
				background: var(--color-surface--hover);
			}
			&:disabled {
				opacity: 0.4;
				cursor: not-allowed;
			}
		}
		&__hint {
			margin: 0 0 var(--space-small);
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}
		&__results {
			display: flex;
			flex-direction: column;
			gap: 2px;
			margin: var(--space-small) 0 0;
			padding: 0;
			list-style: none;
		}
		&__add {
			display: flex;
			width: 100%;
			align-items: center;
			gap: var(--space-small);
			padding: var(--space-small);
			border: 0;
			border-radius: var(--radius-small);
			color: var(--color-interactive);
			background: transparent;
			font: inherit;
			text-align: left;
			cursor: pointer;

			:global(svg) {
				width: 16px;
				height: 16px;
			}
			&:hover {
				background: var(--color-surface--hover);
			}
		}
	}
</style>
