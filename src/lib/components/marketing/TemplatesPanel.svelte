<script lang="ts">
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import SectionBlock from '$lib/components/layout/SectionBlock.svelte';
	import DropdownMenu from '$lib/components/ui/DropdownMenu.svelte';
	import DataTable, { type DataTableColumn } from '$lib/components/data-display/DataTable.svelte';
	import EmptyState from '$lib/components/data-display/EmptyState.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import MarketingTemplatePreviewDialog from './MarketingTemplatePreviewDialog.svelte';
	import {
		fetchMarketingTemplates,
		copyMarketingTemplateRequest,
		marketingTemplatesKey
	} from '$lib/marketing/api';
	import {
		marketingGoalLabels,
		type MarketingCampaignContent
	} from '$lib/marketing/campaign-content';
	import type { MarketingEmailTemplate, MarketingPlatformTemplate } from '$lib/marketing/templates';
	import templateIcon from '@tabler/icons/outline/template.svg?raw';
	import eyeIcon from '@tabler/icons/outline/eye.svg?raw';
	import copyIcon from '@tabler/icons/outline/copy.svg?raw';

	const queryClient = useQueryClient();
	const toast = getToastManager();

	const query = createQuery(() => ({
		queryKey: marketingTemplatesKey,
		queryFn: fetchMarketingTemplates
	}));

	// A platform starter already copied into the org's library offers no second copy action -- nothing in
	// the first release deletes a copied template, so an unbounded "Use template" would only pile up
	// duplicates with no way back out.
	const copiedSourceIds = $derived(
		new Set(
			(query.data?.templates ?? [])
				.map((template) => template.source_template_id)
				.filter((id): id is string => id !== null)
		)
	);

	let preview = $state<{ title: string; content: MarketingCampaignContent } | null>(null);

	function contentOf(template: {
		subject: string;
		preview_text: string | null;
		blocks: MarketingCampaignContent['blocks'];
	}): MarketingCampaignContent {
		return {
			version: '1',
			subject: template.subject,
			preview_text: template.preview_text ?? undefined,
			blocks: template.blocks
		};
	}

	async function useTemplate(template: MarketingPlatformTemplate) {
		try {
			await copyMarketingTemplateRequest(template.key);
			await queryClient.invalidateQueries({ queryKey: marketingTemplatesKey });
			toast.success(`"${template.name}" added to your templates.`);
		} catch (cause) {
			toast.error(cause instanceof Error ? cause.message : 'That template could not be copied.');
		}
	}

	function platformMenuItems(template: MarketingPlatformTemplate) {
		return [
			{
				label: 'Preview',
				icon: eyeIcon,
				onSelect: () => (preview = { title: template.name, content: contentOf(template) })
			},
			{
				label: copiedSourceIds.has(template.id) ? 'Added to your templates' : 'Use template',
				icon: copyIcon,
				disabled: copiedSourceIds.has(template.id),
				onSelect: () => void useTemplate(template)
			}
		];
	}

	function ownMenuItems(template: MarketingEmailTemplate) {
		return [
			{
				label: 'Preview',
				icon: eyeIcon,
				onSelect: () => (preview = { title: template.name, content: contentOf(template) })
			}
		];
	}

	const platformColumns: DataTableColumn[] = [
		{ key: 'name', label: 'Name' },
		{ key: 'goal', label: 'Best for' }
	];
	const ownColumns: DataTableColumn[] = [
		{ key: 'name', label: 'Name' },
		{ key: 'subject', label: 'Subject' },
		{ key: 'updated_at', label: 'Last updated' }
	];

	const dateFormatter = new Intl.DateTimeFormat('en-US', { dateStyle: 'medium' });
</script>

<div class="templates">
	<SectionBlock
		title="Starter templates"
		hint="Branded starting points. Use one to copy it into your own library."
		level={2}
	>
		{#if query.isPending}
			<LoadingSkeleton variant="table" rows={4} label="Loading starter templates" />
		{:else if query.isError}
			<ErrorState description="Templates could not be loaded." retry={() => query.refetch()} />
		{:else}
			<DataTable
				columns={platformColumns}
				items={query.data.platform_templates}
				rowId={(template) => template.id}
				caption="Starter templates"
			>
				{#snippet row(template: MarketingPlatformTemplate)}
					<th scope="row">{template.name}</th>
					<td>{template.goal ? marketingGoalLabels[template.goal] : '—'}</td>
				{/snippet}
				{#snippet rowActions(template: MarketingPlatformTemplate)}
					<DropdownMenu
						triggerLabel={`Actions for ${template.name}`}
						items={platformMenuItems(template)}
					/>
				{/snippet}
			</DataTable>
		{/if}
	</SectionBlock>

	<SectionBlock
		title="Your templates"
		hint="Starter templates you have copied into this organization."
		level={2}
	>
		{#if query.isPending}
			<LoadingSkeleton variant="table" rows={2} label="Loading your templates" />
		{:else if query.isError}
			<ErrorState description="Templates could not be loaded." retry={() => query.refetch()} />
		{:else if query.data.templates.length === 0}
			<EmptyState
				icon={templateIcon}
				title="No templates yet"
				description="Use a starter template above and it appears here, ready to pick when you create a campaign."
			/>
		{:else}
			<DataTable
				columns={ownColumns}
				items={query.data.templates}
				rowId={(template) => template.id}
				caption="Your templates"
			>
				{#snippet row(template: MarketingEmailTemplate)}
					<th scope="row">{template.name}</th>
					<td>{template.subject}</td>
					<td>{dateFormatter.format(new Date(template.updated_at))}</td>
				{/snippet}
				{#snippet rowActions(template: MarketingEmailTemplate)}
					<DropdownMenu
						triggerLabel={`Actions for ${template.name}`}
						items={ownMenuItems(template)}
					/>
				{/snippet}
			</DataTable>
		{/if}
	</SectionBlock>
</div>

{#if preview}
	<MarketingTemplatePreviewDialog
		title={preview.title}
		content={preview.content}
		onClose={() => (preview = null)}
	/>
{/if}

<style lang="scss">
	.templates {
		display: grid;
		gap: var(--space-large);
	}
</style>
