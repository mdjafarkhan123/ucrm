<script lang="ts">
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import MarketingTemplatePreview from './MarketingTemplatePreview.svelte';
	import type { MarketingCampaignContent } from '$lib/marketing/campaign-content';

	let {
		title,
		content,
		onClose
	}: {
		title: string;
		content: MarketingCampaignContent;
		onClose: () => void;
	} = $props();
</script>

<Dialog open={true} {title} size="large" {onClose}>
	<MarketingTemplatePreview {title} {content} />
</Dialog>
