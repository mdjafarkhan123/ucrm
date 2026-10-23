<script lang="ts">
	import { Popover } from 'bits-ui';
	import { createQuery } from '@tanstack/svelte-query';
	import Button from '$lib/components/ui/Button.svelte';
	import SearchInput from '$lib/components/ui/SearchInput.svelte';
	import {
		communicationSnippetsKey,
		fetchCommunicationSnippets,
		type CommunicationSnippet
	} from '$lib/communications/snippets';
	import notesIcon from '@tabler/icons/outline/bolt.svg?raw';

	// The composer's snippet trigger, shared by every channel ConversationComposer renders so reusable text
	// inserts the same way everywhere. Snippets stay editable after insert (contract requirement) -- this
	// only ever appends to the caller's draft, never owns it.
	let {
		disabled = false,
		triggerVariant = 'secondary',
		onInsert
	}: {
		disabled?: boolean;
		/** `quiet` in the inbox reply box's tool bar, where the tools sit on the box itself. */
		triggerVariant?: 'secondary' | 'quiet';
		onInsert: (body: string) => void;
	} = $props();

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
	<Popover.Trigger>
		{#snippet child({ props })}
			<Button
				{...props}
				variant={triggerVariant}
				size="small"
				iconOnly
				label="Insert a snippet"
				{disabled}
				onhover={prefetch}
			>
				{@html notesIcon}
			</Button>
		{/snippet}
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
				{:else if snippetsQuery.isError}
					<p class="snippet-picker__empty" role="alert">Snippets could not be loaded.</p>
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
