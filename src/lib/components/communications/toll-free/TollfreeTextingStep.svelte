<script lang="ts">
	import SetupStepCard from '$lib/components/layout/SetupStepCard.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import Textarea from '$lib/components/ui/Textarea.svelte';
	import type { TollfreeBusiness } from '$lib/communications/sms-tollfree';
	import type { TollfreeDraft } from './tollfree-draft.svelte';
	import messageIcon from '@tabler/icons/outline/message.svg?raw';
	import arrowLeftIcon from '@tabler/icons/outline/arrow-left.svg?raw';
	import arrowRightIcon from '@tabler/icons/outline/arrow-right.svg?raw';

	// Step 2 of the toll-free check (`concept.pen` board `SCpaW`, "How you will use texting"): what the texts are
	// about, how customers agree, two real examples and the policy links.
	let {
		draft,
		errors,
		continuing,
		onBack,
		onContinue
	}: {
		draft: TollfreeDraft;
		errors: Record<string, string>;
		continuing: boolean;
		onBack: () => void;
		onContinue: () => void;
	} = $props();

	type Messaging = TollfreeBusiness['messaging'];
	const messaging = $derived(draft.business.messaging);

	// Twilio's toll-free check has no "another way" of agreeing, so the form offers only its own four.
	const CONSENT_METHODS = [
		{ value: 'website_form', label: 'Website form' },
		{ value: 'paper_form', label: 'Paper form' },
		{ value: 'verbal', label: 'In person or on a call' },
		{ value: 'text_initiated', label: 'Customer texted us first' }
	];
	const VOLUMES = [
		{ value: 'under_500', label: 'Under 500' },
		{ value: '500_2000', label: '500 to 2,000' },
		{ value: '2001_10000', label: '2,001 to 10,000' },
		{ value: 'over_10000', label: 'Over 10,000' }
	];

	function setLink(key: 'privacy_policy_url' | 'terms_url', value: string) {
		// An empty optional link is left out, not sent as a blank address.
		messaging[key] = value.trim() || undefined;
		draft.changed();
	}
</script>

<!-- The inline SVG strings are trusted build-time Tabler icon imports. -->
<!-- eslint-disable svelte/no-at-html-tags -->
<SetupStepCard
	title="How you will use texting"
	hint="These answers help the phone company understand the messages you send."
	icon={messageIcon}
	tone="conversation"
>
	<div class="tollfree-texting">
		<Textarea
			id="tollfree-purpose"
			label="What will you text customers about?"
			required
			rows={3}
			bind:value={messaging.description}
			errorMessage={errors['messaging.description']}
			oninput={() => draft.changed()}
		/>
		<div class="tollfree-texting__pair">
			<Select
				id="tollfree-consent"
				label="How do customers agree?"
				required
				options={CONSENT_METHODS}
				value={messaging.consent_method === 'other' ? '' : messaging.consent_method}
				placeholder="Choose one"
				errorMessage={errors['messaging.consent_method']}
				onchange={(value) => {
					messaging.consent_method = value as Messaging['consent_method'];
					draft.changed();
				}}
			/>
			<Select
				id="tollfree-volume"
				label="Estimated texts each month"
				required
				options={VOLUMES}
				value={messaging.estimated_monthly_messages}
				onchange={(value) => {
					messaging.estimated_monthly_messages = value as Messaging['estimated_monthly_messages'];
					draft.changed();
				}}
			/>
		</div>
		<Textarea
			id="tollfree-consent-how"
			label="Explain how customers agree"
			required
			rows={3}
			bind:value={messaging.consent_description}
			errorMessage={errors['messaging.consent_description']}
			oninput={() => draft.changed()}
		/>

		<section class="tollfree-texting__examples" aria-labelledby="tollfree-examples">
			<h3 id="tollfree-examples">Example texts customers will receive</h3>
			<div class="tollfree-texting__pair">
				{#each [0, 1] as index (index)}
					<Textarea
						id={`tollfree-example-${index + 1}`}
						label={`Example ${index + 1}`}
						required
						rows={3}
						bind:value={messaging.sample_messages[index]}
						errorMessage={errors[`messaging.sample_messages.${index}`]}
						oninput={() => draft.changed()}
					/>
				{/each}
			</div>
		</section>

		<div class="tollfree-texting__pair">
			<Input
				id="tollfree-privacy"
				label="Privacy policy link (optional)"
				type="url"
				placeholder="https://"
				value={messaging.privacy_policy_url ?? ''}
				errorMessage={errors['messaging.privacy_policy_url']}
				oninput={(event: Event) =>
					setLink('privacy_policy_url', (event.currentTarget as HTMLInputElement).value)}
			/>
			<Input
				id="tollfree-terms"
				label="Terms link (optional)"
				type="url"
				placeholder="https://"
				value={messaging.terms_url ?? ''}
				errorMessage={errors['messaging.terms_url']}
				oninput={(event: Event) =>
					setLink('terms_url', (event.currentTarget as HTMLInputElement).value)}
			/>
		</div>
	</div>

	{#snippet footer()}
		<Button variant="secondary" onclick={onBack}>
			<span aria-hidden="true">{@html arrowLeftIcon}</span>
			Back
		</Button>
		<span class="tollfree-texting__foot">Step 2 of 4 · saved as you type</span>
		<Button loading={continuing} onclick={onContinue}>
			{#if !continuing}<span aria-hidden="true">{@html arrowRightIcon}</span>{/if}
			Continue
		</Button>
	{/snippet}
</SetupStepCard>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.tollfree-texting {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);

		&__pair {
			display: grid;
			grid-template-columns: repeat(2, minmax(0, 1fr));
			gap: var(--space-base);
		}

		&__examples {
			display: flex;
			flex-direction: column;
			gap: var(--space-slim);

			h3 {
				margin: 0;
				color: var(--color-heading);
				font-size: var(--typography--fontSize-base);
				font-weight: 600;
			}
		}

		&__foot {
			flex: 1;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-smaller);
			text-align: center;
		}
	}
</style>
