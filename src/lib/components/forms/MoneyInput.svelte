<script lang="ts">
	import { page } from '$app/state';
	import Input from '$lib/components/ui/Input.svelte';

	// Binds a whole-cents integer (minor units, the shape every quote/catalog amount crosses the API
	// boundary as) behind a plain decimal-dollar text field — the same inline-edit shape the Pipeline's
	// estimated-value field already uses. Typing is free text; a blur is where a valid amount becomes the
	// committed minor-unit value, and an invalid one snaps back to the last good one rather than saving junk.
	let {
		value = $bindable(0),
		id,
		label,
		size = 'base',
		required = false,
		invalid = false,
		errorMessage = '',
		disabled = false,
		placeholder = '0.00',
		currencyCode,
		decimals = 2
	}: {
		value?: number;
		id: string;
		label?: string;
		size?: 'small' | 'base' | 'large';
		required?: boolean;
		invalid?: boolean;
		errorMessage?: string;
		disabled?: boolean;
		placeholder?: string;
		currencyCode?: string;
		/** Digits after the point `value` counts in: 2 is cents; 4 suits per-text prices such as $0.0079. */
		decimals?: number;
	} = $props();

	const currency = $derived(
		currencyCode ?? ('currencyCode' in page.data ? (page.data.currencyCode as string) : 'USD')
	);
	const symbol = $derived(
		new Intl.NumberFormat('en-US', { style: 'currency', currency, currencyDisplay: 'narrowSymbol' })
			.formatToParts(0)
			.find((part) => part.type === 'currency')?.value ?? currency
	);
	const scale = $derived(10 ** decimals);

	function fromMinor(minor: number) {
		return (minor / scale).toLocaleString('en-US', {
			minimumFractionDigits: 2,
			maximumFractionDigits: decimals
		});
	}

	let draft = $state(fromMinor(value));
	let focused = $state(false);

	// The external value only overwrites what is being typed once the field is not the one changing it —
	// otherwise a save elsewhere on the page would yank the cursor mid-keystroke.
	$effect(() => {
		if (!focused) draft = fromMinor(value);
	});

	function commit() {
		focused = false;
		const parsed = Number(draft.replace(/,/g, ''));
		if (!Number.isFinite(parsed) || parsed < 0) {
			draft = fromMinor(value);
			return;
		}
		value = Math.round(parsed * scale);
		draft = fromMinor(value);
	}
</script>

<div class="money-input" class:money-input--small={size === 'small'}>
	<Input
		{id}
		{label}
		{size}
		{required}
		{invalid}
		{errorMessage}
		{disabled}
		type="text"
		inputmode="decimal"
		aria-describedby={`${id}-currency`}
		{placeholder}
		bind:value={draft}
		onfocus={() => {
			focused = true;
			draft = fromMinor(value).replace(/,/g, '');
		}}
		onblur={commit}
		onkeydown={(event: KeyboardEvent) => {
			if (event.key === 'Enter') (event.currentTarget as HTMLInputElement).blur();
		}}
	>
		<span class="money-input__currency" id={`${id}-currency`}>{symbol}</span>
	</Input>
</div>

<style lang="scss">
	.money-input {
		:global(.input__control) {
			padding-left: 0;
			overflow: hidden;
		}
		:global(input) {
			text-align: right;
			font-weight: 600;
		}
		&__currency {
			display: grid;
			align-self: stretch;
			place-items: center;
			min-width: 40px;
			border-right: var(--border-base) solid var(--color-border--interactive);
			background: var(--color-surface--background--subtle);
			color: var(--color-heading);
			font-weight: 600;
		}
		&--small &__currency {
			min-width: 36px;
		}
		:global(.input--disabled) &__currency {
			color: var(--color-disabled);
			background: var(--color-disabled--secondary);
		}
	}
</style>
