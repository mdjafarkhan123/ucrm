<script lang="ts">
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import SearchInput from '$lib/components/ui/SearchInput.svelte';
	import EmptyState from '$lib/components/data-display/EmptyState.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import searchIcon from '@tabler/icons/outline/search.svg?raw';
	import { fetchGlobalSearch, type GlobalSearchResult } from '$lib/search/api';
	import { attachFilesToRecord, type FileEntityType } from '$lib/files/api';

	// The other direction of reuse: the file is already chosen, and what is missing is the record. It reads
	// the app's existing global search rather than growing a record search of its own, so "3108", "King
	// Street" and a customer's name all find what the contractor means here exactly as they do in the top bar.
	let {
		open,
		fileId,
		fileName,
		onClose,
		onAttached
	}: {
		open: boolean;
		fileId: string;
		fileName: string;
		onClose: () => void;
		onAttached?: () => void;
	} = $props();

	const queryClient = useQueryClient();
	const uid = $props.id();

	// Only the record types a File can actually be attached to. Invoices and conversations come back from
	// the same search and are left out here, because a File cannot be linked to either one yet.
	const ATTACHABLE_GROUPS = [
		{ key: 'clients', heading: 'Clients', entityType: 'client' },
		{ key: 'requests', heading: 'Requests', entityType: 'request' },
		{ key: 'quotes', heading: 'Quotes', entityType: 'quote' },
		{ key: 'jobs', heading: 'Jobs', entityType: 'job' }
	] as const;

	let query = $state('');
	let debouncedQuery = $state('');
	let attachingId = $state('');
	let attachError = $state('');
	let attachedTo = $state('');

	$effect(() => {
		const value = query;
		const handle = setTimeout(() => (debouncedQuery = value.trim()), 300);
		return () => clearTimeout(handle);
	});

	// Two characters is the server's own minimum, so asking sooner only produces a refusal.
	const canSearch = $derived(debouncedQuery.length >= 2);
	const searchQuery = createQuery(() => ({
		queryKey: ['files', 'attach-search', debouncedQuery],
		queryFn: () => fetchGlobalSearch(debouncedQuery),
		enabled: open && canSearch
	}));

	const groups = $derived(
		ATTACHABLE_GROUPS.map((group) => ({
			...group,
			results: searchQuery.data?.groups[group.key] ?? []
		})).filter((group) => group.results.length > 0)
	);
	const noResults = $derived(canSearch && searchQuery.isSuccess && groups.length === 0);

	async function attach(result: GlobalSearchResult, entityType: FileEntityType) {
		if (attachingId) return;
		attachingId = result.id;
		attachError = '';
		attachedTo = '';
		try {
			const outcome = await attachFilesToRecord([fileId], entityType, result.id);
			if (outcome.refused.length > 0) {
				attachError = outcome.refused[0].reason;
				return;
			}
			attachedTo = result.title;
			void queryClient.invalidateQueries({ queryKey: ['files', 'list'] });
			void queryClient.invalidateQueries({ queryKey: ['files', 'detail'] });
			onAttached?.();
		} catch (error) {
			attachError = error instanceof Error ? error.message : 'That file could not be attached.';
		} finally {
			attachingId = '';
		}
	}

	function handleClose() {
		query = '';
		debouncedQuery = '';
		attachError = '';
		attachedTo = '';
		onClose();
	}
</script>

<Dialog {open} title="Attach to a record" size="default" onClose={handleClose}>
	<div class="attach-to">
		<p class="attach-to__lead">
			Find the customer, request, quote or job that <strong>{fileName}</strong> belongs on. The file stays
			in your library — this just adds it there as well.
		</p>

		<SearchInput
			id={`${uid}-search`}
			bind:value={query}
			placeholder="Customer name, address, job or quote number"
		/>

		{#if attachedTo}
			<p class="attach-to__success" role="status">Added to {attachedTo}.</p>
		{/if}
		{#if attachError}
			<p class="attach-to__error" role="alert">{attachError}</p>
		{/if}

		{#if !canSearch}
			<p class="attach-to__hint">Type at least two letters to start searching.</p>
		{:else if searchQuery.isPending}
			<LoadingSkeleton variant="text" label="Searching" rows={3} />
		{:else if searchQuery.isError}
			<p class="attach-to__error" role="alert">We could not search right now. Try again.</p>
		{:else if noResults}
			<EmptyState
				icon={searchIcon}
				title="Nothing matched"
				description="Try the customer's name, the address, or the job or quote number."
			/>
		{:else}
			<div class="attach-to__results">
				{#each groups as group (group.key)}
					<section class="attach-to__group">
						<h3 class="attach-to__group-heading">{group.heading}</h3>
						<ul class="attach-to__list">
							{#each group.results as result (result.id)}
								<li>
									<button
										type="button"
										class="attach-to__result"
										disabled={attachingId !== ''}
										onclick={() => attach(result, group.entityType)}
									>
										<span class="attach-to__result-title">{result.title}</span>
										{#if result.subtitle}
											<span class="attach-to__result-subtitle">{result.subtitle}</span>
										{/if}
									</button>
								</li>
							{/each}
						</ul>
					</section>
				{/each}
			</div>
		{/if}

		<div class="attach-to__actions">
			<Button variant="secondary" variation="subtle" onclick={handleClose}>Done</Button>
		</div>
	</div>
</Dialog>

<style lang="scss">
	.attach-to {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);
	}
	.attach-to__lead,
	.attach-to__hint {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}
	.attach-to__lead strong {
		color: var(--color-heading);
	}
	.attach-to__success {
		color: var(--color-success);
		font-size: var(--typography--fontSize-small);
		font-weight: 600;
	}
	.attach-to__error {
		color: var(--color-critical);
		font-size: var(--typography--fontSize-small);
	}

	.attach-to__results {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);
		max-height: 44vh;
		overflow-y: auto;
	}
	.attach-to__group-heading {
		margin-bottom: var(--space-smaller);
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		font-weight: 700;
		text-transform: uppercase;
		letter-spacing: 0.04em;
	}
	.attach-to__list {
		display: flex;
		flex-direction: column;
		gap: var(--space-smallest);
		list-style: none;
	}
	.attach-to__result {
		display: flex;
		width: 100%;
		flex-direction: column;
		gap: 2px;
		padding: var(--space-small);
		border: none;
		border-radius: var(--radius-base);
		background: transparent;
		text-align: start;
		cursor: pointer;

		&:hover {
			background: var(--color-surface--hover);
		}
		&:focus-visible {
			outline: none;
			box-shadow: var(--shadow-focus);
		}
		&:disabled {
			cursor: wait;
			opacity: 0.6;
		}
	}
	.attach-to__result-title {
		color: var(--color-heading);
		font-size: var(--typography--fontSize-base);
		font-weight: 600;
	}
	.attach-to__result-subtitle {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}

	.attach-to__actions {
		display: flex;
		justify-content: flex-end;
	}
</style>
