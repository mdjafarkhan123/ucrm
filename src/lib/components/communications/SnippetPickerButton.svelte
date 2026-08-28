<script lang="ts">
	import { Popover } from 'bits-ui';
	import { createQuery } from '@tanstack/svelte-query';
	import SearchInput from '$lib/components/ui/SearchInput.svelte';
	import {
		communicationSnippetsKey,
		fetchCommunicationSnippets,
		type CommunicationSnippet
	} from '$lib/communications/snippets';
	import notesIcon from '@tabler/icons/outline/notes.svg?raw';

	// The composer's snippet trigger: shared by ConversationComposer and WebsiteChatComposer so both reply
	// paths insert reusable text the same way. Snippets stay editable after insert (contract requirement) --
	// this only ever appends to the caller's draft, never owns it.
	let { disabled = false, onInsert }: { disabled?: boolean; onInsert: (body: string) => void } =
		$props();

	let open = $state(false);
	let search = $state('');
	const normalizedSearch = $derived(search.trim().toLowerCase());

	// A business's snippet library is a bounded handful of rows (see the migration), so one page covers it
	// -- loaded only once the picker is actually opened, matching every other revealed-on-hover query.
	const snippetsQuery = createQuery(() => ({
		queryKey: communicationSnippetsKey(),
		queryFn: () => fetchCommunicationSnippets(),
		enabled: open,
		staleTime: 30_000
	}));
	const snippets = $derived(snippetsQuery.data?.items ?? []);
	const filtered = $derived(
		normalizedSearch
			? snippets.filter(
					(item) =>
						item.title.toLowerCase().includes(normalizedSearch) ||
						item.body.toLowerCase().includes(normalizedSearch)
				)
			: snippets
	);

	function prefetch() {
		// Hovering the trigger warms the query the same way a link hover warms a route -- open still
		// shows a skeleton if the click wins the race, but usually it will not have to.
		void snippetsQuery.refetch();
	}

	function insert(snippet: CommunicationSnippet) {
		onInsert(snippet.body);
		open = false;
		search = '';
	}
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<Popover.Root bind:open>
	<Popover.Trigger
		class="snippet-picker__trigger"
		aria-label="Insert a snippet"
		title="Insert a snippet"
		{disabled}
		onpointerenter={prefetch}
	>
		{@html notesIcon}
	</Popover.Trigger>
	<Popover.Portal>
		<Popover.Content
			class="snippet-picker__popover"
			align="start"
			sideOffset={8}
			collisionPadding={12}
		>
			<SearchInput
				id="snippet-picker-search"
				bind:value={search}
				placeholder="Find a snippet"
				ariaLabel="Search snippets"
			/>
			<div class="snippet-picker__options">
				{#if snippetsQuery.isPending}
					<p class="snippet-picker__empty">Loading…</p>
				{:else if filtered.length === 0}
					<p class="snippet-picker__empty">
						{normalizedSearch ? 'No matching snippets.' : 'No snippets yet.'}
					</p>
				{:else}
					{#each filtered as snippet (snippet.id)}
						<button type="button" class="snippet-picker__option" onclick={() => insert(snippet)}>
							<span class="snippet-picker__option-title">
								{snippet.title}
								{#if snippet.folder}<span class="snippet-picker__option-folder"
										>{snippet.folder}</span
									>{/if}
							</span>
							<span class="snippet-picker__option-preview">{snippet.body}</span>
						</button>
					{/each}
				{/if}
			</div>
		</Popover.Content>
	</Popover.Portal>
</Popover.Root>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	:global(.snippet-picker__trigger) {
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

	:global(.snippet-picker__trigger[data-state='open']) {
		color: var(--color-interactive--subtle--hover);
		background: var(--color-surface--active);
	}

	:global(.snippet-picker__popover) {
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

	.snippet-picker__options {
		display: flex;
		max-height: 280px;
		flex-direction: column;
		gap: 2px;
		overflow-y: auto;
	}

	.snippet-picker__option {
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

	.snippet-picker__option-title {
		display: flex;
		align-items: center;
		gap: var(--space-smaller);
		color: var(--color-heading);
		font-size: var(--typography--fontSize-small);
		font-weight: 600;
	}

	.snippet-picker__option-folder {
		padding: 1px var(--space-smaller);
		border-radius: var(--radius-small);
		color: var(--color-text--secondary);
		background: var(--color-inactive--surface);
		font-size: var(--typography--fontSize-smaller);
		font-weight: 400;
	}

	.snippet-picker__option-preview {
		overflow: hidden;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-smaller);
		text-overflow: ellipsis;
		white-space: nowrap;
	}

	.snippet-picker__empty {
		padding: var(--space-small) 0;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}
</style>
