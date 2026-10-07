<script lang="ts">
	import { Combobox } from 'bits-ui';
	import checkIcon from '@tabler/icons/outline/check.svg?raw';
	import chevronDownIcon from '@tabler/icons/outline/chevron-down.svg?raw';
	import exclamationCircleIcon from '@tabler/icons/outline/exclamation-circle.svg?raw';
	import searchIcon from '@tabler/icons/outline/search.svg?raw';
	import {
		allCountryOptions,
		findCountryOption,
		searchCountries
	} from '$lib/settings/country-search';

	// A type-to-search country box saving the ISO code, the way GOV.UK's country autocomplete and
	// Shopify's Polaris combobox work: type "uk", "ger" or "ivory", pick with arrows and Enter.
	let {
		value = $bindable(''),
		id,
		label,
		ariaLabel,
		ariaLabelledby,
		placeholder = 'Search countries',
		required = false,
		disabled = false,
		invalid = false,
		errorMessage = '',
		onchange
	}: {
		/** ISO 3166-1 alpha-2 code, e.g. "PK". */
		value?: string;
		id: string;
		label?: string;
		ariaLabel?: string;
		/** The id of a question already shown elsewhere, naming the picker instead of a label. */
		ariaLabelledby?: string;
		placeholder?: string;
		required?: boolean;
		disabled?: boolean;
		invalid?: boolean;
		errorMessage?: string;
		onchange?: (code: string) => void;
	} = $props();

	const items = allCountryOptions().map((country) => ({
		value: country.code,
		label: country.name
	}));
	let query = $state('');
	let open = $state(false);
	let selected = $derived(findCountryOption(value));
	let inputValue = $derived(open ? query : (selected?.name ?? ''));
	// Reopening on a chosen country shows the whole list, not just that one country.
	let results = $derived(searchCountries(query === selected?.name ? '' : query));
	let searchKey = $derived(results.length === allCountryOptions().length ? '' : query);
	let describedBy = $derived(errorMessage ? `${id}-error` : undefined);

	function focusInput(input: HTMLInputElement) {
		query = selected?.name ?? '';
		open = true;
		input.select();
	}

	function choose(code: string) {
		lastCommitted = code;
		value = code;
		query = findCountryOption(code)?.name ?? '';
		open = false;
		onchange?.(code);
	}

	// bits-ui's Combobox keeps its own copy of the shown text once an option is picked and never re-reads
	// `inputValue`. When the caller changes `value` itself (a Cancel that restores the saved country),
	// remount so the box shows it. Remounting on every pick would drop focus and break tabbing onwards.
	let lastCommitted = value;
	let resetKey = $state(0);
	$effect(() => {
		if (value !== lastCommitted) {
			lastCommitted = value;
			resetKey++;
		}
	});
</script>

<!-- The inline SVG strings are trusted build-time Tabler icon imports. -->
<!-- eslint-disable svelte/no-at-html-tags -->
<div
	class="country-picker"
	class:country-picker--invalid={invalid}
	class:country-picker--disabled={disabled}
>
	{#if label}
		<label for={id}
			>{label}{#if required}
				<span aria-hidden="true">*</span>{/if}</label
		>
	{/if}
	{#key resetKey}
		<Combobox.Root
			type="single"
			bind:value
			bind:open
			{inputValue}
			{items}
			{disabled}
			{required}
			onValueChange={choose}
		>
			<div class="country-picker__control">
				{#if selected && !open}
					<span class="country-picker__lead country-picker__flag" aria-hidden="true"
						>{selected.flag}</span
					>
				{:else}
					<span class="country-picker__lead" aria-hidden="true">{@html searchIcon}</span>
				{/if}
				<Combobox.Input
					{id}
					{placeholder}
					autocomplete="off"
					aria-label={label ? undefined : ariaLabel}
					aria-labelledby={ariaLabelledby}
					aria-describedby={describedBy}
					aria-invalid={invalid}
					onfocus={(event) => focusInput(event.currentTarget)}
					onclick={() => (open = true)}
					oninput={(event) => {
						query = event.currentTarget.value;
						open = true;
					}}
				/>
				<Combobox.Trigger class="country-picker__trigger" aria-label="Show countries">
					<span aria-hidden="true">{@html chevronDownIcon}</span>
				</Combobox.Trigger>
			</div>
			<Combobox.Portal>
				<Combobox.Content
					class="country-picker__menu"
					data-elevation="elevated"
					align="start"
					sideOffset={4}
					collisionPadding={8}
				>
					<Combobox.Viewport class="country-picker__viewport">
						<!-- A fresh list per search: bits-ui highlights the top match only when items mount, so
						     Enter picks it the way every country autocomplete does. -->
						{#key searchKey}
							{#each results as country (country.code)}
								<Combobox.Item
									value={country.code}
									label={country.name}
									class="country-picker__option"
								>
									<span class="country-picker__flag" aria-hidden="true">{country.flag}</span>
									<span class="country-picker__name">{country.name}</span>
									{#if value === country.code}<span class="country-picker__check" aria-hidden="true"
											>{@html checkIcon}</span
										>{:else}<span class="country-picker__code" aria-hidden="true"
											>{country.code}</span
										>{/if}
								</Combobox.Item>
							{:else}<div class="country-picker__empty">No countries match “{query}”.</div>{/each}
						{/key}
					</Combobox.Viewport>
				</Combobox.Content>
			</Combobox.Portal>
		</Combobox.Root>
	{/key}
	{#if errorMessage}<p class="country-picker__error" id={`${id}-error`} role="alert">
			<span aria-hidden="true">{@html exclamationCircleIcon}</span>{errorMessage}
		</p>{/if}
</div>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.country-picker {
		width: 100%;
		min-width: 0;
	}
	.country-picker > label {
		display: block;
		margin-bottom: var(--space-smaller);
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		font-weight: 500;
	}
	.country-picker > label span {
		color: var(--color-critical);
	}
	.country-picker__control {
		position: relative;
		display: flex;
		min-height: var(--space-largest);
		align-items: center;
		border: var(--border-base) solid var(--color-border--interactive);
		border-radius: var(--radius-base);
		background: var(--color-surface);
	}
	.country-picker__control:focus-within {
		z-index: var(--elevation-base);
		box-shadow: var(--shadow-focus);
	}
	.country-picker--invalid .country-picker__control {
		border-color: var(--color-critical);
	}
	.country-picker--disabled .country-picker__control {
		border-color: var(--color-border);
		color: var(--color-disabled);
		background: var(--color-disabled--secondary);
		cursor: not-allowed;
	}
	.country-picker__control :global(input) {
		width: 100%;
		min-width: 0;
		min-height: calc(var(--space-largest) - (var(--border-base) * 2));
		padding: var(--space-small) var(--space-largest);
		border: 0;
		outline: 0;
		color: var(--color-heading);
		background: transparent;
		font: inherit;
		text-overflow: ellipsis;
	}
	.country-picker__control :global(input:disabled) {
		color: var(--color-disabled);
		cursor: not-allowed;
	}
	.country-picker__control :global(input::placeholder) {
		color: var(--color-text--secondary);
	}
	.country-picker__lead {
		position: absolute;
		left: var(--space-base);
		display: grid;
		width: 18px;
		height: 18px;
		place-items: center;
		color: var(--color-icon--secondary);
		pointer-events: none;
	}
	.country-picker__flag {
		display: inline-grid;
		width: 20px;
		flex: 0 0 20px;
		place-items: center;
		font-size: 16px;
		line-height: 1;
	}
	:global(.country-picker__trigger) {
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
	:global(.country-picker__trigger:disabled) {
		cursor: not-allowed;
	}
	:global(.country-picker__trigger:focus-visible) {
		box-shadow: var(--shadow-focus);
	}
	:global(.country-picker__trigger span) {
		display: grid;
		width: 18px;
		height: 18px;
		place-items: center;
		transition: transform var(--timing-quick);
	}
	:global(.country-picker__trigger[data-state='open'] span) {
		transform: rotate(180deg);
	}
	:global(.country-picker__trigger svg),
	.country-picker__lead :global(svg),
	.country-picker__check :global(svg),
	.country-picker__error :global(svg) {
		display: block;
		width: 16px;
		height: 16px;
	}
	:global(.country-picker__menu) {
		z-index: var(--elevation-modal);
		width: max(var(--bits-floating-anchor-width), 240px);
		max-height: min(320px, var(--bits-floating-available-height));
		overflow: hidden;
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface);
		box-shadow: var(--shadow-base);
	}
	:global(.country-picker__viewport) {
		max-height: inherit;
		overflow-y: auto;
		padding: var(--space-small);
		overscroll-behavior: contain;
	}
	:global(.country-picker__option) {
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
	:global(.country-picker__option[data-highlighted]) {
		color: var(--color-heading);
		background: var(--color-surface--hover);
	}
	:global(.country-picker__option[data-selected]) {
		color: var(--color-heading);
		font-weight: 500;
	}
	.country-picker__name {
		min-width: 0;
		flex: 1;
		overflow: hidden;
		font-size: var(--typography--fontSize-base);
		text-overflow: ellipsis;
		white-space: nowrap;
	}
	.country-picker__code {
		flex: 0 0 auto;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		font-variant-numeric: tabular-nums;
		letter-spacing: 0.02em;
	}
	.country-picker__check {
		display: grid;
		width: 16px;
		height: 16px;
		flex: 0 0 16px;
		place-items: center;
		color: var(--color-interactive);
	}
	.country-picker__empty {
		padding: var(--space-base);
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		text-align: center;
	}
	.country-picker__error {
		display: flex;
		align-items: center;
		gap: var(--space-smaller);
		margin: var(--space-smaller) 0 0;
		color: var(--color-critical);
		font-size: var(--typography--fontSize-small);
	}
</style>
