<script lang="ts">
	import SearchInput from '$lib/components/ui/SearchInput.svelte';
	import Checkbox from '$lib/components/ui/Checkbox.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import EmptyState from '$lib/components/data-display/EmptyState.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import {
		formatMinor,
		formatPhone,
		numberTypeLabel,
		type NumberType,
		type ShopNumber
	} from '$lib/communications/sms-number-shop';
	import { placeLine } from './add-number';
	import messageIcon from '@tabler/icons/outline/message.svg?raw';
	import photoIcon from '@tabler/icons/outline/photo.svg?raw';
	import phoneIcon from '@tabler/icons/outline/phone.svg?raw';
	import minusIcon from '@tabler/icons/outline/minus.svg?raw';
	import searchIcon from '@tabler/icons/outline/search.svg?raw';

	// Step 2 of Add number (`concept.pen` board `qaFQf`): type digits, choose whether picture messages or calls are
	// needed, and pick from live numbers. Every number shown can text; five show at a time.
	let {
		contains = $bindable(),
		mms = $bindable(),
		voice = $bindable(),
		chosen = $bindable(),
		numberType,
		numbers,
		loading,
		failed,
		retry,
		monthlyMinor,
		currencyCode
	}: {
		contains: string;
		mms: boolean;
		voice: boolean;
		chosen: ShopNumber | null;
		numberType: NumberType;
		numbers: ShopNumber[] | undefined;
		loading: boolean;
		failed: boolean;
		retry: () => void;
		monthlyMinor: number;
		currencyCode: string;
	} = $props();

	const PAGE = 5;
	// "Show other numbers" moves through the results five at a time; a new search starts at its first five.
	let searchKey = $derived(`${contains}|${mms}|${voice}`);
	let paging = $state({ key: '', page: 0 });
	let page = $derived(paging.key === searchKey ? paging.page : 0);
	let total = $derived(numbers?.length ?? 0);
	let pages = $derived(Math.max(1, Math.ceil(total / PAGE)));
	let shown = $derived((numbers ?? []).slice(page * PAGE, page * PAGE + PAGE));
	let typeLabel = $derived(numberTypeLabel(numberType));
	let area = $derived(numbers?.[0]?.locality ? ` · ${numbers[0].locality.toUpperCase()} AREA` : '');
	let heading = $derived(
		`${total} ${total === 1 ? 'number' : 'numbers'}${contains ? ` for ${contains}` : ''}`
	);

	const abilities = [
		{ key: 'sms', icon: messageIcon, label: 'Text' },
		{ key: 'mms', icon: photoIcon, label: 'Pictures' },
		{ key: 'voice', icon: phoneIcon, label: 'Calls' }
	] as const;
</script>

<!-- The inline SVG strings are trusted build-time Tabler icon imports. -->
<!-- eslint-disable svelte/no-at-html-tags -->
<div class="add-number-list">
	<header class="add-number-list__head">
		<h3>Pick your number</h3>
		<p>Numbers near the area code you type. Every number shown can text.</p>
	</header>

	<div class="add-number-list__filters">
		<div class="add-number-list__search">
			<SearchInput
				id="add-number-digits"
				label="Area code or digits"
				placeholder="e.g. 512"
				ariaLabel="Area code or digits"
				bind:value={contains}
			/>
		</div>
		<Checkbox id="add-number-mms" label="Picture messages" bind:checked={mms} />
		<Checkbox id="add-number-voice" label="Calls" bind:checked={voice} />
	</div>

	<div class="add-number-list__card">
		<div class="add-number-list__card-head">
			<span>
				{#if failed}Couldn’t load numbers{:else if loading}Looking for numbers…{:else}{heading}{area}{/if}
			</span>
			<span>Price per month</span>
		</div>

		{#if failed}
			<ErrorState
				title="We couldn’t reach the phone company"
				description="Nothing was bought or charged. This is usually over in a minute."
				{retry}
			/>
		{:else if loading}
			<ul class="add-number-list__rows" aria-busy="true" aria-label="Looking for numbers">
				{#each [0, 1, 2, 3, 4] as slot (slot)}
					<li class="number-row number-row--loading">
						<span class="skeleton number-row__dot"></span>
						<span class="number-row__text">
							<span class="skeleton skeleton--text"></span>
							<span class="skeleton skeleton--text-short"></span>
						</span>
					</li>
				{/each}
			</ul>
		{:else if total === 0}
			<EmptyState
				icon={searchIcon}
				tone="conversation"
				title={contains ? `No numbers left for ${contains}` : 'No numbers left'}
				description={contains
					? 'Try other digits, or clear the search to see every number.'
					: 'Try again later, or try another kind of number.'}
			/>
		{:else}
			<div class="add-number-list__rows" role="radiogroup" aria-label="Numbers">
				{#each shown as number (number.phone_number)}
					{@const picked = chosen?.phone_number === number.phone_number}
					<label class="number-row" class:number-row--chosen={picked}>
						<input
							class="number-row__radio"
							type="radio"
							name="add-number-number"
							value={number.phone_number}
							checked={picked}
							onchange={() => (chosen = number)}
						/>
						<span class="number-row__text">
							<span class="number-row__number">{formatPhone(number.phone_number)}</span>
							<span class="number-row__place"
								>{placeLine(number.locality, number.region, typeLabel)}</span
							>
						</span>
						<span class="number-row__abilities">
							{#each abilities as ability (ability.key)}
								{@const on = number.capabilities[ability.key]}
								<span class="ability-pill" class:ability-pill--off={!on}>
									<span aria-hidden="true">{@html on ? ability.icon : minusIcon}</span>
									{#if on}{ability.label}{:else}<s>{ability.label}</s>{/if}
								</span>
							{/each}
						</span>
						<span class="number-row__price">
							<strong>{formatMinor(monthlyMinor, currencyCode)}</strong>
							<span>/month</span>
						</span>
					</label>
				{/each}
			</div>
			<footer class="add-number-list__foot">
				<span>Showing {shown.length} of {total}</span>
				{#if pages > 1}
					<Button
						variant="quiet"
						onclick={() => (paging = { key: searchKey, page: (page + 1) % pages })}
					>
						Show other numbers
					</Button>
				{/if}
			</footer>
		{/if}
	</div>
</div>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.add-number-list {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);

		&__head {
			h3 {
				margin: 0;
				color: var(--color-heading);
				font-size: var(--typography--fontSize-large);
				font-weight: 600;
			}

			p {
				margin: var(--space-smaller) 0 0;
				color: var(--color-text--secondary);
				font-size: var(--typography--fontSize-base);
			}
		}

		&__filters {
			display: flex;
			flex-wrap: wrap;
			align-items: flex-end;
			gap: var(--space-large);
		}

		&__search {
			width: 220px;
		}

		&__card {
			overflow: hidden;
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-large);
			background: var(--color-surface);
		}

		&__card-head {
			display: flex;
			justify-content: space-between;
			gap: var(--space-base);
			padding: var(--space-slim) var(--space-base);
			border-bottom: var(--border-base) solid var(--color-border);
			background: var(--color-surface--background--subtle);
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-smaller);
			font-weight: 600;

			span:first-child {
				text-transform: uppercase;
				letter-spacing: 0.04em;
			}
		}

		&__rows {
			display: flex;
			flex-direction: column;
			gap: var(--space-smaller);
			margin: 0;
			padding: var(--space-smaller);
			list-style: none;
		}

		&__foot {
			display: flex;
			align-items: center;
			justify-content: space-between;
			padding: var(--space-small) var(--space-base);
			border-top: var(--border-base) solid var(--color-border);
			background: var(--color-surface--background--subtle);
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}
	}

	.number-row {
		display: flex;
		align-items: center;
		gap: var(--space-base);
		padding: var(--space-small) var(--space-slim);
		border: var(--border-base) solid transparent;
		border-radius: var(--radius-base);
		cursor: pointer;

		&:hover {
			background: var(--color-surface--hover);
		}

		&:has(.number-row__radio:focus-visible) {
			outline: var(--border-thick) solid var(--color-focus);
		}

		&--chosen {
			border-color: var(--color-interactive);
			box-shadow: 0 0 0 0.5px var(--color-interactive);
			background: var(--color-surface);
		}

		&--loading {
			cursor: default;
		}

		&__radio {
			flex: 0 0 auto;
			width: 18px;
			height: 18px;
			margin: 0;
			accent-color: var(--color-interactive);
		}

		&__dot {
			width: 18px;
			height: 18px;
			border-radius: var(--radius-circle);
		}

		&__text {
			display: flex;
			flex: 1 1 auto;
			flex-direction: column;
			gap: var(--space-smallest);
			min-width: 0;
		}

		&__number {
			color: var(--color-heading);
			font-size: var(--typography--fontSize-base);
			font-weight: 600;
		}

		&__place {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-smaller);
		}

		&__abilities {
			display: flex;
			flex: 0 0 250px;
			gap: var(--space-smaller);
		}

		&__price {
			flex: 0 0 110px;
			color: var(--color-heading);
			font-size: var(--typography--fontSize-base);
			text-align: right;

			strong {
				font-weight: 600;
			}

			span {
				color: var(--color-text--secondary);
				font-size: var(--typography--fontSize-smaller);
			}
		}
	}

	.ability-pill {
		display: inline-flex;
		align-items: center;
		gap: var(--space-smaller);
		height: 24px;
		padding: 0 var(--space-small);
		border-radius: var(--radius-circle);
		background: var(--color-conversation--surface);
		color: var(--color-conversation--onSurface);
		font-size: var(--typography--fontSize-smaller);
		font-weight: 600;

		:global(svg) {
			width: 13px;
			height: 13px;
		}

		&--off {
			background: var(--color-surface--background--subtle);
			color: var(--color-text--secondary);
		}
	}
</style>
