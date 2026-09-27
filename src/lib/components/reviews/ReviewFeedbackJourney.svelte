<script lang="ts">
	import Button from '$lib/components/ui/Button.svelte';
	import FormErrorSummary from '$lib/components/forms/FormErrorSummary.svelte';
	import PublicFormQuestion from '$lib/components/forms/PublicFormQuestion.svelte';
	import { blankAnswer, isAnswerEmpty } from '$lib/forms/answers';
	import { REVIEW_STAR_LABELS, type ReviewFeedbackPageModel } from '$lib/reviews/feedback-page';
	import brandGoogleIcon from '@tabler/icons/outline/brand-google.svg?raw';
	import messageIcon from '@tabler/icons/outline/message-circle.svg?raw';
	import lockIcon from '@tabler/icons/outline/lock.svg?raw';
	import arrowLeftIcon from '@tabler/icons/outline/arrow-left.svg?raw';
	import checkIcon from '@tabler/icons/outline/circle-check.svg?raw';
	import starIcon from '@tabler/icons/filled/star.svg?raw';

	// The customer's review journey (brief: "Rating page and private-feedback form"). Routing off: two equal
	// choices, Google or private. Routing on: stars, where a pick at or above the threshold opens Google
	// straight away and a lower one opens the private form. Then the contractor's own thank-you.
	//
	// The public page records each step; the settings preview passes `preview` and records nothing. In the
	// preview, Google opens in a new tab so the contractor can test their link without leaving their work.
	//
	// Mobile and desktop are deliberately different shapes, not one layout squeezed down: on the real
	// customer page (`preview` false) a narrow viewport drops the floating card for an edge-to-edge sheet
	// with a fixed bottom action bar on the form step, while the settings preview always keeps the floating
	// card so it reads correctly inside its dialog regardless of window width.
	type SubmitResult = { ok: true } | { ok: false; error: string };

	let {
		model,
		preview = false,
		onGoogle,
		onSubmit
	}: {
		model: ReviewFeedbackPageModel;
		preview?: boolean;
		/** Called as the customer leaves for Google; it must not delay them. */
		onGoogle?: (rating: number | null) => void;
		onSubmit?: (payload: {
			rating: number | null;
			answers: Record<string, unknown>;
		}) => Promise<SubmitResult>;
	} = $props();

	type Step = 'choose' | 'form' | 'thanks';

	const form = $derived(model.feedback_form);
	const googleUrl = $derived(model.google_review_url);
	const routed = $derived(model.routing_enabled && googleUrl !== null);
	// Without a Google link there is nothing to choose between, so the private form is the page.
	const firstStep = $derived<Step>(
		model.feedback_submitted ? 'thanks' : googleUrl ? 'choose' : 'form'
	);

	let chosenStep = $state<Step | null>(null);
	const step = $derived(chosenStep ?? firstStep);

	let rating = $state<number | null>(null);
	let hoverRating = $state<number | null>(null);
	let answers = $state<Record<string, unknown>>({});
	let submitting = $state(false);
	let errorMessage = $state('');
	let errorSummary = $state<FormErrorSummary>();

	const greeting = $derived(
		model.customer_first_name ? `Hi ${model.customer_first_name},` : 'Hello,'
	);

	const brandInitials = $derived.by(() => {
		const words = model.business.name.trim().split(/\s+/).filter(Boolean);
		if (words.length === 0) return '—';
		if (words.length === 1) return words[0].slice(0, 2).toUpperCase();
		return (words[0][0] + words[words.length - 1][0]).toUpperCase();
	});

	function answerFor(questionId: string, type: Parameters<typeof blankAnswer>[0]) {
		return questionId in answers ? answers[questionId] : blankAnswer(type);
	}

	function goToGoogle(pickedRating: number | null) {
		if (!googleUrl) return;
		onGoogle?.(pickedRating);
		if (preview) {
			window.open(googleUrl, '_blank', 'noopener');
			return;
		}
		window.location.assign(googleUrl);
	}

	function pickStar(star: number) {
		rating = star;
		if (star >= model.routing_google_min_rating) {
			goToGoogle(star);
			return;
		}
		chosenStep = 'form';
	}

	function backToChoice() {
		chosenStep = 'choose';
		rating = null;
		errorMessage = '';
	}

	async function submit(event: SubmitEvent) {
		event.preventDefault();
		errorMessage = '';
		const missing = form.questions.find(
			(question) =>
				question.required && isAnswerEmpty(question.type, answerFor(question.id, question.type))
		);
		if (missing) {
			errorMessage = `Please answer this question: “${missing.label}”`;
			void errorSummary?.reveal();
			return;
		}

		const payload: Record<string, unknown> = {};
		for (const question of form.questions) {
			const value = answerFor(question.id, question.type);
			if (!isAnswerEmpty(question.type, value)) payload[question.id] = value;
		}

		if (!onSubmit) {
			chosenStep = 'thanks';
			return;
		}
		submitting = true;
		const result = await onSubmit({ rating: routed ? rating : null, answers: payload });
		submitting = false;
		if (result.ok) {
			chosenStep = 'thanks';
			return;
		}
		errorMessage = result.error;
		void errorSummary?.reveal();
	}
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<article class="review-journey" class:review-journey--preview={preview}>
	<div class="review-journey__brandbar"></div>
	<header class="review-journey__head">
		{#if model.business.logo_url}
			<img class="review-journey__logo" src={model.business.logo_url} alt={model.business.name} />
		{:else}
			<div class="review-journey__brand">
				<div class="review-journey__brand-mark" aria-hidden="true">{brandInitials}</div>
				<div class="review-journey__brand-name">{model.business.name}</div>
			</div>
		{/if}
	</header>

	{#if step === 'choose'}
		<section class="review-journey__body">
			<p class="review-journey__eyebrow">{greeting}</p>
			{#if routed}
				<h1 class="review-journey__title">
					How was your experience with {model.business.name}?
				</h1>
				<p class="review-journey__text">Your honest rating helps us know how we're doing.</p>
				<div
					class="review-journey__stars"
					role="group"
					aria-label="Your rating"
					onmouseleave={() => (hoverRating = null)}
				>
					{#each REVIEW_STAR_LABELS as label, index (label)}
						{@const star = index + 1}
						<button
							type="button"
							class="review-journey__star"
							class:review-journey__star--lit={star <= (hoverRating ?? rating ?? 0)}
							aria-label={`${star} ${star === 1 ? 'star' : 'stars'}: ${label}`}
							onmouseenter={() => (hoverRating = star)}
							onfocus={() => (hoverRating = star)}
							onblur={() => (hoverRating = null)}
							onclick={() => pickStar(star)}
						>
							<span aria-hidden="true">{@html starIcon}</span>
						</button>
					{/each}
				</div>
				<p class="review-journey__star-label" aria-live="polite">
					{hoverRating ? REVIEW_STAR_LABELS[hoverRating - 1] : ' '}
				</p>
			{:else}
				<h1 class="review-journey__title">We'd love to hear from you</h1>
				<p class="review-journey__text">
					Thank you for choosing {model.business.name}. Your feedback means a lot to us — share it
					however feels right.
				</p>
				<div class="review-journey__choices">
					<button type="button" class="review-journey__choice" onclick={() => goToGoogle(null)}>
						<span class="review-journey__choice-icon review-journey__choice-icon--google">
							{@html brandGoogleIcon}
						</span>
						<span class="review-journey__choice-text">
							<strong>Leave a Google review</strong>
							<span>Share the love publicly — it takes less than a minute.</span>
						</span>
					</button>
					<button
						type="button"
						class="review-journey__choice"
						onclick={() => (chosenStep = 'form')}
					>
						<span class="review-journey__choice-icon">{@html messageIcon}</span>
						<span class="review-journey__choice-text">
							<strong>Tell us privately</strong>
							<span>Have feedback or a concern? Send it straight to our team.</span>
						</span>
					</button>
				</div>
			{/if}
		</section>
	{:else if step === 'form'}
		<section class="review-journey__body review-journey__body--form">
			{#if googleUrl}
				<button type="button" class="review-journey__back" onclick={backToChoice}>
					<span aria-hidden="true">{@html arrowLeftIcon}</span>
					Go back
				</button>
			{/if}
			<h1 class="review-journey__title">{form.heading}</h1>
			{#if form.intro}<p class="review-journey__text review-journey__text--authored">
					{form.intro}
				</p>{/if}
			<p class="review-journey__private">
				<span aria-hidden="true">{@html lockIcon}</span>
				Only {model.business.name} sees your answers.
			</p>

			<form class="review-journey__form" onsubmit={submit} novalidate>
				<FormErrorSummary bind:this={errorSummary} message={errorMessage} />
				{#each form.questions as question (question.id)}
					<PublicFormQuestion
						{question}
						bind:value={
							() => answerFor(question.id, question.type), (value) => (answers[question.id] = value)
						}
					/>
				{/each}
				<div class="review-journey__submit-bar">
					<Button type="submit" size="large" fullWidth loading={submitting} disabled={submitting}>
						Send feedback
					</Button>
				</div>
			</form>
		</section>
	{:else}
		<section class="review-journey__body review-journey__body--centered">
			<span class="review-journey__done" aria-hidden="true">{@html checkIcon}</span>
			<h1 class="review-journey__title">{form.thank_you_title}</h1>
			<p class="review-journey__text review-journey__text--authored">{form.thank_you_message}</p>
			{#if googleUrl && !routed}
				<div class="review-journey__after">
					<p class="review-journey__text">
						Would you also share this on Google? It helps other customers find us.
					</p>
					<Button variant="secondary" onclick={() => goToGoogle(null)}>
						<span class="review-journey__button-icon" aria-hidden="true"
							>{@html brandGoogleIcon}</span
						>
						Leave a Google review
					</Button>
				</div>
			{/if}
		</section>
	{/if}
</article>

<style lang="scss">
	.review-journey {
		position: relative;
		width: 100%;
		max-width: 560px;
		margin: 0 auto;
		background: var(--color-surface);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-large);
		box-shadow: var(--shadow-high);
		overflow: hidden;
		color: var(--color-text);
		font-family: var(--typography--fontFamily-normal);

		&__brandbar {
			height: 5px;
			background: linear-gradient(90deg, var(--color-job) 0%, var(--color-brand) 100%);
		}

		&__head {
			display: flex;
			align-items: center;
			padding: var(--space-larger) var(--space-larger) var(--space-small);
		}

		&__logo {
			display: block;
			max-width: 200px;
			max-height: 56px;
			object-fit: contain;
		}

		&__brand {
			display: flex;
			align-items: center;
			gap: var(--space-slim);
		}

		&__brand-mark {
			display: grid;
			place-items: center;
			width: 44px;
			height: 44px;
			border-radius: var(--radius-base);
			background: var(--color-surface--reverse);
			color: var(--color-text--reverse);
			font-family: var(--typography--fontFamily-display);
			font-size: var(--typography--fontSize-larger);
			font-weight: 800;
		}

		&__brand-name {
			font-family: var(--typography--fontFamily-display);
			font-size: var(--typography--fontSize-larger);
			font-weight: 700;
			line-height: var(--typography--lineHeight-minuscule);
			color: var(--color-heading);
		}

		&__body {
			display: flex;
			flex-direction: column;
			gap: var(--space-small);
			padding: var(--space-base) var(--space-larger) var(--space-larger);

			&--centered {
				align-items: center;
				padding-top: var(--space-large);
				text-align: center;
			}
		}

		&__eyebrow {
			margin: 0;
			color: var(--color-text--secondary);
			font-weight: 600;
		}

		&__title {
			margin: 0;
			font-family: var(--typography--fontFamily-display);
			font-size: var(--typography--fontSize-jumbo);
			font-weight: 900;
			line-height: var(--typography--lineHeight-minuscule);
			color: var(--color-heading);
		}

		&__text {
			margin: 0;
			color: var(--color-text--secondary);

			// Contractor-written text keeps the line breaks they typed.
			&--authored {
				white-space: pre-wrap;
			}
		}

		&__choices {
			display: grid;
			grid-template-columns: 1fr 1fr;
			gap: var(--space-base);
			margin-top: var(--space-base);
		}

		&__choice {
			display: flex;
			flex-direction: column;
			align-items: center;
			gap: var(--space-small);
			width: 100%;
			padding: var(--space-large);
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-base);
			background: var(--color-surface);
			color: inherit;
			font: inherit;
			text-align: center;
			cursor: pointer;
			transition:
				border-color var(--timing-base) ease-out,
				background var(--timing-base) ease-out,
				box-shadow var(--timing-base) ease-out,
				transform var(--timing-base) ease-out;

			@media (hover: hover) {
				&:hover {
					border-color: var(--color-border--interactive);
					background: var(--color-surface--hover);
					box-shadow: var(--shadow-base);
					transform: translateY(-2px);
				}
			}

			&:focus-visible {
				outline: 2px solid var(--color-focus);
				outline-offset: 2px;
			}
		}

		&__choice-icon {
			display: grid;
			flex: none;
			place-items: center;
			width: 56px;
			height: 56px;
			border-radius: var(--radius-circle);
			background: var(--color-surface--background);
			color: var(--color-brand);

			:global(svg) {
				width: 26px;
				height: 26px;
			}

			&--google {
				color: var(--color-informative);
			}
		}

		&__choice-text {
			display: flex;
			flex-direction: column;
			gap: 2px;

			strong {
				color: var(--color-heading);
				font-size: var(--typography--fontSize-large);
			}

			span {
				color: var(--color-text--secondary);
				font-size: var(--typography--fontSize-small);
			}
		}

		&__stars {
			display: flex;
			justify-content: center;
			gap: var(--space-small);
			margin-top: var(--space-base);
		}

		&__star {
			display: grid;
			place-items: center;
			width: 52px;
			height: 52px;
			padding: 0;
			border: none;
			border-radius: var(--radius-base);
			background: transparent;
			color: var(--color-border);
			cursor: pointer;
			transition:
				color 120ms ease,
				transform 120ms ease;

			:global(svg) {
				width: 44px;
				height: 44px;
			}

			&--lit {
				color: var(--color-warning);
			}

			@media (hover: hover) {
				&:hover {
					transform: scale(1.08);
				}
			}

			&:focus-visible {
				outline: 2px solid var(--color-focus);
				outline-offset: 1px;
			}
		}

		&__star-label {
			min-height: 1.5em;
			margin: 0;
			color: var(--color-text--secondary);
			font-weight: 600;
			text-align: center;
		}

		&__back {
			display: inline-flex;
			align-items: center;
			align-self: flex-start;
			gap: var(--space-smaller);
			padding: var(--space-smallest) 0;
			border: none;
			background: none;
			color: var(--color-interactive);
			font: inherit;
			font-weight: 600;
			cursor: pointer;

			:global(svg) {
				width: 18px;
				height: 18px;
			}

			&:hover {
				text-decoration: underline;
			}

			&:focus-visible {
				outline: 2px solid var(--color-focus);
				outline-offset: 2px;
			}
		}

		&__private {
			display: inline-flex;
			align-items: center;
			gap: var(--space-smaller);
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);

			:global(svg) {
				width: 16px;
				height: 16px;
			}
		}

		&__form {
			display: flex;
			flex-direction: column;
			gap: var(--space-large);
			margin-top: var(--space-base);
		}

		&__submit-bar {
			width: 100%;
		}

		&__done {
			color: var(--color-success);

			:global(svg) {
				width: 56px;
				height: 56px;
			}
		}

		&__after {
			display: flex;
			flex-direction: column;
			align-items: center;
			gap: var(--space-base);
			width: 100%;
			padding-top: var(--space-large);
			margin-top: var(--space-base);
			border-top: var(--border-base) solid var(--color-border);
		}

		&__button-icon {
			display: inline-grid;

			:global(svg) {
				width: 18px;
				height: 18px;
			}
		}
	}

	// Below this width the real customer page (never the settings preview, which keeps its floating card
	// so it reads correctly inside a dialog at any window size) trades the floating card for an edge-to-edge
	// sheet with bigger touch targets, a stacked choice list instead of the desktop tile grid, and a fixed
	// bottom action bar on the form step so "Send feedback" is always one thumb-reach away.
	@media (max-width: 639px) {
		.review-journey {
			&__title {
				font-size: var(--typography--fontSize-largest);
			}

			&__choices {
				grid-template-columns: 1fr;
				gap: var(--space-small);
			}

			&__choice {
				flex-direction: row;
				align-items: center;
				text-align: left;
				padding: var(--space-base) var(--space-large);
			}

			&__choice-icon {
				width: 48px;
				height: 48px;

				:global(svg) {
					width: 22px;
					height: 22px;
				}
			}

			&__star {
				width: 58px;
				height: 58px;

				:global(svg) {
					width: 46px;
					height: 46px;
				}
			}
		}

		.review-journey:not(.review-journey--preview) .review-journey__head,
		.review-journey:not(.review-journey--preview) .review-journey__body {
			padding-inline: var(--space-large);
		}

		.review-journey:not(.review-journey--preview) {
			max-width: none;
			min-height: 100vh;
			margin: 0;
			border: none;
			border-radius: 0;
			box-shadow: none;
		}

		.review-journey:not(.review-journey--preview) .review-journey__body--form {
			padding-bottom: calc(var(--space-largest) + 76px);
		}

		.review-journey:not(.review-journey--preview) .review-journey__submit-bar {
			position: fixed;
			right: 0;
			bottom: 0;
			left: 0;
			z-index: var(--elevation-base);
			padding: var(--space-base) var(--space-large)
				calc(var(--space-base) + env(safe-area-inset-bottom));
			background: var(--color-surface);
			border-top: var(--border-base) solid var(--color-border);
			box-shadow: var(--shadow-high);
		}
	}
</style>
