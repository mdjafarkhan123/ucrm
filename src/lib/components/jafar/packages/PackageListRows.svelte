<script lang="ts" generics="T">
	import type { Snippet } from 'svelte';
	import arrowUpIcon from '@tabler/icons/outline/arrow-up.svg?raw';
	import arrowDownIcon from '@tabler/icons/outline/arrow-down.svg?raw';
	import trashIcon from '@tabler/icons/outline/trash.svg?raw';
	import plusIcon from '@tabler/icons/outline/plus.svg?raw';
	import Button from '$lib/components/ui/Button.svelte';

	// An ordered list the builder edits in place — customer highlights and included services. Each row
	// brings its own fields; this owns the order, the remove button, and the add button.
	let {
		items = $bindable(),
		itemName,
		addLabel,
		max,
		emptyText,
		create,
		row
	}: {
		items: T[];
		/** Names a row for screen readers: "highlight" gives "Move highlight 2 up". */
		itemName: string;
		addLabel: string;
		max: number;
		emptyText: string;
		create: () => T;
		/** One row's fields, given the row's position in `items`. */
		row: Snippet<[number]>;
	} = $props();

	function move(index: number, by: number) {
		const next = [...items];
		const [moved] = next.splice(index, 1);
		next.splice(index + by, 0, moved);
		items = next;
	}

	function remove(index: number) {
		items = items.filter((_, position) => position !== index);
	}
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<div class="package-list-rows">
	{#if items.length === 0}
		<p class="package-list-rows__empty">{emptyText}</p>
	{:else}
		<ol class="package-list-rows__list">
			{#each items.keys() as index (index)}
				<li class="package-list-rows__row">
					<span class="package-list-rows__number" aria-hidden="true">{index + 1}</span>
					<div class="package-list-rows__fields">{@render row(index)}</div>
					<div class="package-list-rows__actions">
						<button
							type="button"
							class="package-list-rows__icon-button"
							aria-label={`Move ${itemName} ${index + 1} up`}
							disabled={index === 0}
							onclick={() => move(index, -1)}>{@html arrowUpIcon}</button
						>
						<button
							type="button"
							class="package-list-rows__icon-button"
							aria-label={`Move ${itemName} ${index + 1} down`}
							disabled={index === items.length - 1}
							onclick={() => move(index, 1)}>{@html arrowDownIcon}</button
						>
						<button
							type="button"
							class="package-list-rows__icon-button package-list-rows__icon-button--danger"
							aria-label={`Remove ${itemName} ${index + 1}`}
							onclick={() => remove(index)}>{@html trashIcon}</button
						>
					</div>
				</li>
			{/each}
		</ol>
	{/if}
	<div>
		<Button
			variant="secondary"
			size="small"
			disabled={items.length >= max}
			onclick={() => (items = [...items, create()])}
		>
			<span class="package-list-rows__button-icon" aria-hidden="true">{@html plusIcon}</span
			>{addLabel}
		</Button>
	</div>
</div>

<style lang="scss">
	.package-list-rows {
		display: grid;
		gap: var(--space-base);

		&__empty {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__list {
			display: grid;
			gap: var(--space-small);
			margin: 0;
			padding: 0;
			list-style: none;
		}

		&__row {
			display: grid;
			grid-template-columns: 2.4rem minmax(0, 1fr) auto;
			align-items: start;
			gap: var(--space-small);
		}

		&__number {
			padding-top: var(--space-slim);
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			font-variant-numeric: tabular-nums;
			text-align: end;
		}

		&__fields {
			display: grid;
			gap: var(--space-small);
		}

		&__actions {
			display: flex;
			gap: var(--space-smallest);
			padding-top: var(--space-smaller);
		}

		&__icon-button {
			display: grid;
			place-items: center;
			width: 32px;
			height: 32px;
			padding: 0;
			border: var(--border-base) solid transparent;
			border-radius: var(--radius-base);
			color: var(--color-icon--secondary);
			background: none;
			cursor: pointer;
			transition: all var(--timing-quick) ease-out;

			:global(svg) {
				width: 18px;
				height: 18px;
			}

			&:hover:not(:disabled),
			&:focus-visible:not(:disabled) {
				border-color: var(--color-border--interactive);
				color: var(--color-interactive);
			}
			&:focus-visible {
				outline: none;
				box-shadow: var(--shadow-focus);
			}
			&:disabled {
				color: var(--color-disabled);
				cursor: not-allowed;
			}
			&--danger:hover:not(:disabled),
			&--danger:focus-visible:not(:disabled) {
				border-color: var(--color-critical);
				color: var(--color-critical);
			}
		}

		&__button-icon {
			display: inline-flex;
			width: 1.6rem;
			height: 1.6rem;

			:global(svg) {
				width: 100%;
				height: 100%;
			}
		}
	}
</style>
