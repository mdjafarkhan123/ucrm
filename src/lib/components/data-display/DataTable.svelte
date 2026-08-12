<script lang="ts">
	export type DataTableColumn = { key: string; label: string; align?: 'start' | 'end' };

	let {
		columns,
		rows,
		rowKey = 'id',
		caption
	}: {
		columns: DataTableColumn[];
		rows: Record<string, unknown>[];
		rowKey?: string;
		caption: string;
	} = $props();
</script>

<div class="data-table" role="region" aria-label={caption}>
	<table>
		<caption>{caption}</caption>
		<thead
			><tr
				>{#each columns as column (column.key)}<th
						scope="col"
						class:align-end={column.align === 'end'}>{column.label}</th
					>{/each}</tr
			></thead
		>
		<tbody>
			{#each rows as row (String(row[rowKey]))}
				<tr>
					{#each columns as column, index (column.key)}
						{#if index === 0}<th scope="row" class:align-end={column.align === 'end'}
								>{row[column.key] ?? '—'}</th
							>{:else}<td class:align-end={column.align === 'end'}>{row[column.key] ?? '—'}</td
							>{/if}
					{/each}
				</tr>
			{/each}
		</tbody>
	</table>
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
	thead {
		background: var(--color-surface--background--subtle);
	}
	th,
	td {
		padding: var(--space-slim) var(--space-large);
		border-bottom: var(--border-base) solid var(--color-border);
		vertical-align: middle;
		text-align: start;
	}
	thead th {
		color: var(--color-text);
		font-weight: 700;
	}
	tbody th {
		color: var(--color-heading);
		font-weight: 700;
		white-space: nowrap;
	}
	tbody td {
		padding-top: var(--space-base);
		padding-bottom: var(--space-base);
	}
	tbody tr:last-child th,
	tbody tr:last-child td {
		border-bottom: 0;
	}
	tbody tr:hover {
		background: var(--color-surface--hover);
	}
	.align-end {
		text-align: end;
	}
	.data-table:focus-visible {
		outline: none;
		box-shadow: var(--shadow-focus);
	}
</style>
