<script lang="ts">
	import Select from '$lib/components/ui/Select.svelte';
	import arrowLeftIcon from '@tabler/icons/outline/arrow-left.svg?raw';
	import arrowRightIcon from '@tabler/icons/outline/arrow-right.svg?raw';

	let {
		page,
		pageSize,
		totalCount,
		pageSizeOptions = [10, 20, 30, 40, 50],
		onPageChange,
		onPageSizeChange
	}: {
		page: number;
		pageSize: number;
		totalCount: number;
		pageSizeOptions?: number[];
		onPageChange: (page: number) => void;
		onPageSizeChange: (pageSize: number) => void;
	} = $props();

	const totalPages = $derived(Math.max(1, Math.ceil(totalCount / pageSize)));
	const first = $derived(totalCount === 0 ? 0 : (page - 1) * pageSize + 1);
	const last = $derived(Math.min(totalCount, page * pageSize));
	const pageSizeSelectOptions = $derived(
		pageSizeOptions.map((size) => ({ value: String(size), label: String(size) }))
	);
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<div class="pagination">
	<span class="pagination__info"
		>{totalCount === 0 ? 'No items' : `Showing ${first}-${last} of ${totalCount} items`}</span
	>
	{#if totalCount > 0}
		<div class="pagination__nav">
			<div class="pagination__page-size">
				<Select
					id="pagination-page-size"
					ariaLabel="Items per page"
					value={String(pageSize)}
					options={pageSizeSelectOptions}
					onchange={(value) => onPageSizeChange(Number(value))}
				/>
				<span class="pagination__page-size-label">per page</span>
			</div>
			<div class="pagination__buttons">
				<button
					type="button"
					class="pagination__button"
					aria-label="Previous page"
					disabled={page <= 1}
					onclick={() => onPageChange(page - 1)}><span aria-hidden="true">{@html arrowLeftIcon}</span
					></button
				>
				<button
					type="button"
					class="pagination__button"
					aria-label="Next page"
					disabled={page >= totalPages}
					onclick={() => onPageChange(page + 1)}><span aria-hidden="true">{@html arrowRightIcon}</span
					></button
				>
			</div>
		</div>
	{/if}
</div>
<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.pagination {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-small);
		min-height: 52px;
		padding: var(--space-small) var(--space-base);
		border-top: var(--border-base) solid var(--color-border);

		&__info {
			flex: 9999;
			color: var(--color-text);
			font-size: var(--typography--fontSize-base);
			white-space: nowrap;
		}
		&__nav {
			display: flex;
			flex: 1;
			flex-wrap: wrap;
			align-items: center;
			justify-content: space-between;
			gap: var(--space-base);
			min-width: fit-content;
		}
		&__page-size {
			display: flex;
			align-items: center;
			gap: var(--space-small);

			:global(.select) {
				width: auto;
				min-width: 152px;
			}
		}
		&__page-size-label {
			min-width: 68px;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-base);
		}
		&__buttons {
			display: flex;
			align-items: center;
			gap: var(--space-large);
		}
		&__button {
			display: grid;
			width: 40px;
			height: 40px;
			flex: 0 0 auto;
			place-items: center;
			padding: 0;
			border: var(--border-base) solid var(--color-border--interactive);
			border-radius: var(--radius-base);
			color: var(--color-interactive--subtle);
			background: var(--color-surface);
			transition: all var(--timing-quick) ease-out;

			span,
			span :global(svg) {
				display: block;
				width: 24px;
				height: 24px;
			}
			&:hover:not(:disabled) {
				color: var(--color-interactive--subtle--hover);
				border-color: var(--color-interactive--subtle--hover);
				background: var(--color-surface--hover);
			}
			&:focus-visible {
				outline: none;
				box-shadow: var(--shadow-focus);
			}
			&:disabled {
				color: var(--color-disabled);
				border-color: var(--color-disabled--secondary);
				cursor: not-allowed;
			}
		}
	}

	@media (max-width: 489px) {
		.pagination__buttons {
			gap: var(--space-base);
		}
	}
</style>
