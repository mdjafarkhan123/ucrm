<script lang="ts">
	import { Combobox } from 'bits-ui';
	import PaperworkFlag from '$lib/components/communications/paperwork/PaperworkFlag.svelte';
	import StatusBadge from '$lib/components/ui/StatusBadge.svelte';
	import IconTile from '$lib/components/ui/IconTile.svelte';
	import { searchCountries } from '$lib/settings/country-search';
	import { countryDisplayName } from '$lib/settings/country-names';
	import {
		DESTINATION_LABELS,
		diallingCode,
		formatRate,
		type CountryPrice,
		type Destination
	} from '$lib/communications/sms-destinations';
	import checkIcon from '@tabler/icons/outline/check.svg?raw';
	import chevronDownIcon from '@tabler/icons/outline/chevron-down.svg?raw';
	import searchIcon from '@tabler/icons/outline/search.svg?raw';
	import searchOffIcon from '@tabler/icons/outline/zoom-cancel.svg?raw';
	import xIcon from '@tabler/icons/outline/x.svg?raw';

	// The country box of "Text customers in another country" (`concept.pen` board `xGLYB`): a box naming the
	// chosen country with its dialling code; opened, a search over two groups — countries already on or asked
	// for (greyed with their status, never picked twice) and new countries with what a text costs there.
	// Countries Uplift doesn't offer are left out. Typing ranks matches the way the shared CountryPicker does.
	let {
		value = $bindable(''),
		id,
		labelledby,
		already,
		prices,
		notOffered,
		loading = false,
		disabled = false
	}: {
		/** The ISO code picked, e.g. "AU". */
		value?: string;
		id: string;
		/** The id of the question naming this box. */
		labelledby: string;
		/** Countries the business texts or asked for, which can't be asked for again. */
		already: Destination[];
		prices: Map<string, CountryPrice>;
		notOffered: Set<string>;
		loading?: boolean;
		disabled?: boolean;
	} = $props();

	let open = $state(false);
	let box = $state<HTMLElement | null>(null);
	let query = $state('');
	let alreadyCodes = $derived(new Map(already.map((entry) => [entry.country, entry])));
	let results = $derived(
		open ? searchCountries(query).filter((country) => !notOffered.has(country.code)) : []
	);
	let shownAlready = $derived(results.filter((country) => alreadyCodes.has(country.code)));
	let fresh = $derived(results.filter((country) => !alreadyCodes.has(country.code)));
	// Drawing every country at once is slow on a phone, so the list grows as it is scrolled.
	const ROWS_PER_PAGE = 50;
	let shownRows = $state(ROWS_PER_PAGE);
	let shownFresh = $derived(fresh.slice(0, shownRows));
	let items = $derived(fresh.map((country) => ({ value: country.code, label: country.name })));
	let name = $derived(value ? countryDisplayName(value) : '');

	function showMoreNearBottom(viewport: HTMLElement) {
		const nearBottom =
			viewport.scrollTop + viewport.clientHeight >= viewport.scrollHeight - viewport.clientHeight;
		if (nearBottom && shownRows < fresh.length) shownRows += ROWS_PER_PAGE * 2;
	}

	function begin() {
		if (disabled || loading) return;
		query = '';
		shownRows = ROWS_PER_PAGE;
		open = true;
	}

	function choose(code: string) {
		if (!code) return;
		value = code;
		query = '';
		open = false;
	}

	function priceOf(code: string) {
		const price = prices.get(code);
		return price?.segment != null ? formatRate(price.segment, price.currency) : null;
	}
</script>

<!-- The inline SVG strings are trusted build-time Tabler icon imports. -->
<!-- eslint-disable svelte/no-at-html-tags -->
{#if loading}
	<div class="country-box country-box--loading" aria-busy="true">
		<span class="country-box__spinner" aria-hidden="true"></span>
		<span class="country-box__placeholder">Loading countries…</span>
	</div>
{:else}
	<Combobox.Root
		type="single"
		bind:value={() => value, choose}
		bind:open={() => open, (next) => (next ? begin() : (open = false))}
		inputValue={open ? query : name}
		{items}
		{disabled}
	>
		<div bind:this={box} class="country-box" class:country-box--open={open} class:country-box--disabled={disabled}>
			{#if open}
				<span class="country-box__lead" aria-hidden="true">{@html searchIcon}</span>
			{:else if value}
				<PaperworkFlag code={value} size={24} />
			{/if}
			<Combobox.Input
				{id}
				class="country-box__input"
				placeholder={open ? 'Search countries' : 'Choose a country'}
				autocomplete="off"
				aria-labelledby={labelledby}
				onfocus={begin}
				onclick={begin}
				oninput={(event) => {
					query = event.currentTarget.value;
					shownRows = ROWS_PER_PAGE;
					open = true;
				}}
			/>
			{#if open && query}
				<button
					type="button"
					class="country-box__clear"
					aria-label="Clear search"
					onclick={() => (query = '')}>{@html xIcon}</button
				>
			{:else}
				{#if value && !open}<span class="country-box__dial">{diallingCode(value)}</span>{/if}
				<Combobox.Trigger class="country-box__trigger" aria-label="Show countries">
					<span aria-hidden="true">{@html chevronDownIcon}</span>
				</Combobox.Trigger>
			{/if}
		</div>
		<Combobox.Portal>
			<Combobox.Content
				class="country-box__menu"
				customAnchor={box}
				align="start" sideOffset={8} collisionPadding={8}>
				<Combobox.Viewport
					class="country-box__viewport"
					onscroll={(event: Event) => showMoreNearBottom(event.currentTarget as HTMLElement)}
				>
					{#if results.length === 0}
						<div class="country-box__empty">
							<IconTile icon={searchOffIcon} tone="inactive" size={32} />
							<strong>No country matches “{query.trim()}”</strong>
							<span>Uplift may not offer it yet. Ask us in Support.</span>
						</div>
					{:else}
						{#if shownAlready.length}
							<Combobox.Group class="country-box__group">
								<Combobox.GroupHeading class="country-box__heading"
									>Already on or asked for</Combobox.GroupHeading
								>
								{#each shownAlready as country (country.code)}
									{@const entry = alreadyCodes.get(country.code)}
									<Combobox.Item
										value={country.code}
										label={country.name}
										disabled
										class="country-box__option country-box__option--taken"
									>
										<PaperworkFlag code={country.code} size={20} />
										<span class="country-box__name">{country.name}</span>
										{#if entry && entry.status !== 'off'}
											<StatusBadge status={entry.status === 'ready' ? 'success' : 'warning'}>
												{DESTINATION_LABELS[entry.status]}
											</StatusBadge>
										{/if}
									</Combobox.Item>
								{/each}
							</Combobox.Group>
						{/if}
						{#if shownFresh.length}
							<Combobox.Group class="country-box__group">
								<Combobox.GroupHeading class="country-box__heading"
									>Ask for a new country</Combobox.GroupHeading
								>
								<!-- A fresh list per search: bits-ui highlights the top match only when items mount. -->
								{#key query}
									{#each shownFresh as country (country.code)}
										{@const price = priceOf(country.code)}
										<Combobox.Item
											value={country.code}
											label={country.name}
											class="country-box__option"
										>
											<PaperworkFlag code={country.code} size={20} />
											<span class="country-box__name">{country.name}</span>
											{#if price}
												<span class="country-box__price">{price} <small>a text</small></span>
											{:else}
												<span class="country-box__coming">Price coming</span>
											{/if}
											{#if value === country.code}
												<span class="country-box__check" aria-hidden="true">{@html checkIcon}</span>
											{/if}
										</Combobox.Item>
									{/each}
								{/key}
							</Combobox.Group>
						{/if}
					{/if}
				</Combobox.Viewport>
			</Combobox.Content>
		</Combobox.Portal>
	</Combobox.Root>
{/if}

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.country-box {
		position: relative;
		display: flex;
		align-items: center;
		gap: var(--space-slim);
		box-sizing: border-box;
		min-height: 44px;
		padding: 0 var(--space-small) 0 var(--space-slim);
		border: var(--border-base) solid var(--color-border--interactive);
		border-radius: var(--radius-base);
		background: var(--color-surface);
		transition: border-color var(--timing-quick);

		&:hover {
			border-color: var(--color-border--interactive--hover);
		}

		&--open,
		&--open:hover {
			border-color: var(--color-interactive);
			box-shadow: 0 0 0 0.5px var(--color-interactive);
		}

		&:focus-within:not(.country-box--open) {
			box-shadow: var(--shadow-focus);
		}

		&--disabled {
			opacity: 0.45;
			pointer-events: none;
		}

		&--loading {
			background: var(--color-surface--background--subtle);
			border-color: var(--color-border);
		}

		:global(input.country-box__input),
		:global(input.country-box__input:focus),
		:global(input.country-box__input:hover) {
			flex: 1 1 auto;
			box-shadow: none;
			border-radius: 0;
			min-width: 0;
			min-height: 42px;
			padding: 0;
			border: 0;
			outline: 0;
			color: var(--color-heading);
			background: transparent;
			font: inherit;
			font-size: var(--typography--fontSize-base);
			font-weight: 600;
			text-overflow: ellipsis;
		}

		:global(.country-box__input::placeholder) {
			color: var(--color-text--secondary);
			font-weight: 400;
		}

		&__lead,
		&__lead :global(svg),
		&__clear :global(svg) {
			display: block;
			width: 18px;
			height: 18px;
			color: var(--color-icon--secondary);
		}

		&__placeholder {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-base);
		}

		&__spinner {
			width: 16px;
			height: 16px;
			border: 2px solid var(--color-border);
			border-top-color: var(--color-conversation);
			border-radius: var(--radius-circle);
			animation: country-box-spin 0.8s linear infinite;
		}

		&__dial {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-smaller);
			font-weight: 600;
			font-variant-numeric: tabular-nums;
		}

		&__clear {
			display: grid;
			width: 28px;
			height: 28px;
			padding: 0;
			place-items: center;
			border: 0;
			border-radius: var(--radius-small);
			background: transparent;
			cursor: pointer;

			&:hover {
				background: var(--color-surface--hover);
			}

			&:focus-visible {
				outline: 0;
				box-shadow: var(--shadow-focus);
			}
		}
	}

	:global(.country-box__trigger) {
		display: grid;
		width: 28px;
		height: 28px;
		padding: 0;
		place-items: center;
		border: 0;
		border-radius: var(--radius-small);
		color: var(--color-icon--secondary);
		background: transparent;
		cursor: pointer;
	}

	:global(.country-box__trigger:focus-visible) {
		outline: 0;
		box-shadow: var(--shadow-focus);
	}

	:global(.country-box__trigger svg) {
		display: block;
		width: 18px;
		height: 18px;
	}

	:global(.country-box__menu) {
		z-index: var(--elevation-modal);
		box-sizing: border-box;
		width: var(--bits-floating-anchor-width);
		max-height: min(360px, var(--bits-floating-available-height));
		overflow: hidden;
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-large);
		background: var(--color-surface);
		box-shadow: var(--shadow-base);
	}

	:global(.country-box__viewport) {
		max-height: inherit;
		overflow-y: auto;
		padding: 6px;
		overscroll-behavior: contain;
	}

	:global(.country-box__heading) {
		padding: var(--space-small) var(--space-small) 6px;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-overline);
		font-weight: 600;
		letter-spacing: 0.6px;
		text-transform: uppercase;
	}

	:global(.country-box__option) {
		display: flex;
		align-items: center;
		gap: var(--space-slim);
		min-height: 40px;
		padding: 0 var(--space-small);
		border-radius: var(--radius-base);
		color: var(--color-heading);
		cursor: pointer;
		transition: background-color var(--timing-quick);
	}

	:global(.country-box__option[data-highlighted]) {
		background: var(--color-surface--hover);
	}

	:global(.country-box__option[data-selected]),
	:global(.country-box__option:active) {
		background: var(--color-surface--active);
	}

	:global(.country-box__option--taken) {
		cursor: default;
	}

	:global(.country-box__option--taken > :not(.status-badge)) {
		opacity: 0.6;
	}

	.country-box__name {
		flex: 1 1 auto;
		min-width: 0;
		overflow: hidden;
		font-size: var(--typography--fontSize-base);
		font-weight: 500;
		text-overflow: ellipsis;
		white-space: nowrap;
	}

	.country-box__price {
		color: var(--color-heading);
		font-size: var(--typography--fontSize-base);
		font-weight: 600;
		white-space: nowrap;

		small {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-smaller);
			font-weight: 400;
		}
	}

	.country-box__coming {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-smaller);
		white-space: nowrap;
	}

	.country-box__check,
	.country-box__check :global(svg) {
		display: block;
		width: 16px;
		height: 16px;
		color: var(--color-interactive);
	}

	.country-box__empty {
		display: grid;
		justify-items: center;
		gap: 6px;
		padding: var(--space-large) var(--space-base);
		text-align: center;

		strong {
			margin-top: var(--space-smaller);
			color: var(--color-heading);
			font-size: var(--typography--fontSize-base);
			font-weight: 600;
		}

		span {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-smaller);
		}
	}

	@keyframes country-box-spin {
		to {
			transform: rotate(360deg);
		}
	}
</style>
