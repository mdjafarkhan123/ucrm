<script lang="ts">
	import { createQuery } from '@tanstack/svelte-query';
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import PhotoDescribeForm from './PhotoDescribeForm.svelte';
	import { fetchFile, fileDetailKey, fileImageUrl } from '$lib/files/api';

	// The caption and labels of one photo, opened from a record's Files card -- the way a crew member on a job
	// reaches them, since they have no File Manager. Same query key as the File Manager's details panel, so
	// the hover prefetch on the tile usually means this paints with nothing to wait for.
	let {
		fileId,
		fileName,
		open,
		onClose
	}: { fileId: string | null; fileName: string; open: boolean; onClose: () => void } = $props();

	const detailQuery = createQuery(() => ({
		queryKey: fileDetailKey(fileId ?? ''),
		queryFn: () => fetchFile(fileId!),
		enabled: open && Boolean(fileId)
	}));
</script>

<Dialog {open} title="Caption and labels" size="small" {onClose}>
	<div class="photo-describe-dialog">
		{#if fileId}
			<img
				class="photo-describe-dialog__image"
				src={fileImageUrl(fileId, 'thumb')}
				alt={fileName}
			/>
		{/if}
		{#if detailQuery.isPending}
			<LoadingSkeleton variant="text" label="Loading caption and labels" rows={3} />
		{:else if detailQuery.isError || !detailQuery.data}
			<ErrorState
				description="This photo's details could not be loaded."
				retry={() => detailQuery.refetch()}
			/>
		{:else if !detailQuery.data.can_describe && !detailQuery.data.file.caption && detailQuery.data.file.labels.length === 0}
			<p class="photo-describe-dialog__empty">No caption or labels yet.</p>
		{:else}
			<PhotoDescribeForm detail={detailQuery.data} onSaved={onClose} />
		{/if}
	</div>
</Dialog>

<style lang="scss">
	.photo-describe-dialog {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);

		&__image {
			display: block;
			width: 100%;
			max-height: 200px;
			object-fit: contain;
			border-radius: var(--radius-base);
			background: var(--color-surface--background);
		}

		&__empty {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}
	}
</style>
