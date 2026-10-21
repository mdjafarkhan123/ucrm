<script lang="ts">
	import { createQuery } from '@tanstack/svelte-query';
	import desktopIcon from '@tabler/icons/outline/device-desktop.svg?raw';
	import mobileIcon from '@tabler/icons/outline/device-mobile.svg?raw';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import SegmentedControl from '$lib/components/ui/SegmentedControl.svelte';
	import EmailPreviewBone from './EmailPreviewBone.svelte';
	import { previewCampaignContent } from '$lib/marketing/api';
	import {
		marketingCampaignPreviewKey,
		type MarketingCampaignContent
	} from '$lib/marketing/campaign-content';

	// The rendered desktop/mobile message: shared by MarketingTemplatePreviewDialog (an on-demand look while
	// editing) and CampaignReviewStep (always on screen, blueprint §8 step 5's "rendered desktop/mobile
	// message"), so the render call and the viewport toggle exist in exactly one place.
	let { title, content }: { title: string; content: MarketingCampaignContent } = $props();

	let viewport = $state<'desktop' | 'mobile'>('desktop');

	// Only the chosen width's icon takes the Marketing colour (design `modals.md` → Email preview pop-up).
	const viewportOptions = $derived(
		[
			{ value: 'desktop', label: 'Desktop', icon: desktopIcon },
			{ value: 'mobile', label: 'Mobile', icon: mobileIcon }
		].map((option) => ({
			...option,
			iconColor: option.value === viewport ? 'var(--color-growth)' : 'var(--color-icon--secondary)'
		}))
	);

	const query = createQuery(() => ({
		queryKey: marketingCampaignPreviewKey(content),
		queryFn: () => previewCampaignContent(content)
	}));
</script>

<div class="template-preview">
	<SegmentedControl bind:value={viewport} ariaLabel="Preview width" options={viewportOptions} />

	{#if query.isError}
		<div class="template-preview__problem">
			<ErrorState
				title="This could not be rendered"
				description="Something went wrong on our side. Try again."
				retry={() => query.refetch()}
			/>
		</div>
	{:else}
		<!-- The well the email sits in, at the width a customer's screen gives it. -->
		<div class="template-preview__well">
			<div
				class="template-preview__paper"
				class:template-preview__paper--mobile={viewport === 'mobile'}
			>
				{#if query.isPending}
					<EmailPreviewBone />
				{:else}
					<iframe title={`${title} preview`} srcdoc={query.data.html} sandbox=""></iframe>
				{/if}
			</div>
		</div>
	{/if}
</div>

<style lang="scss">
	.template-preview {
		display: grid;
		gap: var(--space-base);
		justify-items: start;
	}

	.template-preview__problem {
		box-sizing: border-box;
		display: grid;
		place-items: center;
		justify-self: stretch;
		min-height: 320px;
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface);
	}

	.template-preview__well {
		box-sizing: border-box;
		display: flex;
		justify-content: center;
		width: 100%;
		height: 70vh;
		overflow: auto;
		padding: 28px 0;
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface--background--subtle);
	}

	.template-preview__paper {
		flex: 0 0 auto;
		width: 600px;
		max-width: calc(100% - var(--space-larger));
		height: 100%;
		overflow: hidden;
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-small);
		background: var(--color-surface);

		&--mobile {
			width: 375px;
		}

		// The email keeps its own light colours in dark mode.
		iframe {
			display: block;
			width: 100%;
			height: 100%;
			border: 0;
			background: var(--color-white);
		}
	}
</style>
