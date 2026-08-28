<script lang="ts">
	import Badge from '$lib/components/ui/Badge.svelte';
	import { formatFileSize } from '$lib/collaboration/format';
	import { iconForMimeType } from '$lib/collaboration/file-icons';
	import type { InboxAttachment, OutboundAttachment } from '$lib/communications/inbox';
	import downloadIcon from '@tabler/icons/outline/download.svg?raw';

	// Shared read-only file list for the timeline: an inbound message's received files (with the
	// import/scan status ladder) or an outbound message's already-sent files (no status column -- a row
	// exists only once a file sent successfully, so it is always available). The caller supplies which
	// download route to call, keeping this component itself unaware of inbound vs outbound routing.
	let {
		attachments,
		fetchDownloadUrl
	}: {
		attachments: (InboxAttachment | OutboundAttachment)[];
		fetchDownloadUrl: (attachmentId: string) => Promise<{ download_url: string }>;
	} = $props();

	let downloadError = $state('');
	let downloadingId = $state<string | null>(null);

	// The provider URL never reaches the browser -- every download is authorized here, one file at a time.
	async function download(attachment: InboxAttachment | OutboundAttachment) {
		downloadError = '';
		downloadingId = attachment.id;
		try {
			const { download_url } = await fetchDownloadUrl(attachment.id);
			window.open(download_url, '_blank', 'noopener,noreferrer');
		} catch (error) {
			downloadError = error instanceof Error ? error.message : 'That file could not be downloaded.';
		} finally {
			downloadingId = null;
		}
	}

	function stateOf(attachment: InboxAttachment): {
		label: string;
		tone: 'success' | 'warning' | 'critical' | 'inactive' | 'informative';
	} {
		switch (attachment.status) {
			case 'available':
				return { label: 'Available', tone: 'success' };
			case 'pending_import':
			case 'pending_scan':
				return { label: 'Processing…', tone: 'informative' };
			case 'blocked_type':
				return { label: 'Blocked — unsupported file type', tone: 'warning' };
			case 'blocked_size':
				return { label: 'Blocked — exceeds size limit', tone: 'warning' };
			case 'infected':
				return { label: 'Blocked — flagged as unsafe', tone: 'critical' };
			case 'scan_failed':
				return { label: 'Scan failed', tone: 'critical' };
			default:
				return { label: 'Could not be imported', tone: 'critical' };
		}
	}

	// Outbound has no status column at all -- a row only ever exists once its file sent successfully, so
	// it is always available. Kept as its own function so the 'status' narrowing survives across the
	// separate `state` and `available` template bindings below (narrowing a union in one `{@const}` does
	// not carry over into another).
	function isAvailable(attachment: InboxAttachment | OutboundAttachment): boolean {
		return !('status' in attachment) || attachment.status === 'available';
	}
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
{#if attachments.length > 0}
	<ul class="attachment-list" aria-label="Attachments">
		{#each attachments as attachment (attachment.id)}
			{@const state = 'status' in attachment ? stateOf(attachment) : null}
			{@const available = isAvailable(attachment)}
			<li class="attachment-list__item">
				<span class="attachment-list__icon" aria-hidden="true"
					>{@html iconForMimeType(attachment.mime_type)}</span
				>
				<span class="attachment-list__body">
					<span class="attachment-list__name">{attachment.file_name}</span>
					<span class="attachment-list__meta">
						{formatFileSize(attachment.byte_size)}
						{#if state && !available}
							· <Badge status={state.tone} size="small">{state.label}</Badge>
						{/if}
					</span>
				</span>
				{#if available}
					<button
						type="button"
						class="attachment-list__download"
						disabled={downloadingId === attachment.id}
						onclick={() => download(attachment)}
					>
						<span aria-hidden="true">{@html downloadIcon}</span>
						{downloadingId === attachment.id ? 'Preparing…' : 'Download'}
					</button>
				{/if}
			</li>
		{/each}
	</ul>
	{#if downloadError}<p class="attachment-list__error" role="alert">{downloadError}</p>{/if}
{/if}

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.attachment-list {
		display: flex;
		flex-direction: column;
		gap: var(--space-small);
		margin: 0;
		padding: 0;
		list-style: none;

		&__item {
			display: flex;
			align-items: center;
			gap: var(--space-small);
			padding: var(--space-small) var(--space-base);
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-base);
		}

		&__icon {
			display: grid;
			width: 32px;
			height: 32px;
			flex: 0 0 auto;
			place-items: center;
			border-radius: var(--radius-base);
			color: var(--color-icon);
			background: var(--color-surface--background);

			:global(svg) {
				display: block;
				width: 20px;
				height: 20px;
			}
		}

		&__body {
			display: flex;
			min-width: 0;
			flex: 1 1 auto;
			flex-direction: column;
			gap: 2px;
		}

		&__name {
			overflow: hidden;
			color: var(--color-heading);
			font-size: var(--typography--fontSize-small);
			font-weight: 600;
			text-overflow: ellipsis;
			white-space: nowrap;
		}

		&__meta {
			display: inline-flex;
			align-items: center;
			gap: var(--space-smaller);
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-smaller);
		}

		&__download {
			display: inline-flex;
			flex: 0 0 auto;
			align-items: center;
			gap: var(--space-smaller);
			padding: var(--space-smaller) var(--space-small);
			border: var(--border-base) solid var(--color-border--interactive);
			border-radius: var(--radius-base);
			color: var(--color-interactive--subtle);
			background: transparent;
			font: inherit;
			font-size: var(--typography--fontSize-small);
			cursor: pointer;

			:global(svg) {
				display: block;
				width: 14px;
				height: 14px;
			}

			&:hover:not(:disabled) {
				background: var(--color-interactive--background);
			}

			&:focus-visible {
				outline: none;
				box-shadow: var(--shadow-focus);
			}

			&:disabled {
				color: var(--color-disabled);
				cursor: default;
			}
		}

		&__error {
			margin-top: var(--space-small);
			color: var(--color-critical);
			font-size: var(--typography--fontSize-small);
		}
	}
</style>
