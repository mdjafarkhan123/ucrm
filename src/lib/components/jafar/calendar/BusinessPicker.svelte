<script lang="ts">
	import { Combobox } from 'bits-ui';
	import { createQuery } from '@tanstack/svelte-query';
	import { jafarLeadsKey } from '$lib/jafar/query-keys';
	import { DEAL_STAGE_LABELS } from '$lib/jafar/deals';
	import { countryName, type LeadListItem, type LeadListPage } from '$lib/jafar/leads';
	import checkIcon from '@tabler/icons/outline/check.svg?raw';
	import chevronDownIcon from '@tabler/icons/outline/chevron-down.svg?raw';
	import exclamationCircleIcon from '@tabler/icons/outline/exclamation-circle.svg?raw';
	import searchIcon from '@tabler/icons/outline/search.svg?raw';

	// Jafar business management C2: search-and-pick one of Uplift's businesses -- a Lead, a Deal or a client --
	// for a call booked from the calendar. Same look and behaviour as the contractor ClientPicker; typing searches
	// the Leads list across every business.
	let {
		value = $bindable(''),
		id,
		invalid = false,
		errorMessage = '',
		required = false,
		placeholder = 'Search by business, contact or website',
		label = 'Business',
		onSelect
	}: {
		value?: string;
		id: string;
		invalid?: boolean;
		errorMessage?: string;
		required?: boolean;
		placeholder?: string;
		label?: string;
		onSelect?: (business: LeadListItem | null) => void;
	} = $props();

	let query = $state('');
	let open = $state(false);
	let debouncedQuery = $state('');
	let selected = $state<LeadListItem | null>(null);

	$effect(() => {
		const term = query.trim();
		const handle = setTimeout(() => (debouncedQuery = term), 300);
		return () => clearTimeout(handle);
	});

	async function search(term: string): Promise<LeadListItem[]> {
		const params = new URLSearchParams({ deal: 'any', limit: '8' });
		if (term) params.set('search', term);
		const response = await fetch(`/api/jafar/leads?${params}`);
		const result = await response.json().catch(() => ({}));
		if (!response.ok) throw new Error(result.error ?? 'Businesses could not be loaded.');
		return (result as LeadListPage).leads;
	}

	const businessesQuery = createQuery(() => ({
		queryKey: [...jafarLeadsKey, 'picker', debouncedQuery],
		queryFn: () => search(debouncedQuery),
		enabled: open,
		staleTime: 15_000,
		gcTime: 60_000
	}));
	const results = $derived(businessesQuery.data ?? []);
	const comboboxItems = $derived(
		results.map((business) => ({ value: business.id, label: business.business_name }))
	);

	function metaFor(business: LeadListItem) {
		const parts = [
			business.deal_stage ? DEAL_STAGE_LABELS[business.deal_stage] : null,
			business.contact_name,
			countryName(business.country_code)
		];
		return parts.filter(Boolean).join(' · ');
	}

	let inputValue = $derived(open ? query : (selected?.business_name ?? ''));
	let describedBy = $derived(errorMessage ? `${id}-error` : undefined);

	function focusPicker(input: HTMLInputElement) {
		query = '';
		open = true;
		input.select();
	}

	function chooseBusiness(businessId: string) {
		if (!businessId) {
			value = selected?.id ?? '';
			query = selected?.business_name ?? '';
			open = false;
			return;
		}
		const business = results.find((entry) => entry.id === businessId) ?? null;
		value = businessId;
		selected = business;
		query = business?.business_name ?? '';
		open = false;
		onSelect?.(business);
	}
</script>

<!-- The inline SVG strings are trusted build-time Tabler icon imports. -->
<!-- eslint-disable svelte/no-at-html-tags -->
<div class="business-picker" class:business-picker--invalid={invalid}>
	<label for={id}
		>{label}{#if required}<span aria-hidden="true">*</span>{/if}</label
	>
	<Combobox.Root
		type="single"
		bind:value
		bind:open
		{inputValue}
		items={comboboxItems}
		onValueChange={chooseBusiness}
	>
		<div class="business-picker__control">
			<span class="business-picker__search" aria-hidden="true">{@html searchIcon}</span>
			<Combobox.Input
				{id}
				{placeholder}
				autocomplete="off"
				aria-describedby={describedBy}
				aria-invalid={invalid}
				onfocus={(event) => focusPicker(event.currentTarget)}
				onclick={() => (open = true)}
				oninput={(event) => {
					query = event.currentTarget.value;
					open = true;
				}}
			/>
			<Combobox.Trigger class="business-picker__trigger" aria-label="Show businesses">
				<span aria-hidden="true">{@html chevronDownIcon}</span>
			</Combobox.Trigger>
		</div>
		<Combobox.Portal>
			<Combobox.Content
				class="business-picker__menu"
				data-elevation="elevated"
				align="start"
				sideOffset={4}
				collisionPadding={8}
			>
				<Combobox.Viewport class="business-picker__viewport">
					{#if businessesQuery.isPending}
						<div class="business-picker__empty">Searching…</div>
					{:else if businessesQuery.isError}
						<div class="business-picker__empty" role="alert">
							Businesses could not be loaded. Try again.
						</div>
					{:else}
						{#each results as business (business.id)}
							<Combobox.Item
								value={business.id}
								label={business.business_name}
								class="business-picker__option"
							>
								<span class="business-picker__option-copy">
									<strong>{business.business_name}</strong>
									<small>{metaFor(business)}</small>
								</span>
								{#if value === business.id}<span class="business-picker__check" aria-hidden="true"
										>{@html checkIcon}</span
									>{/if}
							</Combobox.Item>
						{:else}<div class="business-picker__empty">
								{debouncedQuery ? `No business matches “${debouncedQuery}”.` : 'No businesses yet.'}
							</div>{/each}
					{/if}
				</Combobox.Viewport>
			</Combobox.Content>
		</Combobox.Portal>
	</Combobox.Root>
	{#if errorMessage}<p class="business-picker__error" id={`${id}-error`} role="alert">
			<span aria-hidden="true">{@html exclamationCircleIcon}</span>{errorMessage}
		</p>{/if}
</div>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.business-picker {
		width: 100%;
	}
	.business-picker > label {
		display: block;
		margin-bottom: var(--space-smaller);
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		font-weight: 500;
	}
	.business-picker > label span {
		color: var(--color-critical);
	}
	.business-picker__control {
		position: relative;
		display: flex;
		min-height: var(--space-largest);
		align-items: center;
		border: var(--border-base) solid var(--color-border--interactive);
		border-radius: var(--radius-base);
		background: var(--color-surface);
	}
	.business-picker__control:focus-within {
		z-index: var(--elevation-base);
		box-shadow: var(--shadow-focus);
	}
	.business-picker--invalid .business-picker__control {
		border-color: var(--color-critical);
	}
	.business-picker__control :global(input) {
		width: 100%;
		min-width: 0;
		min-height: calc(var(--space-largest) - (var(--border-base) * 2));
		padding: var(--space-small) var(--space-largest);
		border: 0;
		outline: 0;
		color: var(--color-heading);
		background: transparent;
		font: inherit;
	}
	.business-picker__search {
		position: absolute;
		left: var(--space-base);
		display: grid;
		width: 16px;
		height: 16px;
		place-items: center;
		color: var(--color-icon--secondary);
		pointer-events: none;
	}
	:global(.business-picker__trigger) {
		position: absolute;
		right: 0;
		display: grid;
		width: var(--space-largest);
		height: 100%;
		place-items: center;
		border: 0;
		border-radius: 0 var(--radius-base) var(--radius-base) 0;
		outline: 0;
		color: var(--color-icon--secondary);
		background: transparent;
		cursor: pointer;
	}
	:global(.business-picker__trigger:focus-visible) {
		box-shadow: var(--shadow-focus);
	}
	:global(.business-picker__trigger[data-state='open']) span {
		transform: rotate(180deg);
	}
	:global(.business-picker__trigger span) {
		display: grid;
		width: 18px;
		height: 18px;
		place-items: center;
		transition: transform var(--timing-quick);
	}
	:global(.business-picker__trigger svg),
	.business-picker__search :global(svg),
	.business-picker__check :global(svg),
	.business-picker__error :global(svg) {
		display: block;
		width: 16px;
		height: 16px;
	}
	:global(.business-picker__menu) {
		z-index: var(--elevation-modal);
		width: var(--bits-floating-anchor-width);
		max-height: min(300px, var(--bits-floating-available-height));
		overflow: hidden;
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface);
		box-shadow: var(--shadow-base);
	}
	:global(.business-picker__viewport) {
		max-height: inherit;
		overflow-y: auto;
		padding: var(--space-small);
	}
	:global(.business-picker__option) {
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
		transition:
			color var(--timing-quick),
			background-color var(--timing-quick);
	}
	:global(.business-picker__option[data-highlighted]) {
		color: var(--color-heading);
		background: var(--color-surface--hover);
	}
	.business-picker__option-copy {
		display: grid;
		min-width: 0;
		flex: 1;
		gap: 2px;
	}
	.business-picker__option-copy strong {
		overflow: hidden;
		color: inherit;
		font-size: var(--typography--fontSize-base);
		font-weight: 500;
		text-overflow: ellipsis;
		white-space: nowrap;
	}
	.business-picker__option-copy small {
		overflow: hidden;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		text-overflow: ellipsis;
		white-space: nowrap;
	}
	.business-picker__check {
		display: grid;
		width: 16px;
		height: 16px;
		flex: 0 0 16px;
		place-items: center;
		color: var(--color-interactive);
	}
	.business-picker__empty {
		padding: var(--space-base);
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		text-align: center;
	}
	.business-picker__error {
		display: flex;
		align-items: center;
		gap: var(--space-smaller);
		margin: var(--space-smaller) 0 0;
		color: var(--color-critical);
		font-size: var(--typography--fontSize-small);
	}
</style>
