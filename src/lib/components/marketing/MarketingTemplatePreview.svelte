<script lang="ts">
	import { createQuery } from '@tanstack/svelte-query';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import SegmentedControl from '$lib/components/ui/SegmentedControl.svelte';
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

	const query = createQuery(() => ({
		queryKey: marketingCampaignPreviewKey(content),
		queryFn: () => previewCampaignContent(content)
	}));
</script>

<div class="template-preview">
	<SegmentedControl
		bind:value={viewport}
		label="Preview width"
		options={[
			{ value: 'desktop', label: 'Desktop' },
			{ value: 'mobile', label: 'Mobile' }
		]}
	/>

	{#if query.isPending}
		<LoadingSkeleton variant="card" rows={4} label="Rendering preview" />
	{:else if query.isError}
		<ErrorState
			title="This could not be rendered"
			description="Something went wrong on our side. Try again."
			retry={() => query.refetch()}
		/>
	{:else}
		<div
			class="template-preview__frame"
			class:template-preview__frame--mobile={viewport === 'mobile'}
		>
			<iframe title={`${title} preview`} srcdoc={query.data.html} sandbox=""></iframe>
		</div>
	{/if}
</div>

<style lang="scss">
	.template-preview {
		display: grid;
		gap: var(--space-base);
		justify-items: start;
	}

	.template-preview__frame {
		width: 100%;
		height: 70vh;
		overflow: auto;
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface--background--subtle);

		&--mobile {
			width: 375px;
			max-width: 100%;
			margin-inline: auto;
		}

		iframe {
			width: 100%;
			height: 100%;
			border: 0;
			background: var(--color-surface);
		}
	}
</style>
