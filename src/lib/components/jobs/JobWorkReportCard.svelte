<script lang="ts">
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import RailCard from '$lib/components/layout/RailCard.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Badge from '$lib/components/ui/Badge.svelte';
	import EmptyState from '$lib/components/data-display/EmptyState.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import EditJobReportDialog from '$lib/components/jobs/EditJobReportDialog.svelte';
	import {
		fetchJobReportState,
		issueJobReportAccessLink,
		jobReportStateKey,
		saveJobReport,
		type JobReportApiError,
		type SaveJobReportInput
	} from '$lib/jobs/report-api';
	import { resolve } from '$app/paths';
	import fileReportIcon from '@tabler/icons/outline/file-report.svg?raw';

	// The living picture handed to a customer of what was done: photos, checklist answers and the work list,
	// gathered from what already exists on the job rather than anything typed fresh here. There is no
	// snapshot — un-checking a photo fixes every link already sent, the moment it is saved.

	let {
		jobId,
		onStateChange
	}: {
		jobId: string;
		/** Tells the page's own "···" menu whether Preview / Print / Copy work report link belong there. */
		onStateChange?: (hasContent: boolean) => void;
	} = $props();

	const queryClient = useQueryClient();
	const toast = getToastManager();

	let editing = $state(false);
	let saving = $state(false);
	let linkSaving = $state(false);

	const stateQuery = createQuery(() => ({
		queryKey: jobReportStateKey(jobId),
		queryFn: () => fetchJobReportState(jobId),
		enabled: Boolean(jobId)
	}));

	const saved = $derived(stateQuery.data);
	const hasContent = $derived(Boolean(saved?.has_content));

	$effect(() => {
		onStateChange?.(hasContent);
	});

	async function refresh() {
		await queryClient.invalidateQueries({ queryKey: jobReportStateKey(jobId) });
	}

	async function save(input: SaveJobReportInput) {
		saving = true;
		try {
			await saveJobReport(jobId, input);
			await refresh();
			toast.success('Work report saved');
		} finally {
			saving = false;
		}
	}

	export async function copyLink() {
		if (linkSaving) return;
		linkSaving = true;
		try {
			const link = await issueJobReportAccessLink(jobId);
			await navigator.clipboard.writeText(link.url);
			toast.success(`Link copied. Send it to ${link.recipient_email}.`);
		} catch (caught) {
			toast.error((caught as JobReportApiError).message ?? 'That link could not be created.');
		} finally {
			linkSaving = false;
		}
	}

	export function openPreview(print = false) {
		const path = resolve('/(app)/jobs/[id]/report/preview', { id: jobId });
		window.open(print ? `${path}?print=1` : path, '_blank', 'noopener');
	}

	const summaryText = $derived.by(() => {
		if (!saved) return '';
		const parts: string[] = [];
		if (saved.report.photo_ids.length) {
			parts.push(
				`${saved.report.photo_ids.length} photo${saved.report.photo_ids.length === 1 ? '' : 's'}`
			);
		}
		if (saved.report.checklist.length) {
			parts.push(
				`${saved.report.checklist.length} checklist answer${saved.report.checklist.length === 1 ? '' : 's'}`
			);
		}
		if (saved.report.include_service_details) parts.push('work list');
		return parts.join(' · ');
	});
</script>

<RailCard title="Work report" icon={fileReportIcon}>
	{#snippet actions()}
		<Button size="small" variant="tertiary" onclick={() => (editing = true)}>Edit report</Button>
	{/snippet}

	{#if stateQuery.isPending}
		<LoadingSkeleton variant="text" rows={2} label="Loading the work report" />
	{:else if stateQuery.isError}
		<p class="job-work-report__error" role="alert">The work report could not be loaded.</p>
	{:else if !hasContent}
		<EmptyState
			icon={fileReportIcon}
			title="No work report yet"
			description="Choose photos, checklist answers or the work list to share with the customer."
		/>
	{:else}
		<div class="job-work-report__summary">
			<Badge size="small" status="success">Ready to share</Badge>
			{#if summaryText}<p class="job-work-report__detail">{summaryText}</p>{/if}
		</div>
	{/if}
</RailCard>

{#if editing && saved}
	<EditJobReportDialog
		open
		jobReport={saved}
		{saving}
		onClose={() => (editing = false)}
		onSave={async (input) => {
			await save(input);
			editing = false;
		}}
	/>
{/if}

<style lang="scss">
	.job-work-report {
		&__summary {
			display: flex;
			flex-direction: column;
			gap: var(--space-smaller);
			align-items: flex-start;
		}

		&__detail {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__error {
			margin: 0;
			color: var(--color-critical);
		}
	}
</style>
