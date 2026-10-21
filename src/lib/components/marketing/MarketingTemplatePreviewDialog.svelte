<script lang="ts">
	import mailIcon from '@tabler/icons/outline/mail.svg?raw';
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

<!-- The email preview pop-up (design `modals.md`): a look only, so it has no footer. -->
<Dialog
	open={true}
	{title}
	subtitle="Email preview · what customers will see"
	icon={mailIcon}
	iconTone="growth"
	size="large"
	{onClose}
>
	<MarketingTemplatePreview {title} {content} />
</Dialog>
