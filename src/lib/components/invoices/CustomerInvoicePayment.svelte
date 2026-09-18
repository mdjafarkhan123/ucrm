<script lang="ts">
	import Button from '$lib/components/ui/Button.svelte';
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import MoneyInput from '$lib/components/forms/MoneyInput.svelte';
	import type { CustomerInvoicePayment } from '$lib/invoices/customer-document';
	import lockIcon from '@tabler/icons/outline/lock.svg?raw';

	// The customer's Pay button (docs/online-payments-behavior-contract.md §3). It only asks for an amount and a
	// tip; the server re-checks both against the invoice and sends back a Stripe payment page to go to. Nothing
	// is marked paid from here — Stripe confirms the payment to the server, and the page shows it when it has.
	//
	// When the whole balance is the only choice, the button goes straight to Stripe. The window opens only when
	// the business allows part payments or tips on this invoice, the way Jobber's client hub does it.
	let {
		payment,
		currencyCode,
		token
	}: {
		payment: CustomerInvoicePayment;
		currencyCode: string;
		token: string;
	} = $props();

	const money = $derived(
		new Intl.NumberFormat('en-US', { style: 'currency', currency: currencyCode })
	);
	const format = (minor: number) => money.format(minor / 100);

	const TIP_PERCENTS = [10, 15, 20] as const;
	type TipChoice = 'none' | `${(typeof TIP_PERCENTS)[number]}` | 'custom';

	const asksFirst = $derived(payment.partial_allowed || payment.tips_enabled);

	let open = $state(false);
	let amountMinor = $state(0);
	let tipChoice = $state<TipChoice>('none');
	let customTipMinor = $state(0);
	// Checked only once they have tried to pay, then kept current as they correct the amount.
	let triedToPay = $state(false);
	let error = $state('');
	let starting = $state(false);

	// Tips are worked out on the pre-tax subtotal and paid on top; they never change what the invoice owes.
	function percentTip(percent: number) {
		return Math.round((payment.tip_base_minor * percent) / 100);
	}

	const tipMinor = $derived(
		!payment.tips_enabled || tipChoice === 'none'
			? 0
			: tipChoice === 'custom'
				? customTipMinor
				: percentTip(Number(tipChoice))
	);
	const payingMinor = $derived(payment.partial_allowed ? amountMinor : payment.balance_minor);
	const amountProblem = $derived(
		!payingMinor || payingMinor <= 0
			? 'Enter how much you would like to pay.'
			: payingMinor > payment.balance_minor
				? `That is more than the ${format(payment.balance_minor)} still owed.`
				: ''
	);
	const amountError = $derived(triedToPay ? amountProblem : '');

	function openDialog() {
		amountMinor = payment.balance_minor;
		tipChoice = 'none';
		customTipMinor = 0;
		triedToPay = false;
		error = '';
		open = true;
	}

	function confirm() {
		triedToPay = true;
		if (amountProblem) return;
		void start(payingMinor, tipMinor);
	}

	async function start(amount: number, tip: number) {
		error = '';
		starting = true;
		try {
			const response = await fetch(`/api/public/invoices/${token}/checkout`, {
				method: 'POST',
				headers: { 'content-type': 'application/json' },
				body: JSON.stringify({ amount_minor: amount, tip_minor: tip })
			});
			const body = await response.json().catch(() => ({}));
			if (!response.ok || typeof body.url !== 'string') {
				error = body.error ?? 'The payment page could not be opened. Please try again in a moment.';
				starting = false;
				return;
			}
			// Stripe's own page. `starting` stays on so the button cannot open a second one while it loads.
			window.location.assign(body.url);
		} catch {
			error = 'The payment page could not be opened. Check your connection and try again.';
			starting = false;
		}
	}
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<div class="invoice-pay">
	<Button
		fullWidth
		loading={starting && !open}
		onclick={() => (asksFirst ? openDialog() : void start(payment.balance_minor, 0))}
	>
		Pay now
	</Button>
	{#if error && !open}<p class="invoice-pay__error" role="alert">{error}</p>{/if}
</div>

{#if asksFirst}
	<Dialog {open} title="Pay invoice" size="small" onClose={() => (open = false)}>
		<div class="invoice-pay__form">
			{#if payment.partial_allowed}
				<MoneyInput
					id="invoice-pay-amount"
					label="Payment amount"
					bind:value={amountMinor}
					disabled={starting}
					invalid={Boolean(amountError)}
					errorMessage={amountError}
				/>
				{#if !amountError}
					<p class="invoice-pay__hint">Up to {format(payment.balance_minor)} is still owed.</p>
				{/if}
			{:else}
				<div class="invoice-pay__row">
					<span>Balance due</span>
					<strong>{format(payment.balance_minor)}</strong>
				</div>
			{/if}

			{#if payment.tips_enabled}
				<fieldset class="invoice-pay__tips" disabled={starting}>
					<legend>Add a tip</legend>
					<div class="invoice-pay__tip-options">
						<label class="invoice-pay__tip" class:invoice-pay__tip--active={tipChoice === 'none'}>
							<input type="radio" name="invoice-pay-tip" value="none" bind:group={tipChoice} />
							<span class="invoice-pay__tip-label">No tip</span>
						</label>
						{#each TIP_PERCENTS as percent (percent)}
							<label
								class="invoice-pay__tip"
								class:invoice-pay__tip--active={tipChoice === `${percent}`}
							>
								<input
									type="radio"
									name="invoice-pay-tip"
									value={`${percent}`}
									bind:group={tipChoice}
								/>
								<span class="invoice-pay__tip-label">{percent}%</span>
								<span class="invoice-pay__tip-amount">{format(percentTip(percent))}</span>
							</label>
						{/each}
						<label class="invoice-pay__tip" class:invoice-pay__tip--active={tipChoice === 'custom'}>
							<input type="radio" name="invoice-pay-tip" value="custom" bind:group={tipChoice} />
							<span class="invoice-pay__tip-label">Custom</span>
						</label>
					</div>
					{#if tipChoice === 'custom'}
						<MoneyInput
							id="invoice-pay-tip-custom"
							label="Tip amount"
							bind:value={customTipMinor}
						/>
					{/if}
				</fieldset>
			{/if}

			{#if payment.tips_enabled}
				<dl class="invoice-pay__summary">
					<div class="invoice-pay__row">
						<dt>Invoice payment</dt>
						<dd>{format(payingMinor)}</dd>
					</div>
					<div class="invoice-pay__row">
						<dt>Tip</dt>
						<dd>{format(tipMinor)}</dd>
					</div>
					<div class="invoice-pay__row invoice-pay__row--total">
						<dt>Total</dt>
						<dd>{format(payingMinor + tipMinor)}</dd>
					</div>
				</dl>
			{/if}

			{#if error}<p class="invoice-pay__error" role="alert">{error}</p>{/if}

			<footer class="invoice-pay__footer">
				<Button variant="secondary" onclick={() => (open = false)} disabled={starting}
					>Cancel</Button
				>
				<Button onclick={confirm} loading={starting}>
					Pay {format(payingMinor + tipMinor)}
				</Button>
			</footer>
			<p class="invoice-pay__secure">
				<span aria-hidden="true">{@html lockIcon}</span>
				You will finish paying on Stripe's secure payment page.
			</p>
		</div>
	</Dialog>
{/if}

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.invoice-pay {
		margin-top: var(--space-base);
		text-align: left;
	}

	.invoice-pay__error {
		margin: var(--space-small) 0 0;
		color: var(--color-critical);
		font-size: var(--typography--fontSize-small);
	}

	// The dialog is portalled out of this component, so its parts are styled globally under their own block.
	:global(.invoice-pay__form) {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);
	}

	:global(.invoice-pay__hint) {
		margin: calc(var(--space-small) * -1) 0 0;
		font-size: var(--typography--fontSize-small);
		color: var(--color-text--secondary);
	}

	:global(.invoice-pay__row) {
		display: flex;
		justify-content: space-between;
		gap: var(--space-base);
		margin: 0;
		color: var(--color-text--secondary);

		:global(strong),
		:global(dd) {
			margin: 0;
			font-weight: 600;
			color: var(--color-heading);
			font-variant-numeric: tabular-nums;
		}
	}

	:global(.invoice-pay__row--total) {
		padding-top: var(--space-small);
		border-top: var(--border-base) solid var(--color-border);

		:global(dt) {
			font-weight: 600;
			color: var(--color-heading);
		}

		:global(dd) {
			font-weight: 700;
		}
	}

	:global(.invoice-pay__tips) {
		display: flex;
		flex-direction: column;
		gap: var(--space-slim);
		margin: 0;
		padding: 0;
		border: 0;

		:global(legend) {
			margin-bottom: var(--space-small);
			padding: 0;
			font-weight: 600;
			color: var(--color-heading);
		}
	}

	:global(.invoice-pay__tip-options) {
		display: grid;
		grid-template-columns: repeat(5, 1fr);
		gap: var(--space-small);
	}

	:global(.invoice-pay__tip) {
		position: relative;
		display: flex;
		flex-direction: column;
		align-items: center;
		justify-content: center;
		gap: var(--space-smallest);
		min-height: 52px;
		padding: var(--space-small) var(--space-smaller);
		border: var(--border-base) solid var(--color-border--interactive);
		border-radius: var(--radius-base);
		background: var(--color-surface);
		cursor: pointer;
		transition: all var(--timing-base) ease-out;

		&:hover {
			background: var(--color-surface--hover);
		}

		&:has(:global(input:focus-visible)) {
			box-shadow: var(--shadow-focus);
		}

		:global(input) {
			position: absolute;
			opacity: 0;
			pointer-events: none;
		}
	}

	:global(.invoice-pay__tip--active) {
		border-color: var(--color-interactive);
		background: var(--color-success--surface);
		box-shadow: inset 0 0 0 1px var(--color-interactive);
	}

	:global(.invoice-pay__tip-label) {
		font-weight: 600;
		color: var(--color-heading);
		font-size: var(--typography--fontSize-base);
	}

	:global(.invoice-pay__tip-amount) {
		font-size: var(--typography--fontSize-smaller);
		color: var(--color-text--secondary);
		font-variant-numeric: tabular-nums;
	}

	:global(.invoice-pay__summary) {
		display: flex;
		flex-direction: column;
		gap: var(--space-small);
		margin: 0;
	}

	:global(.invoice-pay__footer) {
		display: flex;
		justify-content: flex-end;
		gap: var(--space-small);
	}

	:global(.invoice-pay__secure) {
		display: flex;
		align-items: center;
		justify-content: center;
		gap: var(--space-smaller);
		margin: 0;
		font-size: var(--typography--fontSize-smaller);
		color: var(--color-text--secondary);

		:global(svg) {
			width: 14px;
			height: 14px;
		}
	}

	@media (max-width: 420px) {
		:global(.invoice-pay__tip-options) {
			grid-template-columns: repeat(3, 1fr);
		}
	}
</style>
