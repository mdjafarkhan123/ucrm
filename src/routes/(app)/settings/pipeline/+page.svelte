<script lang="ts">
	import { untrack } from 'svelte';
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import { beforeNavigate } from '$app/navigation';
	import { resolve } from '$app/paths';
	import Breadcrumbs from '$lib/components/layout/Breadcrumbs.svelte';
	import RecordFormLayout from '$lib/components/layout/RecordFormLayout.svelte';
	import SectionBlock from '$lib/components/layout/SectionBlock.svelte';
	import Toggle from '$lib/components/ui/Toggle.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import {
		fetchSettingsPipeline,
		settingsPipelineKey,
		savePipelineSettings,
		isSaveConflict
	} from '$lib/settings/api';
	import { invalidatePipeline } from '$lib/pipeline/api';
	import layoutKanbanIcon from '@tabler/icons/outline/layout-kanban.svg?raw';
	import alertTriangleIcon from '@tabler/icons/outline/alert-triangle.svg?raw';

	const queryClient = useQueryClient();
	const toast = getToastManager();
	const query = createQuery(() => ({
		queryKey: settingsPipelineKey,
		queryFn: fetchSettingsPipeline
	}));

	let detailed = $state<boolean | null>(null);
	let savedDetailed = $state<boolean | null>(null);
	let saving = $state(false);
	let errorMessage = $state('');
	let conflict = $state<{ editor_name: string | null; edited_at: string | null } | null>(null);

	$effect(() => {
		const pipeline = query.data?.pipeline;
		if (!pipeline) return;
		untrack(() => {
			if (detailed !== null) return;
			detailed = pipeline.detailed_assessment_stages;
			savedDetailed = pipeline.detailed_assessment_stages;
		});
	});

	const dirty = $derived(detailed !== null && savedDetailed !== null && detailed !== savedDetailed);

	beforeNavigate((navigation) => {
		if (!dirty) return;
		if (!confirm('Leave this page? Your changes have not been saved.')) navigation.cancel();
	});
	$effect(() => {
		function handler(event: BeforeUnloadEvent) {
			if (!dirty) return;
			event.preventDefault();
		}
		window.addEventListener('beforeunload', handler);
		return () => window.removeEventListener('beforeunload', handler);
	});

	function cancel() {
		detailed = savedDetailed;
		conflict = null;
		errorMessage = '';
	}

	async function save() {
		if (!query.data || detailed === null) return;
		saving = true;
		errorMessage = '';
		conflict = null;

		const result = await savePipelineSettings({
			expected_revision: query.data.pipeline.revision,
			detailed_assessment_stages: detailed
		}).catch((error: Error) => {
			errorMessage = error.message;
			return null;
		});
		if (!result) {
			saving = false;
			return;
		}
		if (isSaveConflict(result)) {
			conflict = { editor_name: result.editor_name, edited_at: result.edited_at };
			saving = false;
			return;
		}

		savedDetailed = detailed;
		saving = false;
		toast.success('Pipeline settings saved.');
		await queryClient.invalidateQueries({ queryKey: settingsPipelineKey });
		await invalidatePipeline(queryClient);
	}
</script>

<svelte:head><title>Pipeline · Settings · Contractor CRM</title></svelte:head>

{#if query.isPending || detailed === null}
	<LoadingSkeleton variant="card" rows={2} />
{:else if query.isError}
	<ErrorState description="Pipeline settings could not be loaded." retry={() => query.refetch()} />
{:else}
	{@const canEdit = query.data.permissions.edit}
	{@const editor = query.data.pipeline.last_editor}

	<Breadcrumbs
		items={[{ label: 'Settings', href: resolve('/(app)/settings') }, { label: 'Pipeline' }]}
	/>

	<RecordFormLayout title="Pipeline" icon={layoutKanbanIcon}>
		{#snippet main()}
			{#if !canEdit}
				<p class="pipeline-settings__readonly">
					Only owners and administrators can change this. {#if editor}Last changed by {editor.name ??
							'a teammate'}.{/if}
				</p>
			{/if}
			{#if conflict}
				<p class="pipeline-settings__conflict" role="alert">
					<!-- eslint-disable-next-line svelte/no-at-html-tags -->
					<span aria-hidden="true">{@html alertTriangleIcon}</span>
					{conflict.editor_name ?? 'Someone else'} just changed this. Refresh to see their version before
					saving yours.
				</p>
			{/if}
			{#if errorMessage}
				<p class="pipeline-settings__error" role="alert">{errorMessage}</p>
			{/if}

			{#if detailed !== null}
				{@const d = detailed}
				<SectionBlock
					title="Assessment column"
					hint="How the board groups the three assessment stages for everyone in this organization."
					form
					level={3}
				>
					<Toggle
						id="pipeline-detailed-toggle"
						label="Show assessment stages as separate columns"
						description={d
							? 'The board shows Unscheduled, Scheduled, and Completed as three columns.'
							: 'The board shows one Assessment column, with each card’s state on the card itself.'}
						checked={d}
						disabled={!canEdit}
						labelSide="start"
						onchange={(checked) => (detailed = checked)}
					/>
				</SectionBlock>
			{/if}
		{/snippet}

		{#snippet actions()}
			{#if canEdit}
				<Button variant="secondary" onclick={cancel} disabled={!dirty || saving}>Cancel</Button>
				<Button onclick={save} disabled={!dirty || saving} loading={saving}>Save</Button>
			{/if}
		{/snippet}
	</RecordFormLayout>
{/if}

<style lang="scss">
	.pipeline-settings {
		&__readonly {
			padding: var(--space-base);
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-base);
			color: var(--color-text--secondary);
			background: var(--color-surface--background);
			font-size: var(--typography--fontSize-small);
		}
		&__conflict {
			display: flex;
			align-items: center;
			gap: var(--space-small);
			padding: var(--space-base);
			border-radius: var(--radius-base);
			color: var(--color-warning--onSurface);
			background: var(--color-warning--surface);
			font-size: var(--typography--fontSize-small);
		}
		&__conflict :global(svg) {
			width: 18px;
			height: 18px;
			flex: 0 0 auto;
		}
		&__error {
			margin: 0;
			padding: var(--space-base);
			border-radius: var(--radius-base);
			color: var(--color-critical--onSurface);
			background: var(--color-critical--surface);
			font-size: var(--typography--fontSize-small);
		}
	}
</style>
