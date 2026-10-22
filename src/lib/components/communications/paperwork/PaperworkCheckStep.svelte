<script lang="ts">
	import SetupStepCard from '$lib/components/layout/SetupStepCard.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Banner from '$lib/components/ui/Banner.svelte';
	import FormErrorSummary from '$lib/components/forms/FormErrorSummary.svelte';
	import NextSteps from '$lib/components/communications/add-number/NextSteps.svelte';
	import type { PaperworkDetail, PaperworkFix } from '$lib/communications/number-paperwork';
	import PaperworkFacts from './PaperworkFacts.svelte';
	import { countryName, kindWord, paperworkFacts, withArticle } from './paperwork-ui';
	import sendIcon from '@tabler/icons/outline/send.svg?raw';
	import arrowLeftIcon from '@tabler/icons/outline/arrow-left.svg?raw';
	import hourglassIcon from '@tabler/icons/outline/hourglass.svg?raw';
	import bellIcon from '@tabler/icons/outline/bell.svg?raw';
	import phoneIcon from '@tabler/icons/outline/phone.svg?raw';
	import cashIcon from '@tabler/icons/outline/coin.svg?raw';

	// Step 4 of New paperwork (`concept.pen` board `A0URqF`, Check and send): everything the set says, each with
	// Change, what happens next, and Send for review. A send the server refuses lists what is still missing.
	let {
		detail,
		businessName,
		problems,
		sendError,
		sending,
		onChange,
		onBack,
		onSend
	}: {
		detail: PaperworkDetail;
		businessName: string;
		/** What the server said is still missing, after a refused send. */
		problems: PaperworkFix[];
		sendError: string;
		sending: boolean;
		onChange: (step: 'details' | 'documents') => void;
		onBack: () => void;
		onSend: () => void;
	} = $props();

	let summary = $state<ReturnType<typeof FormErrorSummary>>();
	const facts = $derived(paperworkFacts(detail, businessName));
	const steps = $derived([
		{ icon: hourglassIcon, tone: 'warning', title: 'Under review', hint: '1 to 5 business days' },
		{
			icon: bellIcon,
			tone: 'success',
			title: 'The answer shows here',
			hint: 'On Number paperwork'
		},
		{
			icon: phoneIcon,
			tone: 'informative',
			title: 'Buy your number',
			hint: `Pick ${withArticle(`${countryName(detail.country_code)} ${kindWord(detail.number_type)}`)} number`
		}
	]);
	const message = $derived(
		problems.length
			? `${problems.length} ${problems.length === 1 ? 'thing' : 'things'} to fix before sending`
			: sendError
	);

	$effect(() => {
		if (message) void summary?.reveal();
	});
</script>

<!-- The inline SVG strings are trusted build-time Tabler icon imports. -->
<!-- eslint-disable svelte/no-at-html-tags -->
<SetupStepCard
	title="Check and send"
	hint="You can’t change it while the phone company checks it"
	icon={sendIcon}
	tone="conversation"
	flush
>
	{#if message}
		<div class="paperwork-check__error">
			<FormErrorSummary
				bind:this={summary}
				{message}
				hint={problems.length
					? 'Everything else is kept.'
					: 'Nothing was sent. Try again in a minute.'}
				fields={problems.map((fix) => ({
					anchor: `paperwork-fact-${fix.step}`,
					label: fix.label,
					message: fix.reason
				}))}
			/>
		</div>
	{/if}

	<PaperworkFacts {facts} {onChange} disabled={sending} />

	<div class="paperwork-check__next">
		<NextSteps {steps} />
		<Banner type="success" icon={cashIcon}>
			Paperwork is free. You only pay when you buy the number.
		</Banner>
	</div>

	{#snippet footer()}
		<Button variant="secondary" disabled={sending} onclick={onBack}>
			<span aria-hidden="true">{@html arrowLeftIcon}</span>
			Back
		</Button>
		<span class="paperwork-check__foot"
			>{sending ? 'Sending to the phone company…' : 'Step 4 of 4'}</span
		>
		<Button loading={sending} onclick={onSend}>
			{#if !sending}<span aria-hidden="true">{@html sendIcon}</span>{/if}
			{sending ? 'Sending…' : 'Send for review'}
		</Button>
	{/snippet}
</SetupStepCard>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.paperwork-check {
		&__error {
			padding: var(--space-medium) var(--space-medium) 0;
		}

		&__next {
			display: flex;
			flex-direction: column;
			gap: var(--space-slim);
			padding: var(--space-medium);
			border-top: var(--border-base) solid var(--color-border);
		}

		&__foot {
			flex: 1;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-smaller);
			text-align: center;
		}
	}
</style>
