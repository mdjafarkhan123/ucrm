<script lang="ts">
	import { createQuery } from '@tanstack/svelte-query';
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import SearchInput from '$lib/components/ui/SearchInput.svelte';
	import Avatar from '$lib/components/ui/Avatar.svelte';
	import { fetchClients, type ClientListItem } from '$lib/clients/api';
	import linkIcon from '@tabler/icons/outline/link.svg?raw';
	import pickedIcon from '@tabler/icons/filled/circle-check.svg?raw';

	// "Is this someone you already know?" (design `inbox.md`, Unknown customer). A Messenger customer arrives as a
	// new lead; when the team recognises them, linking merges that lead into the real client, the way Jobber's
	// Merge client does, so the conversation and the Messenger link move onto them. The page runs the merge.
	let {
		open,
		leadId,
		pending = false,
		errorMessage = '',
		onCancel,
		onConfirm
	}: {
		open: boolean;
		/** The lead Messenger created; left out of the list, since it can't be linked to itself. */
		leadId: string;
		pending?: boolean;
		errorMessage?: string;
		onCancel: () => void;
		onConfirm: (client: { id: string; name: string }) => void;
	} = $props();

	let search = $state('');
	let debounced = $state('');
	let picked = $state<ClientListItem | null>(null);

	$effect(() => {
		const term = search.trim();
		const timer = setTimeout(() => (debounced = term), 250);
		return () => clearTimeout(timer);
	});

	const clientsQuery = createQuery(() => ({
		queryKey: ['clients', 'link-picker', debounced],
		queryFn: () =>
			fetchClients({ search: debounced, status: '', tagId: '', sort: 'updated_at', dir: 'desc' }),
		staleTime: 30_000
	}));
	const clients = $derived(
		(clientsQuery.data?.clients ?? []).filter((client) => client.id !== leadId).slice(0, 6)
	);

	function place(client: ClientListItem) {
		const property = client.primary_property;
		return property ? [property.address_line1, property.city].filter(Boolean).join(', ') : null;
	}
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<Dialog
	{open}
	title="Link to a client"
	icon={linkIcon}
	iconTone="client"
	width={440}
	initialFocusId="link-client-search"
	closeDisabled={pending}
	onClose={onCancel}
>
	<div class="link-client">
		<SearchInput
			id="link-client-search"
			bind:value={search}
			placeholder="Search clients by name, phone or email"
			ariaLabel="Search clients"
		/>
		<div class="link-client__list" role="listbox" aria-label="Clients">
			{#if clientsQuery.isPending}
				<p class="link-client__empty">Loading clients…</p>
			{:else if clientsQuery.isError}
				<p class="link-client__empty" role="alert">Clients could not be loaded.</p>
			{:else if clients.length === 0}
				<p class="link-client__empty">No clients match "{debounced}".</p>
			{:else}
				{#each clients as client (client.id)}
					{@const selected = picked?.id === client.id}
					{@const where = place(client)}
					<button
						type="button"
						role="option"
						aria-selected={selected}
						class="link-client__row"
						class:link-client__row--picked={selected}
						onclick={() => (picked = client)}
					>
						<Avatar id={client.id} name={client.display_name} />
						<span class="link-client__text">
							<span class="link-client__name">{client.display_name}</span>
							{#if where || client.phone}
								<span class="link-client__meta"
									>{[where, client.phone].filter(Boolean).join(' · ')}</span
								>
							{/if}
						</span>
						{#if selected}
							<span class="link-client__check" aria-hidden="true">{@html pickedIcon}</span>
						{/if}
					</button>
				{/each}
			{/if}
		</div>
		<p class="link-client__note">
			Linking moves this conversation and anything on the new lead onto the client you pick, then
			removes the lead. Future Messenger messages from this person go to that client.
		</p>
		{#if errorMessage}<p class="link-client__error" role="alert">{errorMessage}</p>{/if}
	</div>
	{#snippet footer()}
		<Button variant="secondary" disabled={pending} onclick={onCancel}>Cancel</Button>
		<Button
			disabled={!picked}
			loading={pending}
			onclick={() => picked && onConfirm({ id: picked.id, name: picked.display_name })}
		>
			{@html linkIcon}
			{picked ? `Link to ${picked.display_name}` : 'Link to client'}
		</Button>
	{/snippet}
</Dialog>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.link-client {
		display: flex;
		flex-direction: column;
		gap: var(--space-slim);
	}

	.link-client__list {
		display: flex;
		min-height: 120px;
		flex-direction: column;
		gap: var(--space-smallest);
	}

	.link-client__row {
		display: flex;
		align-items: center;
		gap: var(--space-slim);
		padding: var(--space-small) 10px;
		border: 0;
		border-radius: var(--radius-tile-large);
		color: inherit;
		background: transparent;
		font: inherit;
		text-align: left;
		cursor: pointer;

		&:hover {
			background: var(--color-surface--hover);
		}

		&:focus-visible {
			outline: none;
			box-shadow: var(--shadow-focus);
		}
	}

	.link-client__row--picked,
	.link-client__row--picked:hover {
		background: var(--color-surface--active);
	}

	.link-client__text {
		display: flex;
		min-width: 0;
		flex: 1;
		flex-direction: column;
	}

	.link-client__name {
		color: var(--color-heading);
		font-size: var(--typography--fontSize-base);
		font-weight: 600;
	}

	.link-client__meta {
		overflow: hidden;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-overline);
		text-overflow: ellipsis;
		white-space: nowrap;
	}

	.link-client__check {
		display: inline-grid;
		flex: 0 0 auto;
		place-items: center;
		color: var(--color-interactive);

		:global(svg) {
			width: 20px;
			height: 20px;
		}
	}

	.link-client__empty,
	.link-client__note {
		margin: 0;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-overline);
	}

	.link-client__empty {
		padding: var(--space-base) 10px;
	}

	.link-client__error {
		margin: 0;
		color: var(--color-critical);
		font-size: var(--typography--fontSize-overline);
		font-weight: 600;
	}
</style>
