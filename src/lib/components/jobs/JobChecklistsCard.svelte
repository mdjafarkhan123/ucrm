<script lang="ts">
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import SectionBlock from '$lib/components/layout/SectionBlock.svelte';
	import EmptyState from '$lib/components/data-display/EmptyState.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import ConfirmDialog from '$lib/components/ui/ConfirmDialog.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import {
		attachJobChecklist,
		checklistTemplatesKey,
		fetchChecklistTemplates,
		fetchJobChecklists,
		jobChecklistsKey,
		removeJobChecklist
	} from '$lib/checklists/api';
	import type { JobChecklist } from '$lib/checklists/types';
	import checklistIcon from '@tabler/icons/outline/checklist.svg?raw';
	import trashIcon from '@tabler/icons/outline/trash.svg?raw';

	let { jobId, active }: { jobId: string; active: boolean } = $props();

	const queryClient = useQueryClient();
	const toast = getToastManager();
	let adding = $state(false);
	let selectedTemplateId = $state('');
	let attaching = $state(false);
	let removeTarget = $state<JobChecklist | null>(null);
	let removing = $state(false);

	const jobQuery = createQuery(() => ({
		queryKey: jobChecklistsKey(jobId),
		queryFn: () => fetchJobChecklists(jobId),
		enabled: Boolean(jobId)
	}));

	// The library is revealed content. Hovering the Add button warms it; opening the picker enables the
	// observer and uses that cached result.
	const templatesQuery = createQuery(() => ({
		queryKey: checklistTemplatesKey(false),
		queryFn: () => fetchChecklistTemplates(false),
		enabled: adding,
		staleTime: 5 * 60 * 1000
	}));

	const attachedTemplateIds = $derived(
		new Set((jobQuery.data?.checklists ?? []).map((checklist) => checklist.source_template_id))
	);
	const templateOptions = $derived(
		(templatesQuery.data?.templates ?? [])
			.filter((template) => !attachedTemplateIds.has(template.id))
			.map((template) => ({ value: template.id, label: template.name }))
	);

	function warmTemplates() {
		void queryClient.prefetchQuery({
			queryKey: checklistTemplatesKey(false),
			queryFn: () => fetchChecklistTemplates(false),
			staleTime: 5 * 60 * 1000
		});
	}

	async function refresh() {
		await queryClient.invalidateQueries({ queryKey: ['checklists'] });
	}

	async function attach() {
		if (!selectedTemplateId || attaching) return;
		attaching = true;
		try {
			await attachJobChecklist(jobId, selectedTemplateId);
			selectedTemplateId = '';
			adding = false;
			await refresh();
			toast.success('Checklist attached.');
		} catch (cause) {
			toast.error(cause instanceof Error ? cause.message : 'That checklist could not be attached.');
		} finally {
			attaching = false;
		}
	}

	async function remove() {
		if (!removeTarget || removing) return;
		removing = true;
		try {
			const result = await removeJobChecklist(jobId, removeTarget.id);
			removeTarget = null;
			await refresh();
			toast.success(
				result.answers_removed > 0
					? `Checklist removed with ${result.answers_removed} saved ${result.answers_removed === 1 ? 'answer' : 'answers'}.`
					: 'Checklist removed.'
			);
		} catch (cause) {
			toast.error(cause instanceof Error ? cause.message : 'That checklist could not be removed.');
		} finally {
			removing = false;
		}
	}
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<SectionBlock title="Checklists" icon={checklistIcon} level={2}>
	{#snippet actions()}
		{#if jobQuery.data?.can_edit && active && !adding}
			<Button
				size="small"
				variant="tertiary"
				onhover={warmTemplates}
				onclick={() => (adding = true)}>Add checklist</Button
			>
		{/if}
	{/snippet}

	{#if jobQuery.isPending}
		<LoadingSkeleton variant="text" rows={2} label="Loading checklists" />
	{:else if jobQuery.isError}
		<p class="job-checklists__error" role="alert">Checklists could not be loaded.</p>
	{:else}
		{@const checklists = jobQuery.data?.checklists ?? []}
		{#if checklists.length === 0 && !adding}
			<EmptyState
				icon={checklistIcon}
				title="No checklists attached"
				description={jobQuery.data?.can_edit && active
					? 'Attach a checklist so every visit has the same questions to fill in.'
					: 'This job has no checklists.'}
			/>
		{:else if checklists.length > 0}
			<ul class="job-checklists__list">
				{#each checklists as checklist (checklist.id)}
					<li class="job-checklists__item">
						<div>
							<p class="job-checklists__name">{checklist.name}</p>
							<p class="job-checklists__summary">
								{checklist.items.length}
								{checklist.items.length === 1 ? 'question' : 'questions'}
							</p>
						</div>
						{#if jobQuery.data?.can_edit && active}
							<Button
								size="small"
								variant="tertiary"
								variation="destructive"
								onclick={() => (removeTarget = checklist)}
							>
								<span class="job-checklists__remove-icon" aria-hidden="true">{@html trashIcon}</span
								>
								Remove
							</Button>
						{/if}
					</li>
				{/each}
			</ul>
		{/if}

		{#if adding}
			<div class="job-checklists__attach">
				{#if templatesQuery.isPending}
					<LoadingSkeleton variant="text" label="Loading checklist library" />
				{:else if templatesQuery.isError}
					<p class="job-checklists__error" role="alert">
						The checklist library could not be loaded.
					</p>
				{:else if templateOptions.length === 0}
					<p class="job-checklists__empty">Every available checklist is already attached.</p>
				{:else}
					<Select
						id="job-checklist-template"
						label="Checklist"
						options={templateOptions}
						bind:value={selectedTemplateId}
					/>
				{/if}
				<div class="job-checklists__actions">
					<Button
						variant="tertiary"
						disabled={attaching}
						onclick={() => {
							selectedTemplateId = '';
							adding = false;
						}}>Cancel</Button
					>
					{#if templateOptions.length > 0}
						<Button loading={attaching} disabled={!selectedTemplateId} onclick={() => void attach()}
							>Attach checklist</Button
						>
					{/if}
				</div>
			</div>
		{/if}
	{/if}
</SectionBlock>

<ConfirmDialog
	open={removeTarget !== null}
	title="Remove this checklist?"
	tone="critical"
	destructive
	confirmLabel="Remove checklist"
	loading={removing}
	onConfirm={() => void remove()}
	onClose={() => (removeTarget = null)}
>
	{#if (removeTarget?.answers_count ?? 0) > 0}
		This also removes <strong>{removeTarget?.answers_count}</strong> saved
		{removeTarget?.answers_count === 1 ? 'answer' : 'answers'} from this job's visits. This cannot be
		undone.
	{:else}
		This takes the checklist off every visit on this job. This cannot be undone.
	{/if}
</ConfirmDialog>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.job-checklists {
		&__list {
			display: grid;
			gap: var(--space-small);
			margin: 0;
			padding: 0;
			list-style: none;
		}

		&__item {
			display: flex;
			align-items: center;
			justify-content: space-between;
			gap: var(--space-base);
			padding: var(--space-small) var(--space-base);
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-base);
			background: var(--color-surface--background--subtle);
		}

		&__name,
		&__summary,
		&__error,
		&__empty {
			margin: 0;
		}

		&__name {
			color: var(--color-heading);
			font-weight: 600;
		}

		&__summary,
		&__empty {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__error {
			color: var(--color-critical);
		}

		&__attach {
			display: grid;
			gap: var(--space-base);
			padding-top: var(--space-small);
		}

		&__actions {
			display: flex;
			justify-content: flex-end;
			gap: var(--space-small);
		}

		&__remove-icon :global(svg) {
			display: block;
			width: 16px;
			height: 16px;
		}
	}
</style>
