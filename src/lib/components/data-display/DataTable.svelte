<script module lang="ts">
	export type DataTableColumn = {
		key: string;
		label: string;
		align?: 'start' | 'end';
		/** This column's header becomes a button that calls `onSortChange` with its key. Needs `sort` and
		 * `onSortChange` on the table to do anything. */
		sortable?: boolean;
	};
	export type DataTableSort = { key: string; direction: 'asc' | 'desc' };
</script>

<script lang="ts" generics="T">
	import type { Snippet } from 'svelte';
	import Checkbox from '$lib/components/ui/Checkbox.svelte';
	import selectorIcon from '@tabler/icons/outline/selector.svg?raw';
	import chevronUpIcon from '@tabler/icons/outline/chevron-up.svg?raw';
	import chevronDownIcon from '@tabler/icons/outline/chevron-down.svg?raw';

	let {
		columns,
		items,
		rowId,
		caption,
		selectable = false,
		selectedIds = $bindable(new Set<string>()),
		rowLabel,
		onRowActivate,
		sort,
		onSortChange,
		row,
		rowActions,
		footer
	}: {
		columns: DataTableColumn[];
		items: T[];
		rowId: (item: T) => string;
		caption: string;
		selectable?: boolean;
		selectedIds?: Set<string>;
		/** Names a row's own checkbox, e.g. "Select Riverbend Diner". Without it every row's checkbox is
		 * called the same thing and a screen reader cannot tell them apart. */
		rowLabel?: (item: T) => string;
		onRowActivate?: (item: T) => void;
		/** The column currently sorted, if any. Null/undefined means the table's default order. */
		sort?: DataTableSort | null;
		/** Called with a sortable column's key when its header is activated. The caller owns the toggle
		 * logic (same key flips direction, a different key starts ascending) and hands the result back
		 * through `sort` — this component never decides direction on its own. */
		onSortChange?: (key: string) => void;
		row: Snippet<[T]>;
		rowActions?: Snippet<[T]>;
		footer?: Snippet;
	} = $props();

	function ariaSort(column: DataTableColumn) {
		if (!column.sortable) return undefined;
		if (sort?.key !== column.key) return 'none';
		return sort.direction === 'asc' ? 'ascending' : 'descending';
	}
	function sortIcon(column: DataTableColumn) {
		if (sort?.key !== column.key) return selectorIcon;
		return sort.direction === 'asc' ? chevronUpIcon : chevronDownIcon;
	}

	const allSelected = $derived(
		items.length > 0 && items.every((item) => selectedIds.has(rowId(item)))
	);
	const someSelected = $derived(items.some((item) => selectedIds.has(rowId(item))) && !allSelected);

	function toggleAll(checked: boolean) {
		const next = new Set(selectedIds);
		for (const item of items) {
			if (checked) next.add(rowId(item));
			else next.delete(rowId(item));
		}
		selectedIds = next;
	}
	// Clicking anywhere on a row opens the record. Controls inside the row keep their own jobs, and a click
	// that was really a drag to select text is left alone. Keyboard and new-tab use go through the real link
	// each table puts on its first cell, so the row itself never becomes a second tab stop.
	function activateRow(event: MouseEvent, item: T) {
		if (!onRowActivate) return;
		const target = event.target as HTMLElement | null;
		if (target?.closest('a, button, input, label, select, textarea, [role="menuitem"]')) return;
		if ((window.getSelection()?.toString() ?? '').length > 0) return;
		onRowActivate(item);
	}

	function toggleRow(id: string, checked: boolean) {
		const next = new Set(selectedIds);
		if (checked) next.add(id);
		else next.delete(id);
		selectedIds = next;
	}
</script>

<div class="data-table" role="region" aria-label={caption}>
	<table>
		<caption>{caption}</caption>
		<thead>
			<tr>
				{#if selectable}
					<th scope="col" class="data-table__select-cell">
						<Checkbox
							id="data-table-select-all"
							label="Select all rows on this page"
							indeterminate={someSelected}
							bind:checked={() => allSelected, toggleAll}
						/>
					</th>
				{/if}
				{#each columns as column (column.key)}
					<th scope="col" class:align-end={column.align === 'end'} aria-sort={ariaSort(column)}>
						{#if column.sortable && onSortChange}
							<!-- eslint-disable svelte/no-at-html-tags -->
							<button
								type="button"
								class="data-table__sort"
								class:data-table__sort--active={sort?.key === column.key}
								onclick={() => onSortChange?.(column.key)}
							>
								{column.label}
								<span class="data-table__sort-icon" aria-hidden="true"
									>{@html sortIcon(column)}</span
								>
							</button>
							<!-- eslint-enable svelte/no-at-html-tags -->
						{:else}
							{column.label}
						{/if}
					</th>
				{/each}
				{#if rowActions}
					<th scope="col" class="data-table__actions-cell">Actions</th>
				{/if}
			</tr>
		</thead>
		<tbody>
			{#each items as item (rowId(item))}
				<tr
					class:data-table__row--clickable={Boolean(onRowActivate)}
					onclick={(event) => activateRow(event, item)}
				>
					{#if selectable}
						<td class="data-table__select-cell">
							<Checkbox
								id={`data-table-select-${rowId(item)}`}
								label={rowLabel ? rowLabel(item) : 'Select row'}
								bind:checked={
									() => selectedIds.has(rowId(item)), (checked) => toggleRow(rowId(item), checked)
								}
							/>
						</td>
					{/if}
					{@render row(item)}
					{#if rowActions}
						<td class="data-table__actions-cell">{@render rowActions(item)}</td>
					{/if}
				</tr>
			{/each}
		</tbody>
	</table>
	{#if footer}{@render footer()}{/if}
</div>

<style lang="scss">
	.data-table {
		overflow-x: auto;
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface);
	}
	table {
		width: 100%;
		border-collapse: collapse;
		color: var(--color-text);
		font-size: var(--typography--fontSize-base);
		text-align: start;
	}
	caption {
		position: absolute;
		width: 1px;
		height: 1px;
		overflow: hidden;
		clip: rect(0 0 0 0);
		clip-path: inset(50%);
		white-space: nowrap;
	}
	/* The row/rowActions cells come from the parent's snippet, so they carry the PARENT's Svelte scope
	   class, not this component's. Anything that must style them has to reach past this component's own
	   scoping with :global(), anchored under .data-table so it stays contained to this table. */
	.data-table :global(thead) {
		background: var(--color-surface--background--subtle);
	}
	.data-table :global(th),
	.data-table :global(td) {
		padding: var(--space-slim) var(--space-large);
		border-bottom: var(--border-base) solid var(--color-border);
		vertical-align: middle;
		text-align: start;
	}
	.data-table :global(thead th) {
		color: var(--color-text);
		font-weight: 700;
		white-space: nowrap;
	}
	.data-table :global(tbody th) {
		color: var(--color-heading);
		font-weight: 700;
		white-space: nowrap;
	}
	.data-table :global(tbody td) {
		color: var(--color-text--secondary);
	}
	.data-table :global(tbody th),
	.data-table :global(tbody td) {
		padding-top: var(--space-base);
		padding-bottom: var(--space-base);
	}
	.data-table :global(tbody tr:last-child th),
	.data-table :global(tbody tr:last-child td) {
		border-bottom: 0;
	}
	.data-table :global(tbody tr:hover) {
		background: var(--color-surface--hover);
	}
	.data-table :global(tbody tr.data-table__row--clickable) {
		cursor: pointer;
	}
	.data-table :global(.align-end) {
		text-align: end;
	}
	.data-table__sort {
		display: inline-flex;
		align-items: center;
		gap: var(--space-smaller);
		margin: calc(var(--space-slim) * -1) calc(var(--space-large) * -1);
		padding: var(--space-slim) var(--space-large);
		border: 0;
		background: none;
		color: inherit;
		font: inherit;
		font-weight: inherit;
		cursor: pointer;

		&:hover {
			color: var(--color-heading);
		}
		&:focus-visible {
			outline: none;
			box-shadow: var(--shadow-focus);
		}
	}
	.data-table__sort--active {
		color: var(--color-interactive);
	}
	.data-table__sort-icon {
		display: inline-flex;
		flex: 0 0 auto;
		color: var(--color-text--secondary);

		:global(svg) {
			width: 14px;
			height: 14px;
		}
	}
	.data-table__sort--active .data-table__sort-icon {
		color: var(--color-interactive);
	}
	.data-table__select-cell {
		width: 40px;
		/* Row-select checkboxes only need the box, not the visible label text. */
		:global(.checkbox__label) {
			position: absolute;
			width: 1px;
			height: 1px;
			overflow: hidden;
			clip: rect(0 0 0 0);
		}
	}
	.data-table__actions-cell {
		width: 48px;
		text-align: end;
	}
	.data-table:focus-visible {
		outline: none;
		box-shadow: var(--shadow-focus);
	}
</style>
