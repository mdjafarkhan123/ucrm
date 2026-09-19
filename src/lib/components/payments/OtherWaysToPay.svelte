<script lang="ts">
	import Button from '$lib/components/ui/Button.svelte';
	import {
		hasAnyPayByAppMethod,
		venmoPayLink,
		cashAppPayLink,
		paypalMeLink,
		type PayByAppMethods
	} from '$lib/payments/pay-by-app';
	import walletIcon from '@tabler/icons/outline/wallet.svg?raw';
	import cashAppIcon from '@tabler/icons/outline/brand-cashapp.svg?raw';
	import paypalIcon from '@tabler/icons/outline/brand-paypal.svg?raw';
	import bankIcon from '@tabler/icons/outline/building-bank.svg?raw';
	import copyIcon from '@tabler/icons/outline/copy.svg?raw';
	import checkIcon from '@tabler/icons/outline/check.svg?raw';

	// The customer's "Other ways to pay" box (docs/online-payments-behavior-contract.md §6), shown beside
	// the Stripe Pay button -- or alone when the contractor has no Stripe connected at all. Venmo, Cash App
	// and PayPal.me are tappable links that open the app with the amount pre-filled; Zelle, Interac
	// e-Transfer and a bank transfer have no such link (they move money bank-to-bank), so those stay
	// copy-to-clipboard. None of this is processed by UCRM -- the contractor records it by hand once paid.
	let {
		methods,
		amountMinor,
		currencyCode,
		memo = '',
		divider = true
	}: {
		methods: PayByAppMethods | null;
		amountMinor: number;
		currencyCode: string;
		/** A short note like "Invoice #123" pre-filled into Venmo's memo field, if it takes one. */
		memo?: string;
		/** A rule sits above this box, for when a Stripe Pay button is rendered right before it. Pass
		 *  `false` when this box is the only thing here, so it doesn't divide itself from nothing. */
		divider?: boolean;
	} = $props();

	let copiedKey = $state<string | null>(null);

	async function copy(key: string, value: string) {
		try {
			await navigator.clipboard.writeText(value);
			copiedKey = key;
			setTimeout(() => {
				if (copiedKey === key) copiedKey = null;
			}, 2000);
		} catch {
			// Clipboard access can be blocked (permissions, insecure context); the value is already on
			// screen for the customer to select and copy by hand.
		}
	}
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
{#if methods && hasAnyPayByAppMethod(methods)}
	<div class="other-ways-to-pay" class:other-ways-to-pay--divided={divider}>
		<p class="other-ways-to-pay__title">Other ways to pay</p>
		<ul class="other-ways-to-pay__list">
			{#if methods.venmo_username}
				<li class="other-ways-to-pay__item">
					<span class="other-ways-to-pay__icon" aria-hidden="true">{@html walletIcon}</span>
					<span class="other-ways-to-pay__info">
						<span class="other-ways-to-pay__label">Venmo</span>
						<span class="other-ways-to-pay__detail">@{methods.venmo_username}</span>
					</span>
					<Button
						size="small"
						variant="secondary"
						href={venmoPayLink(methods.venmo_username, amountMinor, memo)}
						target="_blank">Pay</Button
					>
				</li>
			{/if}

			{#if methods.cash_app_cashtag}
				<li class="other-ways-to-pay__item">
					<span class="other-ways-to-pay__icon" aria-hidden="true">{@html cashAppIcon}</span>
					<span class="other-ways-to-pay__info">
						<span class="other-ways-to-pay__label">Cash App</span>
						<span class="other-ways-to-pay__detail">${methods.cash_app_cashtag}</span>
					</span>
					<Button
						size="small"
						variant="secondary"
						href={cashAppPayLink(methods.cash_app_cashtag, amountMinor)}
						target="_blank">Pay</Button
					>
				</li>
			{/if}

			{#if methods.paypal_me_username}
				<li class="other-ways-to-pay__item">
					<span class="other-ways-to-pay__icon" aria-hidden="true">{@html paypalIcon}</span>
					<span class="other-ways-to-pay__info">
						<span class="other-ways-to-pay__label">PayPal</span>
						<span class="other-ways-to-pay__detail">paypal.me/{methods.paypal_me_username}</span>
					</span>
					<Button
						size="small"
						variant="secondary"
						href={paypalMeLink(methods.paypal_me_username, amountMinor, currencyCode)}
						target="_blank">Pay</Button
					>
				</li>
			{/if}

			{#if methods.zelle_contact}
				<li class="other-ways-to-pay__item">
					<span class="other-ways-to-pay__icon" aria-hidden="true">{@html bankIcon}</span>
					<span class="other-ways-to-pay__info">
						<span class="other-ways-to-pay__label">Zelle</span>
						<span class="other-ways-to-pay__detail">{methods.zelle_contact}</span>
					</span>
					<Button
						size="small"
						variant="secondary"
						onclick={() => copy('zelle', methods.zelle_contact!)}
					>
						{#if copiedKey === 'zelle'}
							<span aria-hidden="true">{@html checkIcon}</span> Copied
						{:else}
							<span aria-hidden="true">{@html copyIcon}</span> Copy
						{/if}
					</Button>
				</li>
			{/if}

			{#if methods.e_transfer_email}
				<li class="other-ways-to-pay__item">
					<span class="other-ways-to-pay__icon" aria-hidden="true">{@html bankIcon}</span>
					<span class="other-ways-to-pay__info">
						<span class="other-ways-to-pay__label">Interac e-Transfer</span>
						<span class="other-ways-to-pay__detail">{methods.e_transfer_email}</span>
					</span>
					<Button
						size="small"
						variant="secondary"
						onclick={() => copy('e_transfer', methods.e_transfer_email!)}
					>
						{#if copiedKey === 'e_transfer'}
							<span aria-hidden="true">{@html checkIcon}</span> Copied
						{:else}
							<span aria-hidden="true">{@html copyIcon}</span> Copy
						{/if}
					</Button>
				</li>
			{/if}

			{#if methods.bank_transfer_instructions}
				<li class="other-ways-to-pay__item other-ways-to-pay__item--block">
					<span class="other-ways-to-pay__icon" aria-hidden="true">{@html bankIcon}</span>
					<span class="other-ways-to-pay__info">
						<span class="other-ways-to-pay__label">Bank transfer</span>
						<span class="other-ways-to-pay__instructions">{methods.bank_transfer_instructions}</span
						>
					</span>
					<Button
						size="small"
						variant="secondary"
						onclick={() => copy('bank', methods.bank_transfer_instructions!)}
					>
						{#if copiedKey === 'bank'}
							<span aria-hidden="true">{@html checkIcon}</span> Copied
						{:else}
							<span aria-hidden="true">{@html copyIcon}</span> Copy
						{/if}
					</Button>
				</li>
			{/if}
		</ul>
	</div>
{/if}

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.other-ways-to-pay {
		display: flex;
		flex-direction: column;
		gap: var(--space-small);
		margin-top: var(--space-base);
		text-align: left;
	}

	.other-ways-to-pay--divided {
		padding-top: var(--space-base);
		border-top: var(--border-base) solid var(--color-border);
	}

	.other-ways-to-pay__title {
		margin: 0;
		font-size: var(--typography--fontSize-small);
		font-weight: 600;
		color: var(--color-text--secondary);
	}

	.other-ways-to-pay__list {
		display: flex;
		flex-direction: column;
		gap: var(--space-small);
		margin: 0;
		padding: 0;
		list-style: none;
	}

	.other-ways-to-pay__item {
		display: flex;
		align-items: center;
		gap: var(--space-small);
	}

	.other-ways-to-pay__item--block {
		align-items: flex-start;
	}

	.other-ways-to-pay__icon {
		display: grid;
		flex: 0 0 auto;
		place-items: center;
		width: var(--space-largest);
		height: var(--space-largest);
		border-radius: var(--radius-base);
		background: var(--color-surface--background);
		color: var(--color-icon);

		:global(svg) {
			width: 20px;
			height: 20px;
		}
	}

	.other-ways-to-pay__info {
		display: flex;
		flex-direction: column;
		flex: 1 1 auto;
		min-width: 0;
		gap: 2px;
	}

	.other-ways-to-pay__label {
		font-weight: 600;
		color: var(--color-heading);
		font-size: var(--typography--fontSize-base);
	}

	.other-ways-to-pay__detail {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		overflow-wrap: anywhere;
	}

	.other-ways-to-pay__instructions {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		white-space: pre-wrap;
		overflow-wrap: anywhere;
	}
</style>
