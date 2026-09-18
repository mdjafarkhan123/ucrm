<script lang="ts">
	import Button from '$lib/components/ui/Button.svelte';
	import lockIcon from '@tabler/icons/outline/lock.svg?raw';

	// The customer's Pay deposit button (docs/online-payments-behavior-contract.md §4). Unlike an invoice
	// payment, there is nothing to ask first: the deposit is one fixed amount the customer already agreed to
	// when they signed, so the button goes straight to Stripe. Nothing is marked paid from here — Stripe
	// confirms the payment to the server, and the page shows it when it has. The amount itself is already
	// drawn beside this button by CustomerQuoteDocument, so this component only needs the token.
	let { token }: { token: string } = $props();

	let starting = $state(false);
	let error = $state('');

	async function start() {
		error = '';
		starting = true;
		try {
			const response = await fetch(`/api/public/quotes/${token}/checkout`, {
				method: 'POST',
				headers: { 'content-type': 'application/json' },
				body: '{}'
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
<div class="deposit-pay">
	<Button fullWidth loading={starting} onclick={start}>Pay deposit</Button>
	{#if error}<p class="deposit-pay__error" role="alert">{error}</p>{/if}
	<p class="deposit-pay__secure">
		<span aria-hidden="true">{@html lockIcon}</span>
		You will finish paying on Stripe's secure payment page.
	</p>
</div>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.deposit-pay {
		display: flex;
		flex-direction: column;
		gap: var(--space-small);
		margin-top: var(--space-base);
	}

	.deposit-pay__error {
		margin: 0;
		color: var(--color-critical);
		font-size: var(--typography--fontSize-small);
	}

	.deposit-pay__secure {
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
</style>
