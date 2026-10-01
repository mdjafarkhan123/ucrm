<script lang="ts">
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import DropdownMenu from '$lib/components/ui/DropdownMenu.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import SaveFilterDialog from './SaveFilterDialog.svelte';
	import ManageSavedFiltersDialog from './ManageSavedFiltersDialog.svelte';
	import {
		fetchSavedFilters,
		savedFiltersKey,
		updateSavedFilter,
		type SavedFilter
	} from '$lib/pipeline/api';
	import {
		filtersFromSavedQuery,
		savedFilterQuery,
		type BoardFilters
	} from '$lib/pipeline/filters';
	import bookmarkIcon from '@tabler/icons/outline/bookmark.svg?raw';
	import checkIcon from '@tabler/icons/outline/check.svg?raw';
	import chevronIcon from '@tabler/icons/outline/chevron-down.svg?raw';
	import plusIcon from '@tabler/icons/outline/bookmark-plus.svg?raw';
	import editIcon from '@tabler/icons/outline/bookmark-edit.svg?raw';
	import settingsIcon from '@tabler/icons/outline/adjustments-horizontal.svg?raw';

	// The board's saved filters: pick one to put the board back the way it was saved, save the current
	// controls under a name, or bring a filter up to date with what the board shows now (Pipedrive and
	// HubSpot both work this way). It never touches the board itself — choosing a filter reports the
	// controls it holds, and the page puts them in the URL like any other change.
	let {
		filters,
		summary,
		onApply
	}: {
		filters: BoardFilters;
		summary: string;
		onApply: (next: BoardFilters) => void;
	} = $props();

	const queryClient = useQueryClient();
	const toast = getToastManager();

	// A list that has to be opened, so it loads when the button is pointed at or focused, not with the
	// page. Once loaded it is cached, and the button can name the filter the board is on.
	let wanted = $state(false);
	const listQuery = createQuery(() => ({
		queryKey: savedFiltersKey,
		queryFn: fetchSavedFilters,
		enabled: wanted,
		staleTime: 300_000
	}));

	let saveOpen = $state(false);
	let manageOpen = $state(false);
	let updating = $state(false);
	// The filter last chosen from this menu. Once the person changes a control, the board no longer
	// matches it, and the menu offers to update it rather than forgetting which filter they started from.
	let chosenId = $state<string | null>(null);

	const all = $derived(listQuery.data?.filters ?? []);
	const mine = $derived(all.filter((filter) => !filter.shared));
	const shared = $derived(all.filter((filter) => filter.shared));
	const current = $derived(savedFilterQuery(filters));

	// The board matches a saved filter exactly: name it. Otherwise, if it started from one and has been
	// changed since, that one is still the one being worked on.
	const matched = $derived(all.find((filter) => filter.query === current) ?? null);
	const chosen = $derived(all.find((filter) => filter.id === chosenId) ?? null);
	const edited = $derived(!matched && current !== '' && chosen ? chosen : null);

	function apply(filter: SavedFilter) {
		chosenId = filter.id;
		onApply(filtersFromSavedQuery(filter.query));
	}

	async function updateChosen(filter: SavedFilter) {
		if (updating) return;
		updating = true;
		try {
			await updateSavedFilter(filter.id, { filters });
			await queryClient.invalidateQueries({ queryKey: savedFiltersKey });
			toast.success(`“${filter.name}” updated`);
		} catch (thrown) {
			toast.error(thrown instanceof Error ? thrown.message : 'That filter could not be updated.');
		} finally {
			updating = false;
		}
	}

	const filterItem = (filter: SavedFilter) => ({
		key: filter.id,
		label: filter.name,
		trailingIcon: matched?.id === filter.id ? checkIcon : undefined,
		note: matched?.id === filter.id ? 'showing now' : undefined,
		onSelect: () => apply(filter)
	});

	const groups = $derived.by(() => {
		if (!listQuery.data) {
			return [
				{
					heading: 'Saved filters',
					items: [
						{
							key: 'status',
							label: listQuery.isError ? 'Saved filters could not be loaded' : 'Loading…',
							disabled: !listQuery.isError,
							onSelect: () => void listQuery.refetch()
						}
					]
				}
			];
		}
		if (all.length === 0) {
			return [
				{
					heading: 'Saved filters',
					items: [
						{ key: 'empty', label: 'No saved filters yet', disabled: true, onSelect: () => {} }
					]
				}
			];
		}
		return [
			...(mine.length ? [{ heading: 'Your filters', items: mine.map(filterItem) }] : []),
			...(shared.length ? [{ heading: 'Shared with the team', items: shared.map(filterItem) }] : [])
		];
	});

	const footer = $derived([
		...(edited?.can_edit
			? [
					{
						key: 'update',
						label: `Update “${edited.name}”`,
						icon: editIcon,
						disabled: updating,
						onSelect: () => void updateChosen(edited)
					}
				]
			: []),
		{
			key: 'save',
			label: 'Save current filters…',
			icon: plusIcon,
			// Nothing to remember on an untouched board.
			disabled: current === '' || !listQuery.data,
			onSelect: () => (saveOpen = true)
		},
		...(all.some((filter) => filter.can_edit)
			? [
					{
						key: 'manage',
						label: 'Manage saved filters…',
						icon: settingsIcon,
						onSelect: () => (manageOpen = true)
					}
				]
			: [])
	]);

	const buttonLabel = $derived(matched?.name ?? edited?.name ?? 'None');
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<span
	class="saved-filters"
	role="presentation"
	onpointerenter={() => (wanted = true)}
	onfocusin={() => (wanted = true)}
>
	<DropdownMenu
		{groups}
		{footer}
		wide
		align="start"
		triggerClass="saved-filters__trigger"
		triggerLabel={`Saved filters: ${buttonLabel}${edited ? ', changed' : ''}`}
	>
		{#snippet trigger()}
			<span class="saved-filters__icon" aria-hidden="true">{@html bookmarkIcon}</span>
			<span class="saved-filters__label">Saved</span>
			<span class="saved-filters__value">{buttonLabel}</span>
			{#if edited}<span class="saved-filters__edited">Changed</span>{/if}
			<span class="saved-filters__chevron" aria-hidden="true">{@html chevronIcon}</span>
		{/snippet}
	</DropdownMenu>
</span>
<!-- eslint-enable svelte/no-at-html-tags -->

<SaveFilterDialog
	open={saveOpen}
	{filters}
	{summary}
	canShare={listQuery.data?.can_share ?? false}
	onSaved={(filter) => {
		chosenId = filter.id;
		saveOpen = false;
	}}
	onClose={() => (saveOpen = false)}
/>

<ManageSavedFiltersDialog open={manageOpen} filters={all} onClose={() => (manageOpen = false)} />

<style lang="scss">
	.saved-filters {
		display: inline-flex;
	}
	// Drawn as one more pill in the row: a fixed word and the value that answers it.
	.saved-filters :global(.saved-filters__trigger) {
		display: inline-flex;
		align-items: center;
		gap: var(--space-smaller);
		min-height: 44px;
		max-width: 280px;
		padding: 0 var(--space-small) 0 var(--space-base);
		border: none;
		border-radius: var(--radius-large);
		color: var(--color-heading);
		background: var(--color-inactive--surface);
		font: inherit;
		font-size: var(--typography--fontSize-base);
		cursor: pointer;

		&:hover {
			background: var(--color-surface--hover);
		}
		&:focus-visible {
			outline: none;
			box-shadow: var(--shadow-focus);
		}
	}
	.saved-filters__icon,
	.saved-filters__chevron {
		display: inline-grid;
		flex: 0 0 auto;
		place-items: center;
		color: var(--color-icon--secondary);

		:global(svg) {
			width: 16px;
			height: 16px;
		}
	}
	.saved-filters__label {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}
	.saved-filters__value {
		min-width: 0;
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}
	.saved-filters__edited {
		flex: 0 0 auto;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		font-style: italic;
	}
</style>
