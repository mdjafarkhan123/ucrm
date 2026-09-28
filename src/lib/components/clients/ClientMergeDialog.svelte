<script lang="ts">
	import { untrack } from 'svelte';
	import { createMutation, createQuery, useQueryClient } from '@tanstack/svelte-query';
	import { goto } from '$app/navigation';
	import { resolve } from '$app/paths';
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import ClientPicker from '$lib/components/work/ClientPicker.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import {
		clientDetailKey,
		clientMergePreviewKey,
		fetchClientMergePreview,
		mergeClients,
		type ClientMergePreview
	} from '$lib/clients/api';
	import swapIcon from '@tabler/icons/outline/arrows-up-down.svg?raw';
	import alertIcon from '@tabler/icons/outline/alert-triangle.svg?raw';
	import blockedIcon from '@tabler/icons/outline/ban.svg?raw';

	// Jobber's "Merge client": pick two clients, say which one stays, read what will move, confirm. The client
	// kept gets everything the other one had, and the other one is deleted. It cannot be undone, so the
	// database's own preview is shown before the button is enabled. Render it only while open, so each opening
	// starts fresh from the client it was opened on.
	let {
		open,
		initialClient = null,
		onClose
	}: {
		open: boolean;
		/** Opened from a client's page: that client starts in the "keep" slot. */
		initialClient?: { id: string; display_name: string } | null;
		onClose: () => void;
	} = $props();

	type Slot = { id: string; name: string };

	const toast = getToastManager();
	const queryClient = useQueryClient();

	let keep = $state<Slot | null>(untrack(() => slotFrom(initialClient)));
	let mergeIn = $state<Slot | null>(null);
	// Bumped on swap so both pickers remount showing their new names.
	let swapCount = $state(0);

	function slotFrom(client: { id: string; display_name: string } | null): Slot | null {
		return client ? { id: client.id, name: client.display_name } : null;
	}

	function swap() {
		[keep, mergeIn] = [mergeIn, keep];
		swapCount += 1;
	}

	const sameClient = $derived(keep !== null && mergeIn !== null && keep.id === mergeIn.id);
	const ready = $derived(keep !== null && mergeIn !== null && !sameClient);

	const previewQuery = createQuery(() => ({
		queryKey: clientMergePreviewKey(keep?.id ?? '', mergeIn?.id ?? ''),
		queryFn: () => fetchClientMergePreview(keep!.id, mergeIn!.id),
		enabled: open && ready,
		// Work and payments can land at any moment; a stale answer here could hide a blocker.
		staleTime: 0,
		gcTime: 0
	}));
	const preview = $derived(ready ? previewQuery.data : undefined);

	const MOVE_LABELS: [keyof ClientMergePreview['moves'], string, string][] = [
		['properties', 'property', 'properties'],
		['requests', 'request', 'requests'],
		['quotes', 'quote', 'quotes'],
		['jobs', 'job', 'jobs'],
		['invoices', 'invoice', 'invoices'],
		['payments', 'payment', 'payments'],
		['messages', 'message', 'messages'],
		['notes', 'note', 'notes'],
		['files', 'file', 'files'],
		['phones', 'phone number', 'phone numbers'],
		['emails', 'email address', 'email addresses'],
		['contacts', 'contact person', 'contact people'],
		['tags', 'tag', 'tags']
	];

	const moves = $derived(
		preview
			? MOVE_LABELS.filter(([key]) => preview.moves[key] > 0).map(
					([key, one, many]) => `${preview.moves[key]} ${preview.moves[key] === 1 ? one : many}`
				)
			: []
	);
	const blocked = $derived((preview?.blockers.length ?? 0) > 0);

	const mergeMutation = createMutation(() => ({
		mutationFn: ({ keepId, mergeInId }: { keepId: string; mergeInId: string; name: string }) =>
			mergeClients(keepId, mergeInId),
		onSuccess: async (result, variables) => {
			// A merge rewrites which client owns requests, quotes, jobs, invoices and conversations, so every
			// cached list may now show the wrong name. Drop the deleted client outright and refresh the rest.
			queryClient.removeQueries({ queryKey: clientDetailKey(variables.mergeInId) });
			void queryClient.invalidateQueries();
			toast.success('Clients merged.', `${variables.name} is now part of this client.`);
			onClose();
			await goto(resolve('/(app)/clients/[id=uuid]', { id: result.surviving_client_id }));
		},
		onError: (error: Error) => {
			toast.error('These clients were not merged', error.message);
			void previewQuery.refetch();
		}
	}));

	function confirm() {
		if (!keep || !mergeIn || !preview || blocked) return;
		mergeMutation.mutate({ keepId: keep.id, mergeInId: mergeIn.id, name: mergeIn.name });
	}
</script>

<!-- The inline SVG strings are trusted build-time Tabler icon imports. -->
<!-- eslint-disable svelte/no-at-html-tags -->
<Dialog {open} title="Merge clients" {onClose}>
	<p class="client-merge__intro">
		Everything the duplicate has moves to the client you keep — work, invoices, payments, messages,
		notes and contact details. Then the duplicate is deleted.
	</p>

	<div class="client-merge__slots">
		{#key swapCount}
			<ClientPicker
				id="client-merge-keep"
				label="Client to keep"
				value={keep?.id ?? ''}
				initialLabel={keep?.name ?? ''}
				onSelect={(client) => (keep = client ? { id: client.id, name: client.display_name } : null)}
			/>
			<div class="client-merge__swap">
				<Button variant="tertiary" size="small" onclick={swap}>
					<span class="client-merge__swap-icon" aria-hidden="true">{@html swapIcon}</span>
					Swap
				</Button>
			</div>
			<ClientPicker
				id="client-merge-in"
				label="Duplicate to merge in and delete"
				value={mergeIn?.id ?? ''}
				initialLabel={mergeIn?.name ?? ''}
				invalid={sameClient}
				errorMessage={sameClient ? 'Choose a different client.' : ''}
				onSelect={(client) =>
					(mergeIn = client ? { id: client.id, name: client.display_name } : null)}
			/>
		{/key}
	</div>

	{#if ready && keep && mergeIn}
		<section class="client-merge__review" aria-live="polite">
			{#if previewQuery.isPending}
				<p class="client-merge__muted">Checking what {mergeIn.name} has…</p>
			{:else if previewQuery.isError}
				<p class="client-merge__banner client-merge__banner--error" role="alert">
					{previewQuery.error.message}
				</p>
			{:else if preview}
				{#if blocked}
					{#each preview.blockers as blocker (blocker)}
						<p class="client-merge__banner client-merge__banner--error" role="alert">
							<span class="client-merge__banner-icon" aria-hidden="true">{@html blockedIcon}</span>
							{blocker}
						</p>
					{/each}
				{/if}

				<h3 class="client-merge__heading">Moves to {keep.name}</h3>
				{#if moves.length > 0}
					<ul class="client-merge__moves">
						{#each moves as move (move)}
							<li>{move}</li>
						{/each}
					</ul>
				{:else}
					<p class="client-merge__muted">
						{mergeIn.name} has no work, messages or contact details to move.
					</p>
				{/if}

				<ul class="client-merge__rules">
					<li>
						Where both have a value, {keep.name}'s stays. Anything only {mergeIn.name} has is added.
					</li>
					<li>Invoices and payments keep their amounts. Only the client they belong to changes.</li>
				</ul>

				{#each preview.warnings as warning (warning)}
					<p class="client-merge__banner client-merge__banner--warning" role="status">
						<span class="client-merge__banner-icon" aria-hidden="true">{@html alertIcon}</span>
						{warning}
					</p>
				{/each}

				<p class="client-merge__final">
					{mergeIn.name} will be deleted. This can't be undone.
				</p>
			{/if}
		</section>
	{/if}

	<footer class="client-merge__footer">
		<Button variant="secondary" onclick={onClose}>Cancel</Button>
		<Button
			variant="primary"
			variation="destructive"
			disabled={!preview || blocked || previewQuery.isFetching}
			loading={mergeMutation.isPending}
			onclick={confirm}
		>
			Merge clients
		</Button>
	</footer>
</Dialog>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.client-merge {
		&__intro {
			margin-bottom: var(--space-base);
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__slots {
			display: flex;
			flex-direction: column;
			gap: var(--space-small);
		}

		&__swap {
			display: flex;
			justify-content: center;
		}

		&__swap-icon {
			display: inline-flex;

			:global(svg) {
				width: 16px;
				height: 16px;
			}
		}

		&__review {
			display: flex;
			flex-direction: column;
			gap: var(--space-small);
			margin-top: var(--space-large);
			padding-top: var(--space-base);
			border-top: var(--border-base) solid var(--color-border);
		}

		&__heading {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			font-weight: 700;
			letter-spacing: 0.04em;
			text-transform: uppercase;
		}

		&__moves {
			display: flex;
			flex-wrap: wrap;
			gap: var(--space-smaller) var(--space-small);
			margin: 0;
			padding: 0;
			list-style: none;

			li {
				padding: var(--space-smallest) var(--space-small);
				border-radius: var(--radius-base);
				color: var(--color-text);
				background: var(--color-surface--active);
				font-size: var(--typography--fontSize-small);
			}
		}

		&__rules {
			display: flex;
			flex-direction: column;
			gap: var(--space-smallest);
			margin: 0;
			padding-left: var(--space-base);
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__muted {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__banner {
			display: flex;
			gap: var(--space-small);
			align-items: center;
			padding: var(--space-slim) var(--space-base);
			border-radius: var(--radius-base);
			font-size: var(--typography--fontSize-small);

			&--warning {
				color: var(--color-warning--onSurface);
				background: var(--color-warning--surface);
			}

			&--error {
				color: var(--color-critical--onSurface);
				background: var(--color-critical--surface);
			}
		}

		&__banner-icon {
			display: inline-flex;
			flex: 0 0 auto;

			:global(svg) {
				width: 18px;
				height: 18px;
			}
		}

		&__final {
			color: var(--color-text);
			font-size: var(--typography--fontSize-small);
			font-weight: 600;
		}

		&__footer {
			display: flex;
			gap: var(--space-small);
			justify-content: flex-end;
			margin-top: var(--space-large);
		}
	}
</style>
