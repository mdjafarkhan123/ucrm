<script lang="ts">
	import { createQuery } from '@tanstack/svelte-query';
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import IconTile from '$lib/components/ui/IconTile.svelte';
	import photoIcon from '@tabler/icons/outline/photo.svg?raw';
	import alertTriangleIcon from '@tabler/icons/outline/alert-triangle.svg?raw';
	import refreshIcon from '@tabler/icons/outline/refresh.svg?raw';
	import quoteIcon from '@tabler/icons/outline/quote.svg?raw';
	import PhotoDescribeForm from './PhotoDescribeForm.svelte';
	import { fetchFile, fileDetailKey, fileImageUrl } from '$lib/files/api';

	// The caption and labels of one photo, opened from a record's Files card -- the way a crew member on a job
	// reaches them, since they have no File Manager. Same query key as the File Manager's details panel, so
	// the hover prefetch on the tile usually means this paints with nothing to wait for.
	let {
		fileId,
		fileName,
		recordName,
		open,
		onClose
	}: {
		fileId: string | null;
		fileName: string;
		/** The record the photo is on, after the file name in the hint line. */
		recordName?: string;
		open: boolean;
		onClose: () => void;
	} = $props();

	const detailQuery = createQuery(() => ({
		queryKey: fileDetailKey(fileId ?? ''),
		queryFn: () => fetchFile(fileId!),
		enabled: open && Boolean(fileId)
	}));
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<Dialog
	{open}
	title="Caption and labels"
	subtitle={[fileName, recordName].filter(Boolean).join(' · ')}
	icon={photoIcon}
	iconTone="inactive"
	size="small"
	{onClose}
>
	<div class="photo-describe-dialog">
		{#if fileId}
			<img
				class="photo-describe-dialog__image"
				src={fileImageUrl(fileId, 'thumb')}
				alt={fileName}
			/>
		{/if}
		{#if detailQuery.isPending}
			<div class="photo-describe-dialog__loading" role="status" aria-label="Loading caption and labels">
				<span class="skeleton photo-describe-dialog__bone-caption"></span>
				<span class="skeleton photo-describe-dialog__bone-label"></span>
				<span class="photo-describe-dialog__bone-tags">
					{#each [0, 1, 2] as bone (bone)}<span class="skeleton photo-describe-dialog__bone-tag"
						></span>{/each}
				</span>
			</div>
		{:else if detailQuery.isError || !detailQuery.data}
			<div class="photo-describe-dialog__failed" role="alert">
				<IconTile icon={alertTriangleIcon} tone="critical" size={32} />
				<p class="photo-describe-dialog__failed-title">Couldn't load the caption and labels</p>
				<p class="photo-describe-dialog__failed-hint">Check your connection, then try again.</p>
				<Button
					size="small"
					variant="secondary"
					loading={detailQuery.isFetching}
					onclick={() => detailQuery.refetch()}
				>
					{@html refreshIcon}Try again
				</Button>
			</div>
		{:else if !detailQuery.data.can_describe && !detailQuery.data.file.caption && detailQuery.data.file.labels.length === 0}
			<p class="photo-describe-dialog__empty">
				<span aria-hidden="true">{@html quoteIcon}</span>No caption or labels yet.
			</p>
		{:else}
			<PhotoDescribeForm detail={detailQuery.data} inDialog onSaved={onClose} />
		{/if}
	</div>
</Dialog>

<style lang="scss">
	.photo-describe-dialog {
		display: flex;
		flex-direction: column;
		gap: 14px;

		&__image {
			display: block;
			width: 100%;
			height: 200px;
			box-sizing: border-box;
			object-fit: cover;
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-base);
			background: var(--color-surface--background);
		}

		&__loading {
			display: flex;
			flex-direction: column;
			gap: 14px;
		}

		&__bone-caption {
			height: 46px;
			min-height: 0;
			border-radius: var(--radius-base);
		}

		&__bone-label {
			width: 56px;
			height: 12px;
			min-height: 0;
		}

		&__bone-tags {
			display: flex;
			gap: var(--space-small);
		}

		&__bone-tag {
			width: 72px;
			height: 28px;
			min-height: 0;
			border-radius: var(--radius-circle);
		}

		&__failed {
			display: flex;
			flex-direction: column;
			align-items: center;
			gap: 10px;
			padding: var(--space-base);
			border-radius: var(--radius-base);
			background: var(--color-surface--background--subtle);
			text-align: center;
		}

		&__failed-title {
			margin: 0;
			color: var(--color-heading);
			font-size: var(--typography--fontSize-base);
			font-weight: 600;
		}

		&__failed-hint {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__empty {
			display: flex;
			align-items: center;
			gap: 10px;
			margin: 0;
			padding: var(--space-slim) 14px;
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-base);
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-base);

			:global(svg) {
				display: block;
				width: 16px;
				height: 16px;
				color: var(--color-icon--secondary);
			}
		}
	}
</style>
