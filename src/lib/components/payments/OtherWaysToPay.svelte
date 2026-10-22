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
	import zelleIcon from '@tabler/icons/outline/send.svg?raw';
	import eTransferIcon from '@tabler/icons/outline/mail.svg?raw';
	import externalLinkIcon from '@tabler/icons/outline/external-link.svg?raw';
	import infoIcon from '@tabler/icons/outline/info-circle.svg?raw';
	import IconTile from '$lib/components/ui/IconTile.svelte';
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
		businessName = null,
		kind = 'invoice'
	}: {
		methods: PayByAppMethods | null;
		amountMinor: number;
		currencyCode: string;
		/** A short note like "Invoice #123" pre-filled into Venmo's memo field, if it takes one. */
		memo?: string;
		/** Named in the foot line: who marks the invoice paid once the money arrives. */
		businessName?: string | null;
		/** What is being paid, for the hint and foot line, and the colour of the box's edge. */
		kind?: 'invoice' | 'deposit';
	} = $props();

	const money = $derived(
		new Intl.NumberFormat('en-US', { style: 'currency', currency: currencyCode })
	);
	const amountText = $derived(money.format(amountMinor / 100));
	const hint = $derived(
		kind === 'deposit' ? `Send the ${amountText} deposit` : `Send ${amountText} with one of these`
	);
	const footText = $derived(
		`${businessName?.trim() || 'The business'} marks this ${kind === 'deposit' ? 'deposit' : 'invoice'} paid once the money arrives.`
	);

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
	<div class="other-ways-to-pay other-ways-to-pay--{kind}">
		<div class="other-ways-to-pay__head">
			<p class="other-ways-to-pay__title">Other ways to pay</p>
			<p class="other-ways-to-pay__hint">{hint}</p>
		</div>
		<ul class="other-ways-to-pay__list">
			{#if methods.venmo_username}
				<li class="other-ways-to-pay__item">
					<IconTile icon={walletIcon} tone="invoice" size={32} />
					<span class="other-ways-to-pay__info">
						<span class="other-ways-to-pay__label">Venmo</span>
						<span class="other-ways-to-pay__detail">@{methods.venmo_username}</span>
					</span>
					<Button
						size="small"
						variant="secondary"
						href={venmoPayLink(methods.venmo_username, amountMinor, memo)}
						target="_blank"
					>
						Pay <span aria-hidden="true">{@html externalLinkIcon}</span>
					</Button>
				</li>
			{/if}
			{#if methods.cash_app_cashtag}
				<li class="other-ways-to-pay__item">
					<IconTile icon={cashAppIcon} tone="invoice" size={32} />
					<span class="other-ways-to-pay__info">
						<span class="other-ways-to-pay__label">Cash App</span>
						<span class="other-ways-to-pay__detail">${methods.cash_app_cashtag}</span>
					</span>
					<Button
						size="small"
						variant="secondary"
						href={cashAppPayLink(methods.cash_app_cashtag, amountMinor)}
						target="_blank"
					>
						Pay <span aria-hidden="true">{@html externalLinkIcon}</span>
					</Button>
				</li>
			{/if}
			{#if methods.paypal_me_username}
				<li class="other-ways-to-pay__item">
					<IconTile icon={paypalIcon} tone="invoice" size={32} />
					<span class="other-ways-to-pay__info">
						<span class="other-ways-to-pay__label">PayPal</span>
						<span class="other-ways-to-pay__detail">paypal.me/{methods.paypal_me_username}</span>
					</span>
					<Button
						size="small"
						variant="secondary"
						href={paypalMeLink(methods.paypal_me_username, amountMinor, currencyCode)}
						target="_blank"
					>
						Pay <span aria-hidden="true">{@html externalLinkIcon}</span>
					</Button>
				</li>
			{/if}
			{#if methods.zelle_contact}
				<li class="other-ways-to-pay__item">
					<IconTile icon={zelleIcon} tone="invoice" size={32} />
					<span class="other-ways-to-pay__info">
						<span class="other-ways-to-pay__label">Zelle</span>
						<span class="other-ways-to-pay__detail">{methods.zelle_contact}</span>
					</span>
					<Button
						size="small"
						variant="secondary"
						class={copiedKey === 'zelle' ? 'other-ways-to-pay__copied' : ''}
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
					<IconTile icon={eTransferIcon} tone="invoice" size={32} />
					<span class="other-ways-to-pay__info">
						<span class="other-ways-to-pay__label">Interac e-Transfer</span>
						<span class="other-ways-to-pay__detail">{methods.e_transfer_email}</span>
					</span>
					<Button
						size="small"
						variant="secondary"
						class={copiedKey === 'e_transfer' ? 'other-ways-to-pay__copied' : ''}
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
					<IconTile icon={bankIcon} tone="invoice" size={32} />
					<span class="other-ways-to-pay__info">
						<span class="other-ways-to-pay__label">Bank transfer</span>
					</span>
					<Button
						size="small"
						variant="secondary"
						class={copiedKey === 'bank' ? 'other-ways-to-pay__copied' : ''}
						onclick={() => copy('bank', methods.bank_transfer_instructions!)}
					>
						{#if copiedKey === 'bank'}
							<span aria-hidden="true">{@html checkIcon}</span> Copied
						{:else}
							<span aria-hidden="true">{@html copyIcon}</span> Copy
						{/if}
					</Button>
					<span class="other-ways-to-pay__instructions">{methods.bank_transfer_instructions}</span>
				</li>
			{/if}
		</ul>
		<p class="other-ways-to-pay__foot">
			<span aria-hidden="true">{@html infoIcon}</span>
			{footText}
		</p>
	</div>
{/if}

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	// A white card on the coloured panel it sits in (the invoice's blue Balance due panel, a quote's deposit).
	.other-ways-to-pay {
		--other-ways-to-pay-edge: var(--color-invoice--surface-edge);

		display: flex;
		flex-direction: column;
		margin-top: var(--space-base);
		padding: var(--space-base) var(--space-base) var(--space-slim);
		border: var(--border-base) solid var(--other-ways-to-pay-edge);
		border-radius: var(--radius-base);
		background: var(--color-surface);
		text-align: left;
	}

	.other-ways-to-pay--deposit {
		--other-ways-to-pay-edge: var(--color-quote--surface-edge);
	}

	.other-ways-to-pay__head {
		display: flex;
		flex-direction: column;
		gap: 2px;
		padding-bottom: var(--space-smaller);
	}

	.other-ways-to-pay__title {
		margin: 0;
		font-size: var(--typography--fontSize-base);
		font-weight: 600;
		color: var(--color-heading);
	}

	.other-ways-to-pay__hint {
		margin: 0;
		font-size: var(--typography--fontSize-small);
		color: var(--color-text--secondary);
	}

	.other-ways-to-pay__list {
		display: flex;
		flex-direction: column;
		margin: 0;
		padding: 0;
		list-style: none;
	}

	.other-ways-to-pay__item {
		display: flex;
		align-items: center;
		gap: var(--space-small);
		padding: var(--space-small) 0;
		border-top: var(--border-base) solid var(--color-border);
	}

	// Bank transfer: name and Copy on one line, the instructions under them in a box.
	.other-ways-to-pay__item--block {
		flex-wrap: wrap;
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
		font-size: var(--typography--fontSize-small);
	}

	.other-ways-to-pay__detail {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		overflow-wrap: anywhere;
	}

	.other-ways-to-pay__instructions {
		flex: 1 0 100%;
		padding: var(--space-slim) var(--space-small);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-small);
		background: var(--color-surface--background);
		color: var(--color-text);
		font-size: var(--typography--fontSize-small);
		line-height: 1.5;
		white-space: pre-wrap;
		overflow-wrap: anywhere;
	}

	.other-ways-to-pay__foot {
		display: flex;
		align-items: center;
		gap: var(--space-smaller);
		margin: 0;
		padding-top: var(--space-small);
		border-top: var(--border-base) solid var(--color-border);
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-smaller);
		font-weight: 500;

		:global(svg) {
			flex: 0 0 auto;
			width: 14px;
			height: 14px;
			color: var(--color-informative);
		}
	}

	// Copied: the button turns green for two seconds.
	:global(.button.other-ways-to-pay__copied) {
		border-color: var(--color-success);
		background: var(--color-success--surface);
		color: var(--color-success--onSurface);
	}
</style>
