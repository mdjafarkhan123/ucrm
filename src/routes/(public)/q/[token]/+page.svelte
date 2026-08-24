<script lang="ts">
	import { page } from '$app/state';
	import { invalidateAll } from '$app/navigation';
	import CustomerQuoteDocument from '$lib/components/quotes/CustomerQuoteDocument.svelte';
	import type { SignatureValue } from '$lib/quotes/signature';

	// The customer's page. Everything it draws came from the token in the URL, resolved on the server,
	// and it draws it with the same component staff see in Preview as client - there is no second,
	// friendlier version of this document anywhere.
	let { data } = $props();

	const token = $derived(page.params.token ?? '');

	function fileHref(attachmentId: string, size?: 'thumb') {
		return `/q/${token}/files/${attachmentId}${size ? `?size=${size}` : ''}`;
	}

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
	async function decide(
		outcome: 'approved' | 'changes_requested',
		note: string,
		signature: SignatureValue | null
	) {
		const response = await fetch(
			`/api/public/quotes/${token}/${outcome === 'approved' ? 'approve' : 'changes'}`,
			{
				method: 'POST',
				headers: { 'content-type': 'application/json' },
				body: JSON.stringify({
					...(note ? { note } : {}),
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
			}
		);

		if (!response.ok) {
			const body = await response.json().catch(() => ({}));
			throw new Error(body.error ?? 'That could not be sent. Please try again.');
		}

		await invalidateAll();
	}
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

{#if data.document}
	<CustomerQuoteDocument doc={data.document} decisions="live" onDecide={decide} {fileHref} />
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
