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
	import IconTile from '$lib/components/ui/IconTile.svelte';
	import Banner from '$lib/components/ui/Banner.svelte';
	import swapIcon from '@tabler/icons/outline/arrows-left-right.svg?raw';
	import alertIcon from '@tabler/icons/outline/alert-triangle.svg?raw';
	import errorIcon from '@tabler/icons/outline/alert-circle.svg?raw';
	import blockedIcon from '@tabler/icons/outline/ban.svg?raw';
	import mergeIcon from '@tabler/icons/outline/git-merge.svg?raw';
	import trashIcon from '@tabler/icons/outline/trash.svg?raw';
	import keepIcon from '@tabler/icons/outline/user-check.svg?raw';
	import arrowIcon from '@tabler/icons/outline/arrow-right.svg?raw';
	import propertyIcon from '@tabler/icons/outline/home.svg?raw';
	import requestIcon from '@tabler/icons/outline/inbox.svg?raw';
	import quoteIcon from '@tabler/icons/outline/file-text.svg?raw';
	import jobIcon from '@tabler/icons/outline/hammer.svg?raw';
	import invoiceIcon from '@tabler/icons/outline/receipt.svg?raw';
	import paymentIcon from '@tabler/icons/outline/credit-card.svg?raw';
	import messageIcon from '@tabler/icons/outline/message-circle.svg?raw';
	import noteIcon from '@tabler/icons/outline/note.svg?raw';
	import fileIcon from '@tabler/icons/outline/file.svg?raw';
	import phoneIcon from '@tabler/icons/outline/phone.svg?raw';
	import emailIcon from '@tabler/icons/outline/mail.svg?raw';
	import contactsIcon from '@tabler/icons/outline/users.svg?raw';
	import tagIcon from '@tabler/icons/outline/tag.svg?raw';

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

	// Each kind of thing that moves, shown as a tile in the colour of its record (`modals.md` → Merge clients).
	const MOVE_KINDS: {
		key: keyof ClientMergePreview['moves'];
		one: string;
		many: string;
		icon: string;
		tone: string;
	}[] = [
		{ key: 'properties', one: 'property', many: 'properties', icon: propertyIcon, tone: 'client' },
		{ key: 'requests', one: 'request', many: 'requests', icon: requestIcon, tone: 'request' },
		{ key: 'quotes', one: 'quote', many: 'quotes', icon: quoteIcon, tone: 'quote' },
		{ key: 'jobs', one: 'job', many: 'jobs', icon: jobIcon, tone: 'job' },
		{ key: 'invoices', one: 'invoice', many: 'invoices', icon: invoiceIcon, tone: 'invoice' },
		{ key: 'payments', one: 'payment', many: 'payments', icon: paymentIcon, tone: 'invoice' },
		{ key: 'messages', one: 'message', many: 'messages', icon: messageIcon, tone: 'conversation' },
		{ key: 'notes', one: 'note', many: 'notes', icon: noteIcon, tone: 'inactive' },
		{ key: 'files', one: 'file', many: 'files', icon: fileIcon, tone: 'informative' },
		{ key: 'phones', one: 'phone number', many: 'phone numbers', icon: phoneIcon, tone: 'time' },
		{ key: 'emails', one: 'email address', many: 'email addresses', icon: emailIcon, tone: 'conversation' },
		{ key: 'contacts', one: 'contact person', many: 'contact people', icon: contactsIcon, tone: 'client' },
		{ key: 'tags', one: 'tag', many: 'tags', icon: tagIcon, tone: 'inactive' }
	];

	const moves = $derived(
		preview
			? MOVE_KINDS.filter(({ key }) => preview.moves[key] > 0).map((kind) => ({
					...kind,
					count: preview.moves[kind.key],
					label: preview.moves[kind.key] === 1 ? kind.one : kind.many
				}))
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
<Dialog {open} title="Merge clients" size="large" icon={mergeIcon} iconTone="client" {onClose}>
	<div class="client-merge">
		<p class="client-merge__intro">
			Everything the duplicate has moves to the client you keep — work, invoices, payments, messages,
			notes and contact details. Then the duplicate is deleted.
		</p>

		<div class="client-merge__slots">
			{#key swapCount}
				<section class="client-merge__slot client-merge__slot--duplicate">
					<header class="client-merge__band">
						<IconTile icon={trashIcon} tone="critical" size={24} white />
						Duplicate to merge in and delete
					</header>
					<div class="client-merge__pick">
						<ClientPicker
							id="client-merge-in"
							label="Duplicate to merge in and delete"
							hideLabel
							avatar
							value={mergeIn?.id ?? ''}
							initialLabel={mergeIn?.name ?? ''}
							invalid={sameClient}
							errorMessage={sameClient ? 'Choose a different client.' : ''}
							onSelect={(client) =>
								(mergeIn = client ? { id: client.id, name: client.display_name } : null)}
						/>
					</div>
				</section>
				<div class="client-merge__between">
					<span class="client-merge__arrow" aria-hidden="true">{@html arrowIcon}</span>
					<Button variant="quiet" size="small" onclick={swap}>
						{@html swapIcon}
						Swap
					</Button>
				</div>
				<section class="client-merge__slot client-merge__slot--keep">
					<header class="client-merge__band">
						<IconTile icon={keepIcon} tone="client" size={24} white />
						Client to keep
					</header>
					<div class="client-merge__pick">
						<ClientPicker
							id="client-merge-keep"
							label="Client to keep"
							hideLabel
							avatar
							value={keep?.id ?? ''}
							initialLabel={keep?.name ?? ''}
							onSelect={(client) =>
								(keep = client ? { id: client.id, name: client.display_name } : null)}
						/>
					</div>
				</section>
			{/key}
		</div>

		{#if ready && keep && mergeIn}
			<section class="client-merge__review" aria-live="polite">
				{#if previewQuery.isPending}
					<p class="client-merge__muted">Checking what {mergeIn.name} has…</p>
					<div class="client-merge__moves" aria-hidden="true">
						{#each { length: 5 } as _, index (index)}
							<div class="client-merge__move client-merge__move--bone">
								<span class="client-merge__bone client-merge__bone--tile"></span>
								<span class="client-merge__bone-lines">
									<span class="client-merge__bone client-merge__bone--short"></span>
									<span class="client-merge__bone client-merge__bone--long"></span>
								</span>
							</div>
						{/each}
					</div>
				{:else if previewQuery.isError}
					<Banner type="error" icon={errorIcon}>{previewQuery.error.message}</Banner>
				{:else if preview}
					{#each preview.blockers as blocker (blocker)}
						<Banner type="error" icon={blockedIcon}>{blocker}</Banner>
					{/each}

					<h3 class="client-merge__heading">Moves to {keep.name}</h3>
					{#if moves.length > 0}
						<ul class="client-merge__moves">
							{#each moves as move (move.key)}
								<li class="client-merge__move">
									<IconTile icon={move.icon} tone={move.tone} size={32} />
									<span class="client-merge__move-copy">
										<strong>{move.count}</strong>
										{move.label}
									</span>
								</li>
							{/each}
						</ul>
					{:else}
						<p class="client-merge__muted">
							{mergeIn.name} has no work, messages or contact details to move.
						</p>
					{/if}

					<ul class="client-merge__rules">
						<li>
							<span class="client-merge__rule-icon client-merge__rule-icon--client" aria-hidden="true"
								>{@html keepIcon}</span
							>
							Where both have a value, {keep.name}'s stays. Anything only {mergeIn.name} has is added.
						</li>
						<li>
							<span class="client-merge__rule-icon client-merge__rule-icon--invoice" aria-hidden="true"
								>{@html invoiceIcon}</span
							>
							Invoices and payments keep their amounts. Only the client they belong to changes.
						</li>
					</ul>

					{#each preview.warnings as warning (warning)}
						<Banner type="warning" icon={alertIcon}>{warning}</Banner>
					{/each}
				{/if}
			</section>
		{/if}
	</div>

	{#snippet footer()}
		{#if ready && preview && mergeIn}
			<p class="client-merge__final">
				<span aria-hidden="true">{@html trashIcon}</span>
				{mergeIn.name} will be deleted. This can't be undone.
			</p>
		{:else}
			<span></span>
		{/if}
		<div class="client-merge__actions">
			<Button variant="secondary" onclick={onClose} disabled={mergeMutation.isPending}>Cancel</Button>
			<Button
				variant="primary"
				variation="destructive"
				disabled={!preview || blocked || previewQuery.isFetching}
				loading={mergeMutation.isPending}
				onclick={confirm}
			>
				{@html mergeIcon}
				Merge clients
			</Button>
		</div>
	{/snippet}
</Dialog>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.client-merge {
		display: flex;
		flex-direction: column;
		gap: var(--space-medium);

		&__intro {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-base);
			line-height: 1.45;
		}

		&__slots {
			display: grid;
			grid-template-columns: minmax(0, 1fr) 96px minmax(0, 1fr);
			align-items: center;
		}

		&__slot {
			--slot-color: var(--color-client);
			--slot-surface: var(--color-client--surface);
			--slot-ink: var(--color-client--onSurface);
			overflow: hidden;
			align-self: stretch;
			border: var(--border-base) solid var(--color-client--surface-edge);
			border-radius: 12px;
			background: var(--color-surface);

			&--duplicate {
				--slot-surface: var(--color-critical--surface);
				--slot-ink: var(--color-critical--onSurface);
				border-color: var(--color-critical--surface-edge);
			}
		}

		&__band {
			display: flex;
			align-items: center;
			gap: var(--space-slim);
			padding: 10px 14px;
			color: var(--slot-ink);
			background: var(--slot-surface);
			font-size: var(--typography--fontSize-label);
			font-weight: 600;
		}

		&__pick {
			padding: 14px;
		}

		&__between {
			display: flex;
			flex-direction: column;
			align-items: center;
			gap: var(--space-small);

			:global(svg) {
				width: 16px;
				height: 16px;
			}
		}

		&__arrow {
			display: grid;
			width: 40px;
			height: 40px;
			place-items: center;
			border: var(--border-base) solid var(--color-client--surface-edge);
			border-radius: var(--radius-circle);
			color: var(--color-client);
			background: var(--color-client--surface);

			:global(svg) {
				width: 20px;
				height: 20px;
			}
		}

		&__review {
			display: flex;
			flex-direction: column;
			gap: 14px;
			padding-top: var(--space-medium);
			border-top: var(--border-base) solid var(--color-border);
		}

		&__heading {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			font-weight: 600;
			letter-spacing: 0.06em;
			text-transform: uppercase;
		}

		&__moves {
			display: grid;
			grid-template-columns: repeat(5, minmax(0, 1fr));
			gap: var(--space-small) 14px;
			margin: 0;
			padding: 0;
			list-style: none;
		}

		&__move {
			display: flex;
			align-items: center;
			gap: 10px;
			min-width: 0;
			padding: var(--space-slim);
			border: var(--border-base) solid var(--color-border);
			border-radius: 12px;
			background: var(--color-surface--background--subtle);
		}

		&__move-copy {
			display: grid;
			min-width: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			font-weight: 500;

			strong {
				color: var(--color-heading);
				font-size: 18px;
				font-weight: 700;
				line-height: 1.2;
			}
		}

		&__bone {
			display: block;
			border-radius: var(--radius-small);
			background: var(--color-border);

			&--tile {
				width: 32px;
				height: 32px;
				border-radius: var(--radius-base);
			}

			&--short {
				width: 24px;
				height: 12px;
			}

			&--long {
				width: 60px;
				height: 8px;
			}
		}

		&__bone-lines {
			display: grid;
			gap: 6px;
		}

		&__rules {
			display: grid;
			gap: var(--space-small);
			margin: 0;
			padding: 0;
			list-style: none;
			color: var(--color-text);
			font-size: var(--typography--fontSize-label);

			li {
				display: flex;
				align-items: center;
				gap: 10px;
			}
		}

		&__rule-icon {
			display: inline-flex;
			flex: 0 0 auto;

			:global(svg) {
				width: 16px;
				height: 16px;
			}

			&--client {
				color: var(--color-client);
			}

			&--invoice {
				color: var(--color-invoice);
			}
		}

		&__muted {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-label);
		}

		&__final {
			display: flex;
			align-items: center;
			gap: var(--space-small);
			margin: 0;
			color: var(--color-critical);
			font-size: var(--typography--fontSize-label);
			font-weight: 600;

			span {
				display: inline-flex;
			}

			:global(svg) {
				width: 16px;
				height: 16px;
			}
		}

		&__actions {
			display: flex;
			gap: var(--space-small);
		}
	}
</style>
