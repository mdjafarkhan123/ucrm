<script lang="ts">
	import { Combobox } from 'bits-ui';
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import {
		catalogItemsKey,
		fetchCatalogItems,
		type CatalogItem,
		type CatalogItemFilter
	} from '$lib/quotes/api';
	import CatalogItemDialog from './CatalogItemDialog.svelte';
	import plusIcon from '@tabler/icons/outline/plus.svg?raw';

	// A line's name field with a catalog search riding underneath it — pick a reusable default, or just
	// keep typing to make a one-off line. Nothing here decides whether typing without a pick is valid: a
	// custom line is a perfectly normal request pricing row, so this never blocks on "no match found".
	let {
		value = $bindable(''),
		id,
		label,
		labor,
		disabled = false,
		placeholder = '',
		invalid = false,
		errorMessage = '',
		currencyCode,
		locale,
		onBlur,
		onSelect
	}: {
		value?: string;
		id: string;
		/** Floating field label, same shape as `ui/Input.svelte`. Pass this instead of a placeholder. */
		label?: string;
		/** Narrows the search when a caller still splits the price list; omitted searches everything. */
		labor?: CatalogItemFilter;
		disabled?: boolean;
		/** The organization's currency, so each result can show its price. Omitted hides the price. */
		currencyCode?: string;
		locale?: string;
		placeholder?: string;
		invalid?: boolean;
		errorMessage?: string;
		/** Fires when the field is left for good — not while the person is reaching for the list. */
		onBlur?: () => void;
		onSelect?: (item: CatalogItem) => void;
	} = $props();

	// This is a custom combobox rather than an `Input`, so it carries its own copy of the floating-label
	// behavior. Same rule as `ui/Input.svelte`: a placeholder lifts the label too, or the two overlap.
	let hasValue = $derived(Boolean(value) || Boolean(placeholder));

	const queryClient = useQueryClient();
	let open = $state(false);
	let debouncedQuery = $state('');

	$effect(() => {
		const term = value.trim();
		const handle = setTimeout(() => (debouncedQuery = term), 300);
		return () => clearTimeout(handle);
	});

	function warm() {
		void queryClient.prefetchQuery({
			queryKey: catalogItemsKey({ labor }),
			queryFn: () => fetchCatalogItems({ labor })
		});
	}

	const itemsQuery = createQuery(() => ({
		queryKey: catalogItemsKey({ search: debouncedQuery, labor }),
		queryFn: () => fetchCatalogItems({ search: debouncedQuery, labor }),
		enabled: open,
		staleTime: 15_000,
		gcTime: 60_000,
		// A denied or not-yet-entitled catalog is not a broken row — it just means every line here is
		// typed by hand, so a failed search retries quietly instead of nagging the person.
		retry: false
	}));
	const results = $derived(itemsQuery.data?.items ?? []);
	const comboboxItems = $derived(results.map((item) => ({ value: item.id, label: item.name })));

	// The list reads as the price list itself, under its own headings, rather than one flat run of names.
	// The API already hands back one page in name order, so the grouping is only a split, never a re-sort.
	const groups = $derived(
		(
			[
				{ label: 'Products', category: 'product' },
				{ label: 'Services', category: 'service' }
			] as const
		)
			.map((group) => ({
				label: group.label,
				items: results.filter((item) => item.category === group.category)
			}))
			.filter((group) => group.items.length > 0)
	);

	// Built once per currency rather than once per row — a long price list would otherwise make a fresh
	// formatter for every result on every keystroke.
	const moneyFormatter = $derived(
		currencyCode
			? new Intl.NumberFormat(locale ?? 'en-US', {
					style: 'currency',
					currency: currencyCode,
					minimumFractionDigits: 2
				})
			: null
	);
	const formatMoney = (minor: number) => moneyFormatter?.format(minor / 100) ?? '';

	let creating = $state(false);

	function choose(itemId: string) {
		const item = results.find((entry) => entry.id === itemId);
		open = false;
		if (!item) return;
		value = item.name;
		onSelect?.(item);
	}

	function startCreate() {
		open = false;
		creating = true;
	}

	function created(item: CatalogItem) {
		creating = false;
		// The new item has to show up the next time somebody searches for it, on this line or any other.
		void queryClient.invalidateQueries({ queryKey: ['catalog-items'] });
		value = item.name;
		onSelect?.(item);
	}
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<div
	class="catalog-picker"
	class:catalog-picker--has-value={hasValue}
	class:catalog-picker--invalid={invalid}
>
	<Combobox.Root
		type="single"
		{open}
		onOpenChange={(next) => (open = next)}
		inputValue={value}
		items={comboboxItems}
		onValueChange={choose}
	>
		{#if label}<label class="catalog-picker__label" for={id}>{label}</label>{/if}
		<div class="catalog-picker__control">
			<Combobox.Input
				{id}
				{placeholder}
				{disabled}
				autocomplete="off"
				onfocus={() => (open = true)}
				onclick={() => (open = true)}
				oninput={(event) => {
					value = event.currentTarget.value;
					open = true;
				}}
				onmouseenter={warm}
				aria-invalid={invalid}
				aria-describedby={errorMessage ? `${id}-error` : undefined}
				onblur={() => {
					// Reaching for the list blurs the input on the way, and the list is still open at that
					// moment. Looking again once the click has settled tells the two apart: still open means
					// the person is inside the picker, shut means they really have left the field.
					setTimeout(() => {
						if (!open) onBlur?.();
					}, 0);
				}}
			/>
		</div>
		<Combobox.Portal>
			<Combobox.Content
				class="catalog-picker__menu"
				data-elevation="elevated"
				align="start"
				sideOffset={4}
				collisionPadding={8}
			>
				<Combobox.Viewport class="catalog-picker__viewport">
					{#if itemsQuery.isPending}
						<div class="catalog-picker__empty">Searching…</div>
					{:else if itemsQuery.isError}
						<div class="catalog-picker__empty">Keep typing to add this as a one-off line.</div>
					{:else if groups.length === 0}
						<div class="catalog-picker__empty">
							{debouncedQuery
								? `No price list match for “${debouncedQuery}”. Keep typing to add it as a one-off line.`
								: 'Nothing in the price list yet — keep typing to add a one-off line.'}
						</div>
					{:else}
						{#each groups as group (group.label)}
							<Combobox.Group>
								<Combobox.GroupHeading class="catalog-picker__heading">
									{group.label}
								</Combobox.GroupHeading>
								{#each group.items as item (item.id)}
									<Combobox.Item value={item.id} label={item.name} class="catalog-picker__option">
										<span class="catalog-picker__option-copy">
											<strong>{item.name}</strong>
											{#if item.description}<small>{item.description}</small>{/if}
										</span>
										{#if moneyFormatter}
											<span class="catalog-picker__option-price"
												>{formatMoney(item.unit_price_minor)}</span
											>
										{/if}
									</Combobox.Item>
								{/each}
							</Combobox.Group>
						{/each}
					{/if}
				</Combobox.Viewport>
				<div class="catalog-picker__footer">
					<button type="button" class="catalog-picker__create" onclick={startCreate}>
						<span aria-hidden="true">{@html plusIcon}</span>
						Create new item
					</button>
				</div>
			</Combobox.Content>
		</Combobox.Portal>
	</Combobox.Root>
	{#if errorMessage}
		<p class="catalog-picker__error" id={`${id}-error`} role="alert">{errorMessage}</p>
	{/if}
</div>

{#if creating}
	<CatalogItemDialog
		open={creating}
		name={value}
		onSaved={created}
		onClose={() => (creating = false)}
	/>
{/if}

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.catalog-picker {
		position: relative;
		width: 100%;
		font-size: var(--typography--fontSize-base);
	}
	.catalog-picker__label {
		position: absolute;
		z-index: var(--elevation-base);
		top: 50%;
		left: var(--space-base);
		max-width: calc(100% - var(--space-largest));
		overflow: hidden;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-base);
		text-overflow: ellipsis;
		white-space: nowrap;
		transform: translateY(-50%);
		transition: all var(--timing-quick);
		pointer-events: none;
	}
	.catalog-picker:focus-within .catalog-picker__label,
	.catalog-picker--has-value .catalog-picker__label {
		top: var(--space-smallest);
		font-size: var(--typography--fontSize-small);
		transform: none;
	}
	.catalog-picker__control {
		position: relative;
		display: flex;
		align-items: center;
		min-height: var(--space-largest);
		border: var(--border-base) solid var(--color-border--interactive);
		border-radius: var(--radius-base);
		background: var(--color-surface);
	}
	.catalog-picker__control:focus-within {
		box-shadow: var(--shadow-focus);
	}
	.catalog-picker--invalid .catalog-picker__control {
		border-color: var(--color-critical);
	}
	.catalog-picker__error {
		padding-top: var(--space-smaller);
		color: var(--color-critical);
		font-size: var(--typography--fontSize-small);
	}
	.catalog-picker__control :global(input) {
		width: 100%;
		min-width: 0;
		padding: calc(var(--space-base) - var(--space-smallest)) var(--space-base);
		border: 0;
		outline: 0;
		color: var(--color-heading);
		background: transparent;
		font: inherit;
		line-height: 20px;
	}
	.catalog-picker:focus-within .catalog-picker__control :global(input),
	.catalog-picker--has-value .catalog-picker__control :global(input) {
		padding-top: calc(var(--space-base) + var(--space-smaller));
		padding-bottom: var(--space-small);
	}
	:global(.catalog-picker__menu) {
		z-index: var(--elevation-modal);
		display: flex;
		width: var(--bits-floating-anchor-width);
		flex-direction: column;
		max-height: min(320px, var(--bits-floating-available-height));
		overflow: hidden;
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface);
		box-shadow: var(--shadow-base);
	}
	:global(.catalog-picker__viewport) {
		min-height: 0;
		flex: 1;
		overflow-y: auto;
		padding: var(--space-small);
	}
	:global(.catalog-picker__heading) {
		padding: var(--space-small) var(--space-small) var(--space-smaller);
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		font-weight: 600;
	}
	:global(.catalog-picker__option) {
		display: flex;
		width: 100%;
		align-items: center;
		gap: var(--space-small);
		padding: var(--space-small);
		border: 0;
		border-radius: var(--radius-small);
		outline: 0;
		color: var(--color-text);
		background: transparent;
		text-align: left;
		cursor: pointer;
	}
	:global(.catalog-picker__option[data-highlighted]) {
		color: var(--color-heading);
		background: var(--color-surface--hover);
	}
	.catalog-picker__option-price {
		flex-shrink: 0;
		color: var(--color-heading);
		font-size: var(--typography--fontSize-base);
		font-variant-numeric: tabular-nums;
		white-space: nowrap;
	}
	.catalog-picker__footer {
		flex-shrink: 0;
		padding: var(--space-small);
		border-top: var(--border-base) solid var(--color-border);
		background: var(--color-surface);
	}
	.catalog-picker__create {
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
		font-weight: 500;
		text-align: left;
		cursor: pointer;
	}
	.catalog-picker__create:hover {
		background: var(--color-surface--hover);
	}
	.catalog-picker__create :global(svg) {
		display: block;
		width: 16px;
		height: 16px;
	}
	.catalog-picker__option-copy {
		display: grid;
		min-width: 0;
		flex: 1;
		gap: 2px;
	}
	.catalog-picker__option-copy strong {
		overflow: hidden;
		font-size: var(--typography--fontSize-base);
		font-weight: 500;
		text-overflow: ellipsis;
		white-space: nowrap;
	}
	.catalog-picker__option-copy small {
		overflow: hidden;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		text-overflow: ellipsis;
		white-space: nowrap;
	}
	.catalog-picker__empty {
		padding: var(--space-base);
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		text-align: center;
	}
</style>
