<script lang="ts">
	import { untrack } from 'svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import FilterChip from '$lib/components/ui/FilterChip.svelte';
	import FilterChipMulti from '$lib/components/ui/FilterChipMulti.svelte';
	import SearchInput from '$lib/components/ui/SearchInput.svelte';
	import {
		EMPTY_LEAD_FILTERS,
		LEAD_SORTS,
		LEAD_SORT_LABELS,
		LEAD_SOURCES,
		LEAD_SOURCE_LABELS,
		LEAD_STATUSES,
		LEAD_STATUS_LABELS,
		countryName,
		hasLeadFilters,
		type LeadFilters,
		type LeadListTotals,
		type LeadSort,
		type LeadSource,
		type LeadStatus
	} from '$lib/jafar/leads';

	// The search box and filter chips above the Leads list, the same bar as the Organizations directory's. It
	// owns none of the filter state: it reports a change and the page puts it in the URL. The one thing it holds
	// is what is being typed in the search box.
	let {
		filters,
		totals,
		onChange
	}: {
		filters: LeadFilters;
		totals: LeadListTotals;
		// `replace`: typing a search is one visit to the list, not one history entry per pause between letters.
		onChange: (next: LeadFilters, options?: { replace?: boolean }) => void;
	} = $props();

	// `sent` is the term this bar last asked for, so a term arriving from the URL that this bar did not send
	// (Back, or a shared link) can be told apart: the box follows it.
	let search = $state(untrack(() => filters.q));
	let sent = untrack(() => filters.q);

	$effect(() => {
		const incoming = filters.q;
		if (incoming !== sent) {
			sent = incoming;
			search = incoming;
		}
	});

	$effect(() => {
		const next = search.trim();
		if (next === sent) return;
		const handle = setTimeout(() => {
			sent = next;
			onChange({ ...filters, q: next }, { replace: true });
		}, 300);
		return () => clearTimeout(handle);
	});

	const statusOptions = $derived(
		LEAD_STATUSES.map((status) => ({
			value: status,
			label: LEAD_STATUS_LABELS[status],
			count: totals.statuses[status] ?? 0
		}))
	);
	// Only countries that have Leads, most first; a country chosen from a shared link stays listed.
	const countryOptions = $derived([
		...totals.countries.map((entry) => ({
			value: entry.code,
			label: countryName(entry.code),
			count: entry.count
		})),
		...filters.countries
			.filter((code) => !totals.countries.some((entry) => entry.code === code))
			.map((code) => ({ value: code, label: countryName(code), count: 0 }))
	]);
	const sourceOptions = $derived(
		LEAD_SOURCES.map((source) => ({
			value: source,
			label: LEAD_SOURCE_LABELS[source],
			count: totals.sources[source] ?? 0
		}))
	);
	const sortOptions = LEAD_SORTS.map((value) => ({ value, label: LEAD_SORT_LABELS[value] }));
	// B4: a business with a Deal moves to the Deals board and leaves this list; it is one choice away here.
	const showOptions = $derived([
		{ value: 'leads', label: 'Leads' },
		{ value: 'in_deal', label: `In a Deal (${totals.in_deal.toLocaleString()})` }
	]);

	const filtering = $derived(hasLeadFilters(filters));

	function clearAll() {
		search = '';
		sent = '';
		onChange({ ...EMPTY_LEAD_FILTERS, sort: filters.sort, inDeal: filters.inDeal });
	}
</script>

<section class="lead-filters" aria-label="Lead filters">
	<div class="lead-filters__row">
		<SearchInput
			id="lead-search"
			class="lead-filters__search"
			bind:value={search}
			placeholder="Search by business, website, contact, email, or phone"
			ariaLabel="Search Leads"
		/>
	</div>

	<div class="lead-filters__row lead-filters__row--chips">
		<FilterChipMulti
			id="lead-filter-status"
			label="Status"
			options={statusOptions}
			values={filters.statuses}
			onchange={(values) => onChange({ ...filters, statuses: values as LeadStatus[] })}
		/>
		<FilterChipMulti
			id="lead-filter-country"
			label="Country"
			options={countryOptions}
			values={filters.countries}
			onchange={(values) => onChange({ ...filters, countries: values })}
		/>
		<FilterChipMulti
			id="lead-filter-source"
			label="Source"
			options={sourceOptions}
			values={filters.sources}
			onchange={(values) => onChange({ ...filters, sources: values as LeadSource[] })}
		/>
		<FilterChip
			id="lead-sort"
			label="Sort"
			value={filters.sort}
			options={sortOptions}
			onchange={(value) => onChange({ ...filters, sort: value as LeadSort })}
		/>
		<FilterChip
			id="lead-show"
			label="Show"
			value={filters.inDeal ? 'in_deal' : 'leads'}
			options={showOptions}
			onchange={(value) => onChange({ ...filters, inDeal: value === 'in_deal' })}
		/>

		{#if filtering || search}
			<Button type="button" variant="tertiary" onclick={clearAll}>Clear all</Button>
		{/if}
	</div>
</section>

<style lang="scss">
	.lead-filters {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);
		padding: var(--space-base);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface);
		box-shadow: var(--shadow-low);
	}

	.lead-filters__row {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: var(--space-small);
	}

	.lead-filters__row :global(.lead-filters__search) {
		flex: 1 1 320px;
		width: auto;
		max-width: 520px;
		min-height: 44px;
	}

	.lead-filters__row--chips {
		padding-top: var(--space-base);
		border-top: var(--border-base) solid var(--color-border);
	}
</style>
