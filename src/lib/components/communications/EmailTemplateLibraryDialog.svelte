<script lang="ts">
	import { createQuery } from '@tanstack/svelte-query';
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Badge from '$lib/components/ui/Badge.svelte';
	import EmptyState from '$lib/components/data-display/EmptyState.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import {
		communicationEmailTemplateLibraryKey,
		copyCommunicationEmailTemplate,
		fetchCommunicationEmailTemplateLibrary,
		EmailTemplateWriteError,
		type CommunicationEmailTemplate
	} from '$lib/communications/email-templates';
	import fileTextIcon from '@tabler/icons/outline/file-text.svg?raw';

	// Jafar's platform library, filtered server-side to what this organization's package includes. A copy
	// snapshots subject/body once; it never becomes a live link, so "Added" here just means a copy exists --
	// spotting a newer platform version and adopting it happens from the org's own list, not from here.
	let {
		open,
		onCopied,
		onClose
	}: {
		open: boolean;
		onCopied: (template: CommunicationEmailTemplate) => void;
		onClose: () => void;
	} = $props();

	let copyingId = $state<string | null>(null);
	let copyError = $state('');

	const libraryQuery = createQuery(() => ({
		queryKey: communicationEmailTemplateLibraryKey,
		queryFn: fetchCommunicationEmailTemplateLibrary,
		enabled: open,
		staleTime: 30_000
	}));

	async function copy(templateId: string) {
		if (copyingId) return;
		copyingId = templateId;
		copyError = '';
		try {
			const template = await copyCommunicationEmailTemplate(templateId);
			onCopied(template);
		} catch (cause) {
			copyError =
				cause instanceof EmailTemplateWriteError
					? cause.message
					: 'That template could not be copied.';
		} finally {
			copyingId = null;
		}
	}
</script>

<Dialog {open} title="Copy from the template library" size="large" {onClose}>
	<div class="email-template-library">
		{#if copyError}<p class="email-template-library__error" role="alert">{copyError}</p>{/if}

		{#if libraryQuery.isPending}
			<LoadingSkeleton variant="table" label="Loading the template library" rows={4} />
		{:else if libraryQuery.isError}
			<ErrorState
				description="The template library could not be loaded."
				retry={() => libraryQuery.refetch()}
			/>
		{:else if libraryQuery.data.length === 0}
			<EmptyState
				icon={fileTextIcon}
				title="No templates in your plan yet"
				description="Templates included in your current package will appear here."
			/>
		{:else}
			<ul class="email-template-library__list">
				{#each libraryQuery.data as item (item.id)}
					<li class="email-template-library__item">
						<div class="email-template-library__copy">
							<div class="email-template-library__heading">
								<strong>{item.name}</strong>
								{#if item.folder}<Badge size="small">{item.folder}</Badge>{/if}
								{#if item.update_available}
									<Badge size="small" status="warning">Update available</Badge>
								{/if}
							</div>
							<span class="email-template-library__subject">{item.subject}</span>
						</div>
						{#if item.copied_template_id}
							<Button variant="secondary" variation="subtle" disabled>Added</Button>
						{:else}
							<Button
								variant="secondary"
								loading={copyingId === item.id}
								disabled={copyingId !== null}
								onclick={() => copy(item.id)}
							>
								Copy
							</Button>
						{/if}
					</li>
				{/each}
			</ul>
		{/if}
	</div>
</Dialog>

<style lang="scss">
	/* Dialog content is portaled out of this component's subtree, so its styles have to be global. */
	:global(.email-template-library) {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);
	}
	:global(.email-template-library__error) {
		padding: var(--space-small) var(--space-base);
		border-radius: var(--radius-base);
		color: var(--color-critical--onSurface);
		background: var(--color-critical--surface);
		font-size: var(--typography--fontSize-small);
	}
	:global(.email-template-library__list) {
		display: flex;
		flex-direction: column;
		gap: var(--space-small);
		margin: 0;
		padding: 0;
		list-style: none;
	}
	:global(.email-template-library__item) {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-base);
		padding: var(--space-small) var(--space-base);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
	}
	:global(.email-template-library__copy) {
		display: flex;
		flex-direction: column;
		gap: var(--space-smallest);
		min-width: 0;
	}
	:global(.email-template-library__heading) {
		display: flex;
		align-items: center;
		gap: var(--space-smaller);
	}
	:global(.email-template-library__subject) {
		overflow: hidden;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		text-overflow: ellipsis;
		white-space: nowrap;
	}
</style>
