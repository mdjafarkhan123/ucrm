<script lang="ts">
	import SectionBlock from '$lib/components/layout/SectionBlock.svelte';
	import Toggle from '$lib/components/ui/Toggle.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import Checkbox from '$lib/components/ui/Checkbox.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import layoutIcon from '@tabler/icons/outline/layout-navbar.svg?raw';
	import alertIcon from '@tabler/icons/outline/alert-triangle.svg?raw';
	import brandGoogleIcon from '@tabler/icons/outline/brand-google.svg?raw';
	import messageIcon from '@tabler/icons/outline/message-2.svg?raw';
	import starIcon from '@tabler/icons/filled/star.svg?raw';

	// What the customer sees on the review page. Routing is off by default: every customer gets both choices.
	// Turning it on sends customers by star rating and needs the owner to accept a hard warning first
	// (docs/google-review-campaign-owner-brief.md § Review routing). `acknowledged` tells the parent the
	// warning was accepted in this edit, so the save can record it.
	let {
		enabled = $bindable(),
		minRating = $bindable(),
		acknowledged = $bindable(),
		hasGoogleLink,
		disabled = false,
		errorMessage = ''
	}: {
		enabled: boolean;
		minRating: number;
		acknowledged: boolean;
		hasGoogleLink: boolean;
		disabled?: boolean;
		errorMessage?: string;
	} = $props();

	let warningOpen = $state(false);
	let understood = $state(false);

	const ratingOptions = [
		{ value: '5', label: '5 stars only' },
		{ value: '4', label: '4 or 5 stars (recommended start)' },
		{ value: '3', label: '3 stars or more' },
		{ value: '2', label: '2 stars or more' }
	];

	function onToggle(next: boolean) {
		if (!next) {
			enabled = false;
			acknowledged = false;
			return;
		}
		// The switch stays off until the warning is accepted. It is bound two-way, so the click has already
		// set `enabled` to true; resetting it here is a real change that flips the switch back.
		enabled = false;
		understood = false;
		warningOpen = true;
	}

	function acceptWarning() {
		enabled = true;
		acknowledged = true;
		warningOpen = false;
	}

	const lowStars = $derived(minRating - 1);
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<SectionBlock
	title="Review page"
	hint="What a customer sees after tapping the link in your message."
	icon={layoutIcon}
	form
	level={3}
>
	<div class="review-routing">
		<div class="review-routing__preview" aria-hidden="true">
			{#if enabled}
				<p class="review-routing__preview-title">How would you rate your experience?</p>
				<div class="review-routing__stars">
					{#each [1, 2, 3, 4, 5] as star (star)}
						<span
							class="review-routing__star"
							class:review-routing__star--google={star >= minRating}
						>
							{@html starIcon}
						</span>
					{/each}
				</div>
				<ul class="review-routing__routes">
					<li>
						<span class="review-routing__route-icon">{@html brandGoogleIcon}</span>
						{minRating === 5 ? '5 stars' : `${minRating}–5 stars`} open your Google review page
					</li>
					<li>
						<span class="review-routing__route-icon">{@html messageIcon}</span>
						{lowStars === 1 ? '1 star' : `1–${lowStars} stars`} open your private feedback form first,
						with a Google review link still shown
					</li>
				</ul>
			{:else}
				<p class="review-routing__preview-title">How did we do?</p>
				<div class="review-routing__choices">
					<span class="review-routing__choice review-routing__choice--primary">
						<span class="review-routing__route-icon">{@html brandGoogleIcon}</span>
						Leave a Google review
					</span>
					<span class="review-routing__choice">
						<span class="review-routing__route-icon">{@html messageIcon}</span>
						Tell us privately
					</span>
				</div>
			{/if}
		</div>

		<p class="review-routing__explain">
			{#if enabled}
				Review routing is on. Customers pick a star rating first and are sent on by what they pick.
				Nobody is kept from Google: the private form always keeps a link to post a Google review.
			{:else}
				Every customer sees the same two choices. Nothing is hidden or depends on how happy they
				are, which keeps you within Google's review rules.
			{/if}
		</p>

		<Toggle
			id="review-routing-enabled"
			label="Send customers by star rating (review routing)"
			description={hasGoogleLink
				? 'Off is recommended. Turning it on asks you to accept a warning first.'
				: 'Add your Google review link above before you can turn this on.'}
			bind:checked={enabled}
			disabled={disabled || (!enabled && !hasGoogleLink)}
			labelSide="start"
			onchange={onToggle}
		/>

		{#if enabled}
			<div class="review-routing__rating">
				<Select
					id="review-routing-min-rating"
					label="Send to Google from"
					options={ratingOptions}
					value={String(minRating)}
					{disabled}
					onchange={(value) => (minRating = Number(value))}
				/>
			</div>
		{/if}

		{#if errorMessage}
			<p class="review-routing__error" role="alert">{errorMessage}</p>
		{/if}
	</div>
</SectionBlock>

<Dialog
	open={warningOpen}
	title="Turn on review routing?"
	initialFocusId="review-routing-understood"
	onClose={() => (warningOpen = false)}
>
	<div class="routing-warning">
		<div class="routing-warning__banner" role="alert">
			<span class="routing-warning__icon" aria-hidden="true">{@html alertIcon}</span>
			<p>
				Customers who pick high star ratings go straight to Google. Everyone else sees your private
				form first, with a link to post a Google review still shown.
			</p>
		</div>
		<p>
			Asking only happy customers for public reviews is called review gating, and it is not allowed.
			UCRM never hides the Google link from anyone, but steering customers by their rating can still
			look like gating:
		</p>
		<ul class="routing-warning__list">
			<li>
				<strong>Google</strong> says businesses must not selectively ask satisfied customers for reviews.
				Google can remove your reviews or restrict your Business Profile.
			</li>
			<li>
				<strong>In the UK</strong>, the Competition and Markets Authority says encouraging only
				satisfied customers to leave reviews may break consumer law.
			</li>
			<li>
				<strong>In the US</strong>, the Federal Trade Commission tells businesses not to ask for
				reviews only from customers they expect to be positive.
			</li>
		</ul>
		<p>
			UCRM recommends leaving routing off. If you turn it on, you are responsible for this choice
			and its consequences for your business.
		</p>
		<Checkbox
			id="review-routing-understood"
			label="I understand the risk and take responsibility for turning on review routing."
			bind:checked={understood}
		/>
		<div class="routing-warning__actions">
			<Button variant="secondary" onclick={() => (warningOpen = false)}>Keep it off</Button>
			<Button variation="destructive" disabled={!understood} onclick={acceptWarning}>
				Turn on routing
			</Button>
		</div>
	</div>
</Dialog>

<style lang="scss">
	.review-routing {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);

		&__preview {
			display: flex;
			flex-direction: column;
			align-items: center;
			gap: var(--space-slim);
			padding: var(--space-large) var(--space-base);
			border: var(--border-base) dashed var(--color-border);
			border-radius: var(--radius-base);
			background: var(--color-surface--background--subtle);
			text-align: center;
		}

		&__preview-title {
			margin: 0;
			color: var(--color-heading);
			font-size: var(--typography--fontSize-large);
			font-weight: 700;
		}

		&__choices {
			display: flex;
			flex-wrap: wrap;
			justify-content: center;
			gap: var(--space-small);
		}

		&__choice {
			display: inline-flex;
			align-items: center;
			gap: var(--space-small);
			padding: var(--space-small) var(--space-base);
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-base);
			color: var(--color-text);
			background: var(--color-surface);
			font-weight: 600;

			&--primary {
				border-color: var(--color-interactive);
				color: var(--color-surface);
				background: var(--color-interactive);
			}
		}

		&__stars {
			display: flex;
			gap: var(--space-smaller);
		}

		&__star {
			display: inline-grid;
			color: var(--color-disabled);

			&--google {
				color: var(--color-warning);
			}

			:global(svg) {
				width: 28px;
				height: 28px;
			}
		}

		&__routes {
			display: flex;
			flex-direction: column;
			gap: var(--space-smaller);
			margin: 0;
			padding: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			list-style: none;

			li {
				display: inline-flex;
				align-items: center;
				gap: var(--space-small);
			}
		}

		&__route-icon {
			display: inline-grid;

			:global(svg) {
				width: 18px;
				height: 18px;
			}
		}

		&__explain {
			margin: 0;
			color: var(--color-text--secondary);
		}

		&__rating {
			max-width: 320px;
		}

		&__error {
			margin: 0;
			color: var(--color-critical);
			font-size: var(--typography--fontSize-small);
		}
	}

	.routing-warning {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);

		p {
			margin: 0;
		}

		&__banner {
			display: flex;
			align-items: center;
			gap: var(--space-small);
			padding: var(--space-slim) var(--space-base);
			border-radius: var(--radius-base);
			color: var(--color-critical--onSurface);
			background: var(--color-critical--surface);
		}

		&__icon {
			display: inline-grid;
			flex: 0 0 auto;

			:global(svg) {
				width: 20px;
				height: 20px;
			}
		}

		&__list {
			display: flex;
			flex-direction: column;
			gap: var(--space-small);
			margin: 0;
			padding-left: var(--space-large);
		}

		&__actions {
			display: flex;
			justify-content: flex-end;
			gap: var(--space-small);
		}
	}
</style>
