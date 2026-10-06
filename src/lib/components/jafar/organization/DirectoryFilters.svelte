<script lang="ts">
	import { untrack } from 'svelte';
	import { CalendarDate } from '@internationalized/date';
	import CalendarPicker from '$lib/components/ui/CalendarPicker.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import FilterChip from '$lib/components/ui/FilterChip.svelte';
	import FilterChipMulti from '$lib/components/ui/FilterChipMulti.svelte';
	import SearchInput from '$lib/components/ui/SearchInput.svelte';
	import {
		activeDirectoryFilterCount,
		DIRECTORY_BILLING,
		DIRECTORY_JOINED,
		DIRECTORY_LABELS,
		DIRECTORY_LIFECYCLES,
		DIRECTORY_RENEWS,
		DIRECTORY_TEAM_SIZES,
		EMPTY_DIRECTORY_FILTERS,
		NO_PACKAGE,
		type DirectoryAttentionReason,
		type DirectoryFilters,
		type DirectoryJoined,
		type DirectoryTotals
	} from '$lib/jafar/organization-directory-filters';

	// The search box and every filter chip above the Organizations table. It owns none of the filter state:
	// it reports a change and the page puts it in the URL, which is what makes refresh, Back and a shared link
	// all keep the filters. The one thing it does hold is what is being typed in the search box.
	let {
		filters,
		totals,
		attentionLabels,
		onChange
	}: {
		filters: DirectoryFilters;
		totals: DirectoryTotals;
		/** Display names for the attention reasons, in the order the list should show them. */
		attentionLabels: Record<DirectoryAttentionReason, string>;
		// `replace` asks the page not to add a history entry: typing a search is one visit to the list, not one
		// per pause between letters.
		onChange: (next: DirectoryFilters, options?: { replace?: boolean }) => void;
	} = $props();

	// `sent` is the term this bar last asked for, so a term arriving from the URL that this bar did not send
	// (Back, or a shared link) can be told apart: the box follows it. One this bar did send must never be
	// written back over what has been typed since.
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
		// Long enough that a name typed at ordinary speed is one request, short enough to feel live.
		const handle = setTimeout(() => {
			sent = next;
			onChange({ ...filters, q: next }, { replace: true });
		}, 300);
		return () => clearTimeout(handle);
	});

	const activeCount = $derived(activeDirectoryFilterCount(filters));

	const attentionOptions = $derived(
		(Object.keys(attentionLabels) as DirectoryAttentionReason[]).map((reason) => ({
			value: reason,
			label: attentionLabels[reason],
			count: totals.attention[reason]
		}))
	);
	const lifecycleOptions = $derived(
		DIRECTORY_LIFECYCLES.map((status) => ({
			value: status,
			label: DIRECTORY_LABELS.lifecycle[status],
			count: totals[status]
		}))
	);
	const packageOptions = $derived([
		...totals.packages.map((entry) => ({
			value: entry.package_id,
			label: entry.name,
			count: entry.count
		})),
		{ value: NO_PACKAGE, label: 'No package', count: totals.no_package }
	]);

	const billingOptions = [
		{ value: '', label: 'All' },
		...DIRECTORY_BILLING.map((value) => ({ value, label: DIRECTORY_LABELS.billing[value] }))
	];
	const renewsOptions = [
		{ value: '', label: 'Any time' },
		...DIRECTORY_RENEWS.map((value) => ({ value, label: DIRECTORY_LABELS.renews[value] }))
	];
	const joinedOptions = [
		{ value: '', label: 'Any time' },
		...DIRECTORY_JOINED.map((value) => ({ value, label: DIRECTORY_LABELS.joined[value] }))
	];
	const teamOptions = [
		{ value: '', label: 'Any size' },
		...DIRECTORY_TEAM_SIZES.map((value) => ({ value, label: DIRECTORY_LABELS.team[value] }))
	];

	function update(change: Partial<DirectoryFilters>) {
		onChange({ ...filters, ...change });
	}

	// Leaving a custom range takes its two ends with it, so a preset never carries a stale date into the URL.
	function changeJoined(joined: string) {
		onChange({ ...filters, joined: joined as '' | DirectoryJoined, from: '', to: '' });
	}

	// The pickers speak CalendarDate; the URL speaks `2026-08-19`. Both ends are optional.
	function toCalendarDate(day: string) {
		if (!day) return undefined;
		const [year, month, date] = day.split('-').map(Number);
		return new CalendarDate(year, month, date);
	}
	function toDay(value: CalendarDate | undefined) {
		if (!value) return '';
		return `${value.year}-${String(value.month).padStart(2, '0')}-${String(value.day).padStart(2, '0')}`;
	}

	function clearAll() {
		search = '';
		sent = '';
		onChange(EMPTY_DIRECTORY_FILTERS);
	}
</script>

<section class="directory-filters" aria-label="Organization filters">
	<div class="directory-filters__row">
		<SearchInput
			id="organization-search"
			class="directory-filters__search"
			bind:value={search}
			placeholder="Search by name, slug, or administrator email"
			ariaLabel="Search organizations"
		/>
	</div>

	<div class="directory-filters__row directory-filters__row--chips">
		<FilterChipMulti
			id="organization-filter-attention"
			label="Needs attention"
			options={attentionOptions}
			values={filters.attention}
			onchange={(values) => update({ attention: values as DirectoryAttentionReason[] })}
		/>
		<FilterChipMulti
			id="organization-filter-lifecycle"
			label="Status"
			options={lifecycleOptions}
			values={filters.lifecycle}
			onchange={(values) => update({ lifecycle: values as DirectoryFilters['lifecycle'] })}
		/>
		<FilterChipMulti
			id="organization-filter-package"
			label="Package"
			options={packageOptions}
			values={filters.packages}
			onchange={(values) => update({ packages: values })}
		/>
		<FilterChip
			id="organization-filter-billing"
			label="Billing"
			value={filters.billing}
			options={billingOptions}
			restValue=""
			onchange={(value) => update({ billing: value as DirectoryFilters['billing'] })}
		/>
		<FilterChip
			id="organization-filter-renews"
			label="Renews"
			value={filters.renews}
			options={renewsOptions}
			restValue=""
			onchange={(value) => update({ renews: value as DirectoryFilters['renews'] })}
		/>
		<FilterChip
			id="organization-filter-joined"
			label="Joined"
			value={filters.joined}
			options={joinedOptions}
			restValue=""
			onchange={changeJoined}
		/>
		<FilterChip
			id="organization-filter-team"
			label="Team size"
			value={filters.team}
			options={teamOptions}
			restValue=""
			onchange={(value) => update({ team: value as DirectoryFilters['team'] })}
		/>

		{#if activeCount > 0 || search}
			<Button type="button" variant="tertiary" onclick={clearAll}>
				Clear all{activeCount > 0 ? ` (${activeCount})` : ''}
			</Button>
		{/if}
	</div>

	{#if filters.joined === 'custom'}
		<div class="directory-filters__row directory-filters__row--range">
			<CalendarPicker
				id="organization-joined-from"
				label="Joined from"
				value={toCalendarDate(filters.from)}
				maxValue={toCalendarDate(filters.to)}
				onchange={(value) => update({ from: toDay(value) })}
			/>
			<CalendarPicker
				id="organization-joined-to"
				label="Joined until"
				value={toCalendarDate(filters.to)}
				minValue={toCalendarDate(filters.from)}
				onchange={(value) => update({ to: toDay(value) })}
			/>
			{#if !filters.from && !filters.to}
				<p class="directory-filters__hint">Pick at least one end of the range.</p>
			{/if}
		</div>
	{/if}
</section>

<style lang="scss">
	.directory-filters {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);
		padding: var(--space-base);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface);
		box-shadow: var(--shadow-low);
	}

	.directory-filters__row {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: var(--space-small);
	}

	// The search takes the first line to itself; the chips sit under it, as a quiet second tier.
	.directory-filters__row :global(.directory-filters__search) {
		flex: 1 1 320px;
		width: auto;
		max-width: 520px;
		min-height: 44px;
	}

	.directory-filters__row--chips {
		padding-top: var(--space-base);
		border-top: var(--border-base) solid var(--color-border);
	}

	.directory-filters__row--range {
		align-items: end;
		gap: var(--space-base);

		// Two short dates get a date-sized box each and sit side by side.
		:global(.calendar-picker) {
			width: 200px;
		}
	}

	.directory-filters__hint {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}

	@media (max-width: 767px) {
		.directory-filters__row--range :global(.calendar-picker) {
			width: 100%;
		}
	}
</style>
