<script lang="ts">
	import { page } from '$app/state';
	import { invalidateAll } from '$app/navigation';
	import CustomerInvoiceDocument from '$lib/components/invoices/CustomerInvoiceDocument.svelte';
	import CustomerInvoicePayment from '$lib/components/invoices/CustomerInvoicePayment.svelte';
	import circleCheckIcon from '@tabler/icons/outline/circle-check.svg?raw';
	import clockIcon from '@tabler/icons/outline/clock.svg?raw';
	import infoIcon from '@tabler/icons/outline/info-circle.svg?raw';
	import testPipeIcon from '@tabler/icons/outline/test-pipe.svg?raw';

	// The customer's page. Everything it draws came from the token in the URL, resolved on the server, and it
	// draws it with the same component staff see in Preview as client — there is no second, friendlier
	// version of this document anywhere.
	let { data } = $props();

	const token = $derived(page.params.token ?? '');

	// The view is recorded from here, once, after the document has actually been drawn on this screen. That is
	// what makes "the client opened your invoice" mean what the office thinks it means: a mail scanner fetching
	// the URL never runs this. It is fire and forget — the customer's invoice is already in front of them and a
	// failed ping is not their problem.
	let viewedToken = '';

	$effect(() => {
		if (!data.document || viewedToken === token) return;
		viewedToken = token;
		void fetch(`/api/public/invoices/${token}/view`, {
			method: 'POST',
			headers: { 'content-type': 'application/json' },
			body: '{}'
		}).catch(() => {});
	});

	// Online payment. Stripe sends the customer back here with `?payment=success` as soon as they finish, which
	// can be a moment before Stripe's confirmation reaches our server. Until it does, the page says it is
	// confirming and quietly reloads its data; it never claims the money arrived before the server has it.
	const payment = $derived(data.payment);
	const currencyCode = $derived(data.document?.invoice.currency_code ?? 'USD');
	const money = $derived(
		new Intl.NumberFormat('en-US', { style: 'currency', currency: currencyCode })
	);
	const returnedFromStripe = $derived(page.url.searchParams.get('payment') === 'success');
	const canPay = $derived(Boolean(payment?.available && payment.balance_minor > 0));

	// About a minute of checking. Cards confirm in seconds; after that the page stops asking and says so.
	const POLL_MS = 2500;
	let pollsLeft = $state(24);

	type PaymentNews = 'thanks' | 'confirming' | 'slow' | 'processing' | null;
	const news = $derived.by((): PaymentNews => {
		if (!payment) return null;
		if (returnedFromStripe && payment.recent_paid_minor > 0) return 'thanks';
		if (payment.processing_minor > 0) return 'processing';
		if (returnedFromStripe) return pollsLeft > 0 ? 'confirming' : 'slow';
		return null;
	});

	$effect(() => {
		// Read here so each tick schedules the next one; `news` alone stays 'confirming' and would not.
		if (news !== 'confirming' || pollsLeft <= 0) return;
		const timer = setTimeout(() => {
			pollsLeft -= 1;
			void invalidateAll();
		}, POLL_MS);
		return () => clearTimeout(timer);
	});
</script>

<svelte:head>
	<title
		>{data.document
			? `Invoice #${data.document.invoice.invoice_number}`
			: data.expired
				? 'Link expired'
				: 'Invoice not available'}</title
	>
	<meta name="robots" content="noindex, nofollow" />
	<meta name="referrer" content="no-referrer" />
</svelte:head>

<!-- eslint-disable svelte/no-at-html-tags -->
{#snippet banner(
	tone: 'success' | 'notice' | 'warning',
	icon: string,
	title: string,
	detail: string
)}
	<div class="pay-banner pay-banner--{tone}" role="status">
		<span class="pay-banner__icon" aria-hidden="true">{@html icon}</span>
		<div>
			<p class="pay-banner__title">{title}</p>
			<p class="pay-banner__detail">{detail}</p>
		</div>
	</div>
{/snippet}
<!-- eslint-enable svelte/no-at-html-tags -->

{#snippet payButton()}
	{#if payment}
		<CustomerInvoicePayment {payment} {currencyCode} {token} />
	{/if}
{/snippet}

{#if data.document}
	{@const doc = data.document}
	<CustomerInvoiceDocument {doc} payment={canPay ? payButton : undefined}>
		{#snippet notice()}
			{#if payment && (news || payment.test_mode)}
				<div class="pay-banners">
					{#if news === 'thanks'}
						{@render banner(
							'success',
							circleCheckIcon,
							'Payment received — thank you',
							`Your payment has been confirmed and ${doc.business.name ?? 'the business'} has been told.`
						)}
					{:else if news === 'processing'}
						{@render banner(
							'notice',
							clockIcon,
							'Payment processing',
							`A bank payment of ${money.format(payment.processing_minor / 100)} is on its way. Bank payments can take a few working days to clear, and this page will show it once they do. There is no need to pay again.`
						)}
					{:else if news === 'confirming'}
						{@render banner(
							'notice',
							infoIcon,
							'Confirming your payment…',
							'This usually takes a few seconds. Please keep this page open.'
						)}
					{:else if news === 'slow'}
						{@render banner(
							'notice',
							infoIcon,
							'Your payment is still being confirmed',
							'This is taking longer than usual. There is no need to pay again. Refresh this page in a few minutes to see it.'
						)}
					{/if}
					{#if payment.test_mode}
						{@render banner(
							'warning',
							testPipeIcon,
							'Test mode — no real money',
							'This business is still testing online payments. Only Stripe test cards work here.'
						)}
					{/if}
				</div>
			{/if}
		{/snippet}
	</CustomerInvoiceDocument>
{:else if data.expired}
	<main class="invoice-unavailable">
		<h1>This link has expired</h1>
		<p>
			Invoice links only stay open for a while. Ask the company for a fresh one and they can send
			you another straight away.
		</p>
	</main>
{:else}
	<main class="invoice-unavailable">
		<h1>This invoice is not available</h1>
		<p>
			The link may have been replaced by a newer one, or it may have been turned off. Ask the
			company for an up-to-date link and they can send you another.
		</p>
	</main>
{/if}

<style lang="scss">
	.pay-banners {
		display: flex;
		flex-direction: column;
		gap: var(--space-small);
	}

	// Banner per the design skill: tinted surface, solid-colour icon circle, no border.
	.pay-banner {
		--pay-banner-surface: var(--color-informative--surface);
		--pay-banner-text: var(--color-informative--onSurface);
		--pay-banner-solid: var(--color-informative);

		display: flex;
		align-items: center;
		gap: var(--space-small);
		padding: var(--space-slim) var(--space-base);
		border-radius: var(--radius-base);
		background: var(--pay-banner-surface);
		color: var(--pay-banner-text);

		&--success {
			--pay-banner-surface: var(--color-success--surface);
			--pay-banner-text: var(--color-success--onSurface);
			--pay-banner-solid: var(--color-success);
		}

		&--warning {
			--pay-banner-surface: var(--color-warning--surface);
			--pay-banner-text: var(--color-warning--onSurface);
			--pay-banner-solid: var(--color-warning);
		}
	}

	.pay-banner__icon {
		display: grid;
		flex: 0 0 auto;
		place-items: center;
		padding: var(--space-smaller);
		border-radius: var(--radius-circle);
		background: var(--pay-banner-solid);
		color: var(--color-surface);

		:global(svg) {
			display: block;
			width: 20px;
			height: 20px;
		}
	}

	.pay-banner__title {
		margin: 0;
		font-weight: 700;
	}

	.pay-banner__detail {
		margin: 0;
		font-size: var(--typography--fontSize-small);
	}

	.invoice-unavailable {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);
		align-items: center;
		justify-content: center;
		min-height: 100vh;
		padding: var(--space-largest);
		text-align: center;
		background: var(--color-surface--background);
		color: var(--color-text);
	}

	.invoice-unavailable h1 {
		margin: 0;
		font-size: var(--typography--fontSize-largest);
		line-height: var(--typography--lineHeight-tightest);
		font-weight: 700;
		color: var(--color-heading);
	}

	.invoice-unavailable p {
		margin: 0;
		max-width: 44ch;
		color: var(--color-text--secondary);
	}
</style>
