<script lang="ts">
	import { page } from '$app/state';
	import { invalidateAll } from '$app/navigation';
	import CustomerQuoteDocument from '$lib/components/quotes/CustomerQuoteDocument.svelte';
	import CustomerQuoteDepositPayment from '$lib/components/quotes/CustomerQuoteDepositPayment.svelte';
	import OtherWaysToPay from '$lib/components/payments/OtherWaysToPay.svelte';
	import { hasAnyPayByAppMethod } from '$lib/payments/pay-by-app';
	import type { SignatureValue } from '$lib/signatures/signature';
	import type { CustomerDeclineReason } from '$lib/quotes/customer-decline';
	import circleCheckIcon from '@tabler/icons/outline/circle-check.svg?raw';
	import infoIcon from '@tabler/icons/outline/info-circle.svg?raw';
	import testPipeIcon from '@tabler/icons/outline/test-pipe.svg?raw';

	// The customer's page. Everything it draws came from the token in the URL, resolved on the server,
	// and it draws it with the same component staff see in Preview as client - there is no second,
	// friendlier version of this document anywhere.
	let { data } = $props();

	const token = $derived(page.params.token ?? '');

	function fileHref(attachmentId: string, size?: 'thumb') {
		return `/q/${token}/files/${attachmentId}${size ? `?size=${size}` : ''}`;
	}

	const logoHref = $derived(data.document?.business.has_logo ? `/q/${token}/logo` : null);

	// The view is recorded from here, once, after the document has actually been drawn on this screen.
	// That is what makes "the client opened your quote" mean what the office thinks it means: a mail
	// scanner fetching the URL never runs this. It is fire and forget — the customer's quote is already
	// in front of them and a failed ping is not their problem.
	let viewedToken = '';

	$effect(() => {
		if (!data.document || viewedToken === token) return;
		// Once per link per visit. Answering the quote reloads this page, and that is the same person
		// still looking at the same document, not a second opening of it.
		viewedToken = token;
		void fetch(`/api/public/quotes/${token}/view`, {
			method: 'POST',
			headers: { 'content-type': 'application/json' },
			body: '{}'
		}).catch(() => {});
	});

	// Sending the answer. On success the page is reloaded so the status chip, the dates and the buttons
	// all come back from the server telling the same story — the document is the truth, not this tab.
	const DECISION_PATHS = {
		approved: 'approve',
		changes_requested: 'changes',
		declined: 'decline'
	} as const;

	async function decide(
		outcome: keyof typeof DECISION_PATHS,
		note: string,
		signature: SignatureValue | null,
		reason: CustomerDeclineReason | null
	) {
		const response = await fetch(`/api/public/quotes/${token}/${DECISION_PATHS[outcome]}`, {
			method: 'POST',
			headers: { 'content-type': 'application/json' },
			body: JSON.stringify({
				...(note ? { note } : {}),
				// Only ever sent with a decline, and only when they picked one.
				...(reason ? { reason } : {}),
				// Only ever sent with an approval, and only when they actually signed. A drawing goes
				// as a PNG data URL; a typed name goes as the name and nothing else.
				...(signature
					? {
							signature: {
								name: signature.name.trim(),
								method: signature.method,
								...(signature.image ? { image: signature.image } : {})
							}
						}
					: {})
			})
		});

		if (!response.ok) {
			const body = await response.json().catch(() => ({}));
			throw new Error(body.error ?? 'That could not be sent. Please try again.');
		}

		await invalidateAll();
	}

	// Online deposit payment. Stripe sends the customer back here with `?payment=success` as soon as they
	// finish, which can be a moment before Stripe's confirmation reaches our server. Until it does, the page
	// says it is confirming and quietly reloads its data; it never claims the deposit arrived before the
	// server has it. `doc.deposit.satisfied` is the one source of truth for whether it has.
	const payment = $derived(data.payment);
	const deposit = $derived(data.document?.deposit ?? null);
	const canPay = $derived(
		Boolean(
			payment &&
			deposit &&
			!deposit.satisfied &&
			(payment.available || hasAnyPayByAppMethod(payment.pay_by_app))
		)
	);
	const returnedFromStripe = $derived(page.url.searchParams.get('payment') === 'success');

	// About a minute of checking. Cards confirm in seconds; after that the page stops asking and says so.
	const POLL_MS = 2500;
	let pollsLeft = $state(24);

	type PaymentNews = 'thanks' | 'confirming' | 'slow' | null;
	const news = $derived.by((): PaymentNews => {
		if (!payment || !returnedFromStripe) return null;
		if (deposit?.satisfied) return 'thanks';
		return pollsLeft > 0 ? 'confirming' : 'slow';
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
			? `Quote #${data.document.quote.quote_number}`
			: data.expired
				? 'Link expired'
				: 'Quote not available'}</title
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

{#snippet depositPayButton()}
	{#if payment}
		{#if payment.available}
			<CustomerQuoteDepositPayment {token} />
		{/if}
		<OtherWaysToPay
			methods={payment.pay_by_app}
			amountMinor={payment.deposit_required_minor}
			currencyCode={data.document?.document.currency_code ?? 'USD'}
			memo={data.document ? `Deposit for quote #${data.document.quote.quote_number}` : ''}
			divider={payment.available}
		/>
	{/if}
{/snippet}

{#if data.document}
	<CustomerQuoteDocument
		doc={data.document}
		decisions="live"
		onDecide={decide}
		{fileHref}
		{logoHref}
		depositPayment={canPay ? depositPayButton : undefined}
	>
		{#snippet notice()}
			{#if payment && (news || payment.test_mode)}
				<div class="pay-banners">
					{#if news === 'thanks'}
						{@render banner(
							'success',
							circleCheckIcon,
							'Deposit received — thank you',
							`Your deposit payment has been confirmed and ${data.document?.business.name ?? 'the business'} has been told.`
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
	</CustomerQuoteDocument>
{:else if data.expired}
	<main class="quote-unavailable">
		<h1>This link has expired</h1>
		<p>
			Quote links only stay open for a while. Ask the company for a fresh one and they can send you
			another straight away.
		</p>
	</main>
{:else}
	<main class="quote-unavailable">
		<h1>This quote is not available</h1>
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

	.quote-unavailable {
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

	h1 {
		margin: 0;
		font-size: var(--typography--fontSize-largest);
		line-height: var(--typography--lineHeight-tightest);
		font-weight: 700;
		color: var(--color-heading);
	}

	p {
		margin: 0;
		max-width: 44ch;
		color: var(--color-text--secondary);
	}
</style>
