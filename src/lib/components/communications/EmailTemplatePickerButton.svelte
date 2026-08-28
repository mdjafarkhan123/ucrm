<script lang="ts">
	import { Popover } from 'bits-ui';
	import { createQuery } from '@tanstack/svelte-query';
	import SearchInput from '$lib/components/ui/SearchInput.svelte';
	import {
		communicationEmailTemplatesKey,
		fetchCommunicationEmailTemplates,
		type CommunicationEmailTemplateListItem
	} from '$lib/communications/email-templates';
	import templateIcon from '@tabler/icons/outline/template.svg?raw';

	// The composer's template trigger. Unlike a snippet, a template carries both subject and body and is
	// meant to seed the whole draft -- so this hands the caller the full template and lets the composer
	// decide whether to confirm before overwriting text the user already started.
	let {
		disabled = false,
		onApply
	}: {
		disabled?: boolean;
		onApply: (template: CommunicationEmailTemplateListItem) => void;
	} = $props();

	let open = $state(false);
	let search = $state('');
	const normalizedSearch = $derived(search.trim().toLowerCase());

	// A business's template library is its own copy-on-write list (see the migration) -- a bounded handful of
	// rows, so one page covers it, loaded only once the picker opens like every other revealed-on-hover query.
	const templatesQuery = createQuery(() => ({
		queryKey: communicationEmailTemplatesKey(),
		queryFn: () => fetchCommunicationEmailTemplates(),
		enabled: open,
		staleTime: 30_000
	}));
	const templates = $derived(templatesQuery.data?.items ?? []);
	const filtered = $derived(
		normalizedSearch
			? templates.filter(
					(item) =>
						item.name.toLowerCase().includes(normalizedSearch) ||
						item.subject.toLowerCase().includes(normalizedSearch) ||
						item.body.toLowerCase().includes(normalizedSearch)
				)
			: templates
	);

	function prefetch() {
		// Hovering the trigger warms the query the same way a link hover warms a route.
		void templatesQuery.refetch();
	}

	function apply(template: CommunicationEmailTemplateListItem) {
		onApply(template);
		open = false;
		search = '';
	}
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<Popover.Root bind:open>
	<Popover.Trigger
		class="email-template-picker__trigger"
		aria-label="Use an email template"
		title="Use an email template"
		{disabled}
		onpointerenter={prefetch}
	>
		{@html templateIcon}
	</Popover.Trigger>
	<Popover.Portal>
		<Popover.Content
			class="email-template-picker__popover"
			align="start"
			sideOffset={8}
			collisionPadding={12}
		>
			<SearchInput
				id="email-template-picker-search"
				bind:value={search}
				placeholder="Find a template"
				ariaLabel="Search templates"
			/>
			<div class="email-template-picker__options">
				{#if templatesQuery.isPending}
					<p class="email-template-picker__empty">Loading…</p>
				{:else if filtered.length === 0}
					<p class="email-template-picker__empty">
						{normalizedSearch ? 'No matching templates.' : 'No templates yet.'}
					</p>
				{:else}
					{#each filtered as template (template.id)}
						<button
							type="button"
							class="email-template-picker__option"
							onclick={() => apply(template)}
						>
							<span class="email-template-picker__option-title">
								{template.name}
								{#if template.folder}<span class="email-template-picker__option-folder"
										>{template.folder}</span
									>{/if}
							</span>
							<span class="email-template-picker__option-preview">{template.subject}</span>
						</button>
					{/each}
				{/if}
			</div>
		</Popover.Content>
	</Popover.Portal>
</Popover.Root>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	:global(.email-template-picker__trigger) {
		display: inline-flex;
		box-sizing: border-box;
		flex: 0 0 auto;
		align-items: center;
		justify-content: center;
		width: var(--space-larger);
		height: var(--space-larger);
		border: var(--border-base) solid transparent;
		border-radius: var(--radius-base);
		color: var(--color-interactive--subtle);
		background: transparent;
		cursor: pointer;
		transition: all var(--timing-base) ease-out;

		:global(svg) {
			display: block;
			width: 20px;
			height: 20px;
		}

		&:hover:not(:disabled),
		&:focus-visible:not(:disabled) {
			color: var(--color-interactive--subtle--hover);
			background: var(--color-surface--hover);
		}

		&:focus-visible {
			outline: none;
			box-shadow: var(--shadow-focus);
		}

		&:disabled {
			color: var(--color-disabled);
			cursor: not-allowed;
		}
	}

	:global(.email-template-picker__trigger[data-state='open']) {
		color: var(--color-interactive--subtle--hover);
		background: var(--color-surface--active);
	}

	:global(.email-template-picker__popover) {
		z-index: var(--elevation-tooltip);
		display: flex;
		width: min(320px, calc(100vw - var(--space-large) * 2));
		flex-direction: column;
		gap: var(--space-small);
		padding: var(--space-base);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface);
		box-shadow: var(--shadow-base);
	}

	.email-template-picker__options {
		display: flex;
		max-height: 280px;
		flex-direction: column;
		gap: 2px;
		overflow-y: auto;
	}

	.email-template-picker__option {
		display: flex;
		flex-direction: column;
		gap: 2px;
		padding: var(--space-small);
		border: 0;
		border-radius: var(--radius-small);
		background: transparent;
		text-align: left;
		cursor: pointer;
		transition: background-color var(--timing-quick);

		&:hover,
		&:focus-visible {
			background: var(--color-surface--hover);
		}

		&:focus-visible {
			outline: none;
		}
	}

	.email-template-picker__option-title {
		display: flex;
		align-items: center;
		gap: var(--space-smaller);
		color: var(--color-heading);
		font-size: var(--typography--fontSize-small);
		font-weight: 600;
	}

	.email-template-picker__option-folder {
		padding: 1px var(--space-smaller);
		border-radius: var(--radius-small);
		color: var(--color-text--secondary);
		background: var(--color-inactive--surface);
		font-size: var(--typography--fontSize-smaller);
		font-weight: 400;
	}

	.email-template-picker__option-preview {
		overflow: hidden;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-smaller);
		text-overflow: ellipsis;
		white-space: nowrap;
	}

	.email-template-picker__empty {
		padding: var(--space-small) 0;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}
</style>
