<script lang="ts">
	import { untrack, type Snippet } from 'svelte';
	import { createQuery } from '@tanstack/svelte-query';
	import { CalendarDate } from '@internationalized/date';
	import Select from '$lib/components/ui/Select.svelte';
	import CalendarPicker from '$lib/components/ui/CalendarPicker.svelte';
	import SearchInput from '$lib/components/ui/SearchInput.svelte';
	import SavedFiltersMenu from './SavedFiltersMenu.svelte';
	import { LEAD_SOURCES } from '$lib/clients/lead-sources';
	import { assignableTeamKey, fetchAssignableTeam } from '$lib/team/api';
	import { fetchLeadSources, leadSourcesKey } from '$lib/pipeline/api';
	import {
		BOARD_DATE_LABELS,
		BOARD_DATE_PRESETS,
		BOARD_SORTS,
		BOARD_SORT_LABELS,
		directionLabel,
		searchTerm,
		sortHasDirection,
		type BoardDatePreset,
		type BoardFilters,
		type BoardSort
	} from '$lib/pipeline/filters';
	import arrowUpIcon from '@tabler/icons/outline/arrow-up.svg?raw';
	import arrowDownIcon from '@tabler/icons/outline/arrow-down.svg?raw';

	// The row of controls above the board: which cards to find, what order they are in, whose they are, where
	// they came from, when they came in, and how many there are altogether. It owns none of that state — it reports a change and the page
	// puts it in the URL, which is what makes refresh and the back button work.
	let {
		filters,
		resultCount,
		canViewValue,
		onChange,
		leading
	}: {
		filters: BoardFilters;
		/** Null until the summary has answered. */
		resultCount: number | null;
		// Sorting by value is reading value, so the whole option is absent for a member without money —
		// not disabled, which would still tell them the board has amounts on it.
		canViewValue: boolean;
		// `replace` asks the page not to add a history entry: typing a search is one visit to the board,
		// not one per pause between letters.
		onChange: (next: BoardFilters, options?: { replace?: boolean }) => void;
		// The Board / Table switch, first in the row. It belongs to the page, not to these controls.
		leading?: Snippet;
	} = $props();

	// The search box holds what is being typed; the URL holds what the board is searching for. `sent` is the
	// term this bar last asked for, so the two can be told apart: a term arriving from the URL that this bar
	// did not send is the Back button or a shared link, and the box follows it. One this bar did send must
	// never be written back over what the person has typed since.
	let search = $state(untrack(() => filters.q ?? ''));
	let sent = untrack(() => filters.q ?? '');

	$effect(() => {
		const incoming = filters.q ?? '';
		if (incoming !== sent) {
			sent = incoming;
			search = incoming;
		}
	});

	$effect(() => {
		const next = searchTerm(search) ?? '';
		if (next === sent) return;
		// Long enough that a name typed at ordinary speed is one request, short enough to feel live.
		const handle = setTimeout(() => {
			sent = next;
			onChange({ ...filters, q: next || undefined }, { replace: true });
		}, 300);
		return () => clearTimeout(handle);
	});

	// The team only matters once someone opens the Salesperson list, but it is a small, long-lived list and
	// the board almost always has an owner filter used against it, so it loads with the bar rather than
	// making the first open wait.
	const teamQuery = createQuery(() => ({
		queryKey: assignableTeamKey,
		queryFn: fetchAssignableTeam,
		staleTime: 300_000
	}));

	const sortOptions = $derived(
		BOARD_SORTS.filter((sort) => sort !== 'value' || canViewValue).map((sort) => ({
			value: sort,
			label: BOARD_SORT_LABELS[sort]
		}))
	);

	const ownerOptions = $derived([
		{ value: 'all', label: 'All' },
		{ value: 'unassigned', label: 'Unassigned' },
		...(teamQuery.data ?? []).map((member) => ({
			value: member.id,
			label: member.full_name ?? 'Unnamed teammate'
		}))
	]);

	// Clients carry their lead source as free text, so the list is the client form's own sources plus any
	// other spelling the open cards really carry ("Google", "staff"). The board matches a source whatever its
	// capitals, so each appears once. Like any list that has to be opened, it loads when the pill is pointed
	// at or focused, not with the page.
	let wantSources = $state(false);
	const sourcesQuery = createQuery(() => ({
		queryKey: leadSourcesKey,
		queryFn: fetchLeadSources,
		enabled: wantSources,
		staleTime: 60_000
	}));

	const sourceNames = $derived.by(() => {
		const names = [...LEAD_SOURCES];
		const extra = [...(sourcesQuery.data ?? []), ...(filters.source ? [filters.source] : [])];
		for (const name of extra) {
			if (!names.some((known) => known.toLowerCase() === name.toLowerCase())) names.push(name);
		}
		return names;
	});

	const sourceOptions = $derived([
		{ value: '', label: 'All' },
		...sourceNames.map((source) => ({ value: source, label: source }))
	]);

	// A link may carry "referral" for the list's "Referral"; the pill still shows it as chosen.
	const selectedSource = $derived(
		sourceNames.find((name) => name.toLowerCase() === filters.source?.toLowerCase()) ?? ''
	);

	const dateOptions = BOARD_DATE_PRESETS.map((preset) => ({
		value: preset,
		label: BOARD_DATE_LABELS[preset]
	}));

	const arrow = $derived(filters.direction === 'desc' ? arrowDownIcon : arrowUpIcon);
	const arrowLabel = $derived(directionLabel(filters.sort, filters.direction));

	// The pickers speak CalendarDate; the URL speaks `2026-08-19`. Both ends are optional, so an empty one
	// stays undefined rather than becoming today.
	function toCalendarDate(day: string | undefined) {
		if (!day) return undefined;
		const [year, month, date] = day.split('-').map(Number);
		return new CalendarDate(year, month, date);
	}
	function toDay(value: CalendarDate | undefined) {
		if (!value) return undefined;
		return `${value.year}-${String(value.month).padStart(2, '0')}-${String(value.day).padStart(2, '0')}`;
	}

	// What a saved filter would remember, in words, for the Save dialog. Only the controls that differ from
	// an untouched board are named; the search box is never part of a saved filter.
	const savedSummary = $derived.by(() => {
		const parts: string[] = [];
		if (filters.owner !== 'all') {
			parts.push(
				`Salesperson: ${ownerOptions.find((option) => option.value === filters.owner)?.label ?? 'a former teammate'}`
			);
		}
		if (filters.source) parts.push(`Lead source: ${selectedSource || filters.source}`);
		if (filters.date === 'custom') {
			parts.push(`Created: ${filters.from ?? 'any time'} to ${filters.to ?? 'today'}`);
		} else if (filters.date !== 'all') {
			parts.push(`Created: ${BOARD_DATE_LABELS[filters.date]}`);
		}
		if (filters.sort !== 'attention' || filters.direction !== 'desc') {
			parts.push(
				`Sort: ${BOARD_SORT_LABELS[filters.sort]}${sortHasDirection(filters.sort) ? `, ${directionLabel(filters.sort, filters.direction).toLowerCase()}` : ''}`
			);
		}
		return parts.length
			? `This filter remembers ${parts.join(' · ')}.`
			: 'This filter remembers the board as it is now.';
	});

	function update(change: Partial<BoardFilters>) {
		onChange({ ...filters, ...change });
	}

	// Leaving a custom range takes its two ends with it, so a preset never carries a stale from/to into the
	// URL or the query key.
	function changeDate(date: BoardDatePreset) {
		onChange(
			date === 'custom'
				? { ...filters, date }
				: { ...filters, date, from: undefined, to: undefined }
		);
	}
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<div class="board-controls">
	<div class="board-controls__row">
		{@render leading?.()}

		<SearchInput
			id="pipeline-search"
			class="board-controls__search"
			bind:value={search}
			placeholder="Search cards"
			ariaLabel="Search cards by client, title, quote number, address, phone, or email"
		/>

		<SavedFiltersMenu {filters} summary={savedSummary} onApply={(next) => onChange(next)} />

		<span class="board-controls__pill board-controls__pill--labelled">
			<label class="board-controls__label" for="pipeline-sort">Sort by</label>
			<Select
				id="pipeline-sort"
				class="board-controls__select"
				value={filters.sort}
				options={sortOptions}
				onchange={(value) =>
					// The nearest close date is the useful first look, so that sort starts soonest first.
					update(
						value === 'close' ? { sort: 'close', direction: 'asc' } : { sort: value as BoardSort }
					)}
			/>
		</span>

		{#if sortHasDirection(filters.sort)}
			<button
				type="button"
				class="board-controls__direction"
				aria-label={arrowLabel}
				title={arrowLabel}
				onclick={() => update({ direction: filters.direction === 'desc' ? 'asc' : 'desc' })}
			>
				<span aria-hidden="true">{@html arrow}</span>
			</button>
		{/if}

		<span class="board-controls__pill board-controls__pill--labelled">
			<label class="board-controls__label" for="pipeline-owner">Salesperson</label>
			<Select
				id="pipeline-owner"
				class="board-controls__select"
				value={filters.owner}
				options={ownerOptions}
				onchange={(value) => update({ owner: value })}
			/>
		</span>

		<span
			class="board-controls__pill board-controls__pill--labelled"
			role="presentation"
			onpointerenter={() => (wantSources = true)}
			onfocusin={() => (wantSources = true)}
		>
			<label class="board-controls__label" for="pipeline-source">Lead source</label>
			<Select
				id="pipeline-source"
				class="board-controls__select"
				value={selectedSource}
				options={sourceOptions}
				onchange={(value) => update({ source: value || undefined })}
			/>
		</span>

		<!-- Jobber tells this pill apart with a calendar icon alone. Ours says the word, because the two
		pills beside it say theirs, and three pills reading "All" tell nobody which is which. -->
		<span class="board-controls__pill board-controls__pill--labelled">
			<label class="board-controls__label" for="pipeline-date">Created</label>
			<Select
				id="pipeline-date"
				class="board-controls__select"
				value={filters.date}
				options={dateOptions}
				onchange={(value) => changeDate(value as BoardDatePreset)}
			/>
		</span>

		<p class="board-controls__count" aria-live="polite">
			{#if resultCount !== null}
				({resultCount}
				{resultCount === 1 ? 'result' : 'results'})
			{/if}
		</p>
	</div>

	{#if filters.date === 'custom'}
		<div class="board-controls__row board-controls__row--range">
			<CalendarPicker
				id="pipeline-date-from"
				label="From"
				value={toCalendarDate(filters.from)}
				maxValue={toCalendarDate(filters.to)}
				onchange={(value) => update({ from: toDay(value) })}
			/>
			<CalendarPicker
				id="pipeline-date-to"
				label="To"
				value={toCalendarDate(filters.to)}
				minValue={toCalendarDate(filters.from)}
				onchange={(value) => update({ to: toDay(value) })}
			/>
			{#if !filters.from && !filters.to}
				<p class="board-controls__hint">Pick at least one end of the range.</p>
			{/if}
		</div>
	{/if}
</div>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.board-controls {
		display: flex;
		flex-direction: column;
		gap: var(--space-small);
	}
	.board-controls__row {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: var(--space-small);
	}
	// A fixed, name-sized box at the start of the row. On a narrow screen it takes the row to itself.
	.board-controls__row :global(.board-controls__search) {
		flex: 0 1 280px;
		width: auto;
		min-width: 200px;
		min-height: 44px;
	}
	.board-controls__row--range {
		align-items: end;
		gap: var(--space-base);
	}
	// The pickers fill their container by default, which on a bare row means one field per line stretched
	// across the page. They are two short dates, so they get a date-sized box and sit side by side.
	.board-controls__row--range :global(.calendar-picker) {
		width: 200px;
	}
	// Each control reads as one pill holding a fixed word and the value that answers it, the way the board
	// reference draws them.
	.board-controls__pill {
		display: inline-flex;
		align-items: center;
		border-radius: var(--radius-large);
		background: var(--color-inactive--surface);

		&--labelled {
			padding-left: var(--space-base);
		}
	}
	.board-controls__label {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		font-weight: 400;
		white-space: nowrap;
	}
	// The select inside a pill drops its own box and borrows the pill's, so the two do not draw two shapes.
	.board-controls__pill :global(.board-controls__select .select__trigger) {
		padding: 0 var(--space-slim);
		border: none;
		border-radius: var(--radius-large);
		background: transparent;
	}
	// A real width, because the dropdown sizes itself to its trigger: left to shrink-wrap inside the pill,
	// the trigger goes narrow and the open list truncates every option to a letter and an ellipsis.
	.board-controls__pill :global(.board-controls__select) {
		width: 176px;
	}
	.board-controls__direction {
		display: inline-flex;
		flex: 0 0 auto;
		align-items: center;
		justify-content: center;
		width: 44px;
		height: 44px;
		border: var(--border-base) solid var(--color-border--interactive);
		border-radius: var(--radius-base);
		color: var(--color-heading);
		background: var(--color-surface);
		cursor: pointer;

		:global(svg) {
			width: 20px;
			height: 20px;
		}
		&:hover {
			background: var(--color-surface--hover);
		}
		&:focus-visible {
			outline: none;
			box-shadow: var(--shadow-focus);
		}
	}
	.board-controls__count {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		font-variant-numeric: tabular-nums;
	}
	.board-controls__hint {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}
</style>
