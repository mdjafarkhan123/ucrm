<script lang="ts">
	import { page } from '$app/state';
	import ReviewFeedbackJourney from '$lib/components/reviews/ReviewFeedbackJourney.svelte';

	// The customer's review feedback page. Everything on it came from the token in the URL, resolved on the
	// server. Each step the customer takes is recorded by the public review API; none of it blocks them.
	let { data } = $props();

	const token = $derived(page.params.token ?? '');

	// Recorded once the page is on this screen, so "opened" means a person saw it: a mail scanner or a
	// message link preview fetching the URL never runs this. Fire and forget.
	let openedToken = '';
	$effect(() => {
		if (openedToken === token) return;
		openedToken = token;
		void fetch(`/api/public/reviews/${token}/open`, {
			method: 'POST',
			headers: { 'content-type': 'application/json' },
			body: '{}'
		}).catch(() => {});
	});

	// keepalive lets the record finish after the browser has already left for Google.
	function recordGoogle(rating: number | null) {
		void fetch(`/api/public/reviews/${token}/google`, {
			method: 'POST',
			headers: { 'content-type': 'application/json' },
			body: JSON.stringify({ rating }),
			keepalive: true
		}).catch(() => {});
	}

	async function submitFeedback(payload: {
		rating: number | null;
		answers: Record<string, unknown>;
	}): Promise<{ ok: true } | { ok: false; error: string }> {
		try {
			const response = await fetch(`/api/public/reviews/${token}/feedback`, {
				method: 'POST',
				headers: { 'content-type': 'application/json' },
				body: JSON.stringify(payload)
			});
			if (response.ok) return { ok: true };
			const result = (await response.json().catch(() => ({}))) as { error?: string };
			if (response.status === 429) {
				return { ok: false, error: 'Too many tries. Please wait a few minutes and try again.' };
			}
			return {
				ok: false,
				error: result.error ?? 'We could not send your feedback. Please try again.'
			};
		} catch {
			return {
				ok: false,
				error: 'We could not send your feedback. Check your connection and try again.'
			};
		}
	}
</script>

<svelte:head>
	<title>{`How did we do? · ${data.model.business.name}`}</title>
	<meta name="robots" content="noindex, nofollow" />
	<meta name="referrer" content="no-referrer" />
</svelte:head>

<main class="review-page">
	<ReviewFeedbackJourney model={data.model} onGoogle={recordGoogle} onSubmit={submitFeedback} />
</main>

<style lang="scss">
	.review-page {
		display: flex;
		align-items: center;
		justify-content: center;
		min-height: 100vh;
		padding: var(--space-extravagant) var(--space-large);
		background: var(--color-surface--background);
	}

	// Below the card's own mobile breakpoint the page stops being a "page with a card on it" and becomes
	// the sheet itself — no visible seam between the two.
	@media (max-width: 639px) {
		.review-page {
			padding: 0;
			background: var(--color-surface);
		}
	}
</style>
