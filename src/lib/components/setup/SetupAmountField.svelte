<script lang="ts">
	import Input from '$lib/components/ui/Input.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import {
		SETUP_DISTANCE_UNITS,
		SETUP_DURATION_UNITS,
		defaultDistanceUnit
	} from '$lib/setup/answer-values';

	// A setup answer that is an amount (client onboarding A5d): a number, a percentage, money in the business's
	// currency, or a distance or time with its unit beside it. Number and percentage are the number as typed;
	// the others are JSON text with the amount and its currency or unit (see `$lib/setup/answer-values`), so
	// the page saves them like any other answer. An empty amount is an empty answer.
	let {
		id,
		label,
		labelledby,
		kind,
		value = $bindable(''),
		currency,
		country,
		required = false,
		invalid = false,
		onedit,
		oncommit
	}: {
		id: string;
		label: string;
		/** The id of the question shown above; the box then carries no label of its own. */
		labelledby?: string;
		kind: 'number' | 'percentage' | 'money' | 'distance' | 'duration';
		value?: string;
		/** The business's currency, for money. */
		currency: string | null;
		/** The business's country, which suggests miles or kilometres. */
		country: string | null;
		required?: boolean;
		invalid?: boolean;
		onedit: () => void;
		oncommit: () => void;
	} = $props();

	function parse(raw: string): { amount?: unknown; unit?: unknown; currency?: unknown } {
		try {
			const parsed = JSON.parse(raw);
			return parsed && typeof parsed === 'object' ? parsed : {};
		} catch {
			return {};
		}
	}

	const units = $derived(
		kind === 'distance' ? SETUP_DISTANCE_UNITS : kind === 'duration' ? SETUP_DURATION_UNITS : null
	);
	const structured = $derived(kind === 'money' || units !== null);
	const stored = $derived(structured && value ? parse(value) : {});

	// The amount as saved, or the number itself for number and percentage.
	const amount = $derived(
		structured ? (stored.amount === undefined ? '' : String(stored.amount)) : value
	);

	// What the box shows is the text as typed, so a half-typed "99." is not tidied away under the cursor. It
	// follows the answer only when the answer changes from outside, such as when the page loads.
	let text = $state('');
	let written: string | null = null;
	$effect.pre(() => {
		if (value === written) return;
		written = value;
		text = amount;
	});

	// A unit picked before any amount is typed has nowhere to be saved yet, so it is held here.
	let pickedUnit = $state<string | null>(null);
	const unit = $derived(
		typeof stored.unit === 'string'
			? stored.unit
			: (pickedUnit ?? (kind === 'distance' ? defaultDistanceUnit(country) : 'minutes'))
	);

	// Money keeps the currency it was given in; a new amount takes the business's.
	const moneyCurrency = $derived(
		typeof stored.currency === 'string' ? stored.currency : (currency ?? '')
	);
	const currencySymbol = $derived.by(() => {
		if (!moneyCurrency) return '';
		try {
			return (
				new Intl.NumberFormat(undefined, { style: 'currency', currency: moneyCurrency })
					.formatToParts(0)
					.find((part) => part.type === 'currency')?.value ?? moneyCurrency
			);
		} catch {
			return moneyCurrency;
		}
	});

	function write(nextUnit = unit) {
		// Much of Europe writes 99,50; one comma and no point is read as a decimal comma.
		let typed = text.trim().replace(/\s/g, '');
		if (/^\d*,\d*$/.test(typed)) typed = typed.replace(',', '.');
		let next = typed;
		// Distance and time keep a number; money keeps the amount as typed so 99.50 stays 99.50. Text that is
		// not a number yet is kept as typed, so the save refuses it with a message rather than losing it.
		if (typed && kind === 'money')
			next = JSON.stringify({ amount: typed, currency: moneyCurrency });
		else if (typed && units)
			next = JSON.stringify({
				amount: /^\d+(\.\d+)?$/.test(typed) ? Number(typed) : typed,
				unit: nextUnit
			});
		written = next;
		value = next;
	}

	function typeAmount(event: Event) {
		text = (event.currentTarget as HTMLInputElement).value;
		write();
		onedit();
	}

	function chooseUnit(next: string) {
		pickedUnit = next;
		if (text.trim()) write(next);
		oncommit();
	}
</script>

<div class="setup-amount">
	<div class="setup-amount__row">
		<div
			class="setup-amount__box"
			class:setup-amount__box--prefixed={kind === 'money'}
			class:setup-amount__box--suffixed={kind === 'percentage'}
			style:--setup-amount-prefix-width={`${Math.max(currencySymbol.length, 1) + 2}ch`}
		>
			<Input
				{id}
				label={labelledby ? undefined : label}
				aria-labelledby={labelledby}
				inputmode="decimal"
				autocomplete="off"
				placeholder="0"
				value={text}
				{required}
				{invalid}
				oninput={typeAmount}
				onblur={oncommit}
			/>
			{#if kind === 'money' && currencySymbol}
				<span class="setup-amount__affix setup-amount__affix--prefix" aria-hidden="true"
					>{currencySymbol}</span
				>
			{:else if kind === 'percentage'}
				<span class="setup-amount__affix setup-amount__affix--suffix" aria-hidden="true">%</span>
			{/if}
		</div>
		{#if units}
			<div class="setup-amount__unit">
				<Select
					id={`${id}-unit`}
					label="Unit"
					options={[...units]}
					value={unit}
					onchange={chooseUnit}
				/>
			</div>
		{/if}
	</div>
	{#if kind === 'money' && moneyCurrency}
		<p class="setup-amount__note">In {moneyCurrency}</p>
	{/if}
</div>

<style lang="scss">
	.setup-amount {
		display: flex;
		flex-direction: column;
		gap: var(--space-smaller);
		min-width: 0;

		&__row {
			display: flex;
			align-items: flex-start;
			gap: var(--space-small);
		}

		&__box {
			position: relative;
			flex: 1 1 auto;
			min-width: 0;
			max-width: 32rem;

			&--prefixed :global(input) {
				padding-left: calc(var(--space-base) + var(--setup-amount-prefix-width));
			}

			&--suffixed :global(input) {
				padding-right: calc(var(--space-base) * 2 + 1ch);
			}
		}

		&__affix {
			position: absolute;
			bottom: 0;
			display: flex;
			align-items: center;
			height: var(--field-height, 4.8rem);
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-base);
			pointer-events: none;

			&--prefix {
				left: var(--space-base);
			}

			&--suffix {
				right: var(--space-base);
			}
		}

		&__unit {
			flex: 0 0 14rem;
		}

		&__note {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}
	}
</style>
