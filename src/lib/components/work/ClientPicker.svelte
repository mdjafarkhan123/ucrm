<script lang="ts">
	import { untrack } from 'svelte';
	import { Combobox } from 'bits-ui';
	import { createQuery } from '@tanstack/svelte-query';
	import { fetchClients, type ClientListItem } from '$lib/clients/api';
	import checkIcon from '@tabler/icons/outline/check.svg?raw';
	import chevronDownIcon from '@tabler/icons/outline/chevron-down.svg?raw';
	import exclamationCircleIcon from '@tabler/icons/outline/exclamation-circle.svg?raw';
	import searchIcon from '@tabler/icons/outline/search.svg?raw';

	// Search-and-pick a client, shared by every create page that starts from one: a request today, a quote
	// or job later. Typing searches the same client list the Clients page uses, so results and ranking never
	// drift apart from it. Picking a client hands the whole row back through `onSelect`, since the property
	// picker beside this one needs the primary property, not just an id.
	let {
		value = $bindable(''),
		id,
		invalid = false,
		errorMessage = '',
		required = false,
		placeholder = 'Search by name or company',
		initialClient = null,
		onSelect
	}: {
		value?: string;
		id: string;
		invalid?: boolean;
		errorMessage?: string;
		required?: boolean;
		placeholder?: string;
		/** A client already chosen elsewhere -- a draft handed in from another form -- so the field shows their
		 * name at rest instead of looking empty while `value` carries the id. */
		initialClient?: ClientListItem | null;
		onSelect?: (client: ClientListItem | null) => void;
	} = $props();

	let query = $state(untrack(() => initialClient?.display_name ?? ''));
	let open = $state(false);
	let debouncedQuery = $state('');
	let selected = $state<ClientListItem | null>(untrack(() => initialClient));

	$effect(() => {
		const term = query.trim();
		const handle = setTimeout(() => (debouncedQuery = term), 300);
		return () => clearTimeout(handle);
	});

	const clientsQuery = createQuery(() => ({
		queryKey: ['clients', 'picker', debouncedQuery],
		queryFn: () =>
			fetchClients({
				search: debouncedQuery,
				status: '',
				tagId: '',
				sort: 'updated_at',
				dir: 'desc'
			}),
		enabled: open,
		// A search result goes stale slowly enough that reopening the same query moments later, or a
		// keystroke that lands back on an earlier term, can reuse it instead of asking again.
		staleTime: 15_000,
		gcTime: 60_000
	}));
	const results = $derived(clientsQuery.data?.clients ?? []);
	const comboboxItems = $derived(
		results.map((client) => ({ value: client.id, label: client.display_name }))
	);

	function metaFor(client: ClientListItem) {
		if (client.company_name) return client.company_name;
		const property = client.primary_property;
		if (property) return [property.address_line1, property.city].filter(Boolean).join(', ');
		return 'No property yet';
	}

	let inputValue = $derived(open ? query : (selected?.display_name ?? ''));
	let describedBy = $derived(errorMessage ? `${id}-error` : undefined);

	function focusPicker(input: HTMLInputElement) {
		query = '';
		open = true;
		input.select();
	}

	function chooseClient(clientId: string) {
		// Clicking the already-picked client is a deselect as far as the combobox is concerned, but the input
		// keeps showing their name -- the form would read as filled in while reporting no client. Treat it as
		// "no change" instead; clearing is done by typing.
		if (!clientId) {
			value = selected?.id ?? '';
			query = selected?.display_name ?? '';
			open = false;
			return;
		}
		const client = results.find((entry) => entry.id === clientId) ?? null;
		value = clientId;
		selected = client;
		query = client?.display_name ?? '';
		open = false;
		onSelect?.(client);
	}
</script>

<!-- The inline SVG strings are trusted build-time Tabler icon imports. -->
<!-- eslint-disable svelte/no-at-html-tags -->
<div class="client-picker" class:client-picker--invalid={invalid}>
	<label for={id}
		>Client{#if required}<span aria-hidden="true">*</span>{/if}</label
	>
	<Combobox.Root
		type="single"
		bind:value
		bind:open
		{inputValue}
		items={comboboxItems}
		onValueChange={chooseClient}
	>
		<div class="client-picker__control">
			<span class="client-picker__search" aria-hidden="true">{@html searchIcon}</span>
			<Combobox.Input
				{id}
				{placeholder}
				autocomplete="off"
				aria-describedby={describedBy}
				aria-invalid={invalid}
				onfocus={(event) => focusPicker(event.currentTarget)}
				onclick={() => (open = true)}
				oninput={(event) => {
					query = event.currentTarget.value;
					open = true;
				}}
			/>
			<Combobox.Trigger class="client-picker__trigger" aria-label="Show clients">
				<span aria-hidden="true">{@html chevronDownIcon}</span>
			</Combobox.Trigger>
		</div>
		<Combobox.Portal>
			<Combobox.Content
				class="client-picker__menu"
				data-elevation="elevated"
				align="start"
				sideOffset={4}
				collisionPadding={8}
			>
				<Combobox.Viewport class="client-picker__viewport">
					{#if clientsQuery.isPending}
						<div class="client-picker__empty">Searching…</div>
					{:else}
						{#each results as client (client.id)}
							<Combobox.Item
								value={client.id}
								label={client.display_name}
								class="client-picker__option"
							>
								<span class="client-picker__option-copy">
									<strong>{client.display_name}</strong>
									<small>{metaFor(client)}</small>
								</span>
								{#if value === client.id}<span class="client-picker__check" aria-hidden="true"
										>{@html checkIcon}</span
									>{/if}
							</Combobox.Item>
						{:else}<div class="client-picker__empty">
								{debouncedQuery ? `No clients match “${debouncedQuery}”.` : 'No clients yet.'}
							</div>{/each}
					{/if}
				</Combobox.Viewport>
			</Combobox.Content>
		</Combobox.Portal>
	</Combobox.Root>
	{#if errorMessage}<p class="client-picker__error" id={`${id}-error`} role="alert">
			<span aria-hidden="true">{@html exclamationCircleIcon}</span>{errorMessage}
		</p>{/if}
</div>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.client-picker {
		width: 100%;
	}
	.client-picker > label {
		display: block;
		margin-bottom: var(--space-smaller);
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		font-weight: 500;
	}
	.client-picker > label span {
		color: var(--color-critical);
	}
	.client-picker__control {
		position: relative;
		display: flex;
		min-height: var(--space-largest);
		align-items: center;
		border: var(--border-base) solid var(--color-border--interactive);
		border-radius: var(--radius-base);
		background: var(--color-surface);
	}
	.client-picker__control:focus-within {
		z-index: var(--elevation-base);
		box-shadow: var(--shadow-focus);
	}
	.client-picker--invalid .client-picker__control {
		border-color: var(--color-critical);
	}
	.client-picker__control :global(input) {
		width: 100%;
		min-width: 0;
		min-height: calc(var(--space-largest) - (var(--border-base) * 2));
		padding: var(--space-small) var(--space-largest);
		border: 0;
		outline: 0;
		color: var(--color-heading);
		background: transparent;
		font: inherit;
	}
	.client-picker__search {
		position: absolute;
		left: var(--space-base);
		display: grid;
		width: 16px;
		height: 16px;
		place-items: center;
		color: var(--color-icon--secondary);
		pointer-events: none;
	}
	:global(.client-picker__trigger) {
		position: absolute;
		right: 0;
		display: grid;
		width: var(--space-largest);
		height: 100%;
		place-items: center;
		border: 0;
		border-radius: 0 var(--radius-base) var(--radius-base) 0;
		outline: 0;
		color: var(--color-icon--secondary);
		background: transparent;
		cursor: pointer;
	}
	:global(.client-picker__trigger:focus-visible) {
		box-shadow: var(--shadow-focus);
	}
	:global(.client-picker__trigger[data-state='open']) span {
		transform: rotate(180deg);
	}
	:global(.client-picker__trigger span) {
		display: grid;
		width: 18px;
		height: 18px;
		place-items: center;
		transition: transform var(--timing-quick);
	}
	:global(.client-picker__trigger svg),
	.client-picker__search :global(svg),
	.client-picker__check :global(svg),
	.client-picker__error :global(svg) {
		display: block;
		width: 16px;
		height: 16px;
	}
	:global(.client-picker__menu) {
		z-index: var(--elevation-modal);
		width: var(--bits-floating-anchor-width);
		max-height: min(300px, var(--bits-floating-available-height));
		overflow: hidden;
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface);
		box-shadow: var(--shadow-base);
	}
	:global(.client-picker__viewport) {
		max-height: inherit;
		overflow-y: auto;
		padding: var(--space-small);
	}
	:global(.client-picker__option) {
		display: flex;
		width: 100%;
		align-items: center;
		gap: var(--space-small);
		padding: var(--space-small);
		border: 0;
		border-radius: var(--radius-small);
		outline: 0;
		color: var(--color-text);
		background: transparent;
		text-align: left;
		cursor: pointer;
		transition:
			color var(--timing-quick),
			background-color var(--timing-quick);
	}
	:global(.client-picker__option[data-highlighted]) {
		color: var(--color-heading);
		background: var(--color-surface--hover);
	}
	.client-picker__option-copy {
		display: grid;
		min-width: 0;
		flex: 1;
		gap: 2px;
	}
	.client-picker__option-copy strong {
		overflow: hidden;
		color: inherit;
		font-size: var(--typography--fontSize-base);
		font-weight: 500;
		text-overflow: ellipsis;
		white-space: nowrap;
	}
	.client-picker__option-copy small {
		overflow: hidden;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		text-overflow: ellipsis;
		white-space: nowrap;
	}
	.client-picker__check {
		display: grid;
		width: 16px;
		height: 16px;
		flex: 0 0 16px;
		place-items: center;
		color: var(--color-interactive);
	}
	.client-picker__empty {
		padding: var(--space-base);
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		text-align: center;
	}
	.client-picker__error {
		display: flex;
		align-items: center;
		gap: var(--space-smaller);
		margin: var(--space-smaller) 0 0;
		color: var(--color-critical);
		font-size: var(--typography--fontSize-small);
	}
</style>
