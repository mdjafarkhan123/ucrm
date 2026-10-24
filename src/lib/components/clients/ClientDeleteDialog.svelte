<script lang="ts">
	import { createMutation, createQuery, useQueryClient } from '@tanstack/svelte-query';
	import { resolve } from '$app/paths';
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Banner from '$lib/components/ui/Banner.svelte';
	import IconTile from '$lib/components/ui/IconTile.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import {
		clientDeletePreviewKey,
		deleteClients,
		fetchClientDeletePreview,
		recentlyDeletedClientsKey,
		restoreClientDeletions,
		type ClientDeletionBlocker,
		type ClientDeletionCounts,
		type ClientDeleteResult
	} from '$lib/clients/api';
	import trashIcon from '@tabler/icons/outline/trash.svg?raw';
	import shieldIcon from '@tabler/icons/outline/shield-check.svg?raw';
	import hiddenIcon from '@tabler/icons/outline/eye-off.svg?raw';
	import restoreIcon from '@tabler/icons/outline/rotate.svg?raw';
	import stopTextIcon from '@tabler/icons/outline/message-circle-off.svg?raw';
	import moneyIcon from '@tabler/icons/outline/currency-dollar.svg?raw';
	import errorIcon from '@tabler/icons/outline/alert-circle.svg?raw';
	import openIcon from '@tabler/icons/outline/arrow-up-right.svg?raw';
	import requestIcon from '@tabler/icons/outline/inbox.svg?raw';
	import quoteIcon from '@tabler/icons/outline/file-text.svg?raw';
	import jobIcon from '@tabler/icons/outline/hammer.svg?raw';
	import messageIcon from '@tabler/icons/outline/message-circle.svg?raw';
	import noteIcon from '@tabler/icons/outline/note.svg?raw';
	import fileIcon from '@tabler/icons/outline/file.svg?raw';
	import reviewIcon from '@tabler/icons/outline/star.svg?raw';
	import opportunityIcon from '@tabler/icons/outline/target.svg?raw';
	import propertyIcon from '@tabler/icons/outline/home.svg?raw';
	import invoiceIcon from '@tabler/icons/outline/receipt.svg?raw';
	import cardIcon from '@tabler/icons/outline/credit-card.svg?raw';
	import walletIcon from '@tabler/icons/outline/wallet.svg?raw';

	// Data privacy Part 6 (`modals.md` → Delete client pop-ups, Approved B): Jobber's delete names what goes with
	// the customer; HubSpot's keeps them restorable for 30 days. One client or many from the Clients list. A client
	// with open money is refused and named. Render it only while open, so each opening counts afresh.
	let {
		open,
		clients,
		onClose,
		onDeleted
	}: {
		open: boolean;
		/** The picked clients; one from the client page, up to 100 from the Clients list. */
		clients: { id: string; display_name: string }[];
		onClose: () => void;
		/** After the move to Recently Deleted, e.g. to leave the deleted client's page. */
		onDeleted?: (result: ClientDeleteResult) => void;
	} = $props();

	const toast = getToastManager();
	const queryClient = useQueryClient();
	const ids = $derived(clients.map((client) => client.id));
	const many = $derived(clients.length > 1);

	const previewQuery = createQuery(() => ({
		queryKey: clientDeletePreviewKey(ids),
		queryFn: () => fetchClientDeletePreview(ids),
		enabled: open && ids.length > 0,
		// New work or a payment can land at any moment; a stale count here could hide a refusal.
		staleTime: 0,
		gcTime: 0
	}));
	const preview = $derived(previewQuery.data);
	const deletable = $derived(
		preview?.clients.filter((client) => client.blockers.length === 0) ?? []
	);
	const blocked = $derived(preview?.clients.filter((client) => client.blockers.length > 0) ?? []);
	// One client with open money gets the refusal pop-up instead of the delete.
	const refusal = $derived(!many && blocked.length === 1 ? blocked[0] : null);
	const single = $derived(!many ? preview?.clients[0] : undefined);

	const name = $derived(
		many ? `${clients.length} clients` : (clients[0]?.display_name ?? 'this client')
	);
	const counts = $derived<Partial<ClientDeletionCounts>>(
		(many ? preview?.totals : single?.counts) ?? {}
	);
	const keptInvoices = $derived(
		(many ? preview?.kept_totals.invoices : single?.kept.invoices) ?? 0
	);

	// Each kind that goes, in its record's colour (`modals.md` → Delete client).
	const KINDS: { key: keyof ClientDeletionCounts; label: string; icon: string; tone: string }[] = [
		{ key: 'requests', label: 'Requests', icon: requestIcon, tone: 'request' },
		{ key: 'quotes', label: 'Quotes', icon: quoteIcon, tone: 'quote' },
		{ key: 'jobs', label: 'Jobs and visits', icon: jobIcon, tone: 'job' },
		{ key: 'messages', label: 'Messages', icon: messageIcon, tone: 'conversation' },
		{ key: 'notes', label: 'Notes', icon: noteIcon, tone: 'inactive' },
		{ key: 'files', label: 'Files', icon: fileIcon, tone: 'informative' },
		{ key: 'review_requests', label: 'Review requests', icon: reviewIcon, tone: 'review' },
		{ key: 'opportunities', label: 'Pipeline cards', icon: opportunityIcon, tone: 'growth' },
		{ key: 'properties', label: 'Properties', icon: propertyIcon, tone: 'client' }
	];
	const goes = $derived(KINDS.map((kind) => ({ ...kind, count: counts[kind.key] ?? 0 })));

	const dateFormat = new Intl.DateTimeFormat(undefined, { month: 'short', day: 'numeric' });
	const sinceFormat = new Intl.DateTimeFormat(undefined, { month: 'short', year: 'numeric' });
	const purgeDate = $derived(preview ? dateFormat.format(new Date(preview.purge_after)) : '');
	const subtitle = $derived.by(() => {
		if (many) {
			return blocked.length
				? `${clients.length} picked on the Clients list · ${blocked.length} left out`
				: `${clients.length} picked on the Clients list`;
		}
		if (!single) return undefined;
		const properties = single.counts.properties;
		return `Client since ${sinceFormat.format(new Date(single.created_at))} · ${properties} ${
			properties === 1 ? 'property' : 'properties'
		}`;
	});

	function money(blocker: ClientDeletionBlocker) {
		if (blocker.amount_minor == null || !blocker.currency_code) return '';
		return new Intl.NumberFormat(undefined, {
			style: 'currency',
			currency: blocker.currency_code
		}).format(blocker.amount_minor / 100);
	}

	function blockerIcon(kind: string) {
		if (kind === 'card_payment_in_progress' || kind === 'refund_in_progress') return cardIcon;
		if (kind === 'credit_unused') return walletIcon;
		if (kind === 'message_sending') return messageIcon;
		return invoiceIcon;
	}

	const undoMutation = createMutation(() => ({
		mutationFn: (deletionIds: string[]) => restoreClientDeletions(deletionIds),
		onSuccess: (result) => {
			void queryClient.invalidateQueries();
			if (result.matches.length) {
				toast.warning(
					'Not brought back yet',
					'Open Recently Deleted to choose how to restore them.'
				);
			} else {
				toast.success(
					result.restored.length === 1
						? `${result.restored[0].display_name} is back`
						: `${result.restored.length} clients are back`
				);
			}
		},
		onError: (error: Error) => toast.error('They were not brought back', error.message)
	}));

	const deleteMutation = createMutation(() => ({
		mutationFn: () => deleteClients(deletable.map((client) => client.client_id)),
		onSuccess: (result) => {
			// The clients, their work and their conversations leave every list, the schedule and the inbox.
			void queryClient.invalidateQueries();
			void queryClient.invalidateQueries({ queryKey: recentlyDeletedClientsKey });
			const deletionIds = result.deleted.map((row) => row.deletion_id);
			if (deletionIds.length) {
				toast.show({
					variant: 'success',
					title:
						result.deleted.length === 1
							? `${result.deleted[0].display_name} moved to Recently Deleted`
							: `${result.deleted.length} clients moved to Recently Deleted`,
					message: `You can restore them until ${purgeDate}.`,
					duration: 8000,
					action: { label: 'Undo', onSelect: () => undoMutation.mutate(deletionIds) }
				});
			}
			if (result.left_out.length) {
				toast.warning(
					`${result.left_out.length} left out`,
					`${result.left_out.map((row) => row.display_name).join(', ')} still have money open.`
				);
			}
			onDeleted?.(result);
			onClose();
		}
	}));
</script>

<!-- The inline SVG strings are trusted build-time Tabler icon imports. -->
<!-- eslint-disable svelte/no-at-html-tags -->
{#if refusal}
	<Dialog
		{open}
		title="{refusal.display_name} can't be deleted yet"
		icon={moneyIcon}
		iconTone="warning"
		{onClose}
	>
		<div class="client-delete__refusal">
			<p class="client-delete__intro">
				Some of their money isn't settled. Settle each item below, then delete them.
			</p>
			<ul class="client-delete__list">
				{#each refusal.blockers as blocker, index (index)}
					<li class="client-delete__row client-delete__row--blocker">
						<IconTile icon={blockerIcon(blocker.kind)} tone="invoice" size={32} />
						<span class="client-delete__blocker">
							<span class="client-delete__blocker-title">
								{blocker.label.split('.')[0]}
								{#if money(blocker)}
									· <span class="client-delete__amount">{money(blocker)}</span>
								{/if}
							</span>
							<span class="client-delete__blocker-how">
								{blocker.label.split('.').slice(1).join('.').trim()}
							</span>
						</span>
						{#if blocker.invoice_id}
							<Button
								variant="secondary"
								size="small"
								href={resolve('/(app)/invoices/[id=uuid]', { id: blocker.invoice_id })}
							>
								{@html openIcon}
								Open
							</Button>
						{/if}
					</li>
				{/each}
			</ul>
		</div>
		{#snippet footer()}
			<span></span>
			<Button variant="primary" onclick={onClose}>Got it</Button>
		{/snippet}
	</Dialog>
{:else}
	<Dialog
		{open}
		title="Delete {name}?"
		{subtitle}
		width={940}
		icon={trashIcon}
		iconTone="critical"
		flush
		closeDisabled={deleteMutation.isPending}
		{onClose}
	>
		<div class="client-delete">
			<section class="client-delete__goes">
				{#if many && blocked.length}
					<Banner type="warning" icon={moneyIcon}>
						Left out because money is still open: {blocked
							.map((client) => client.display_name)
							.join(', ')}.
					</Banner>
				{/if}
				{#if deleteMutation.isError}
					<Banner type="error" icon={errorIcon}>{deleteMutation.error.message}</Banner>
				{/if}
				<h3 class="client-delete__heading client-delete__heading--critical">
					<span aria-hidden="true">{@html trashIcon}</span>
					Goes with {many ? 'them' : name}
				</h3>
				{#if previewQuery.isError}
					<Banner type="error" icon={errorIcon}>
						We couldn't count what goes with {many ? 'them' : name}.
						{#snippet action()}
							<Button variant="secondary" size="small" onclick={() => previewQuery.refetch()}>
								Try again
							</Button>
						{/snippet}
					</Banner>
				{:else}
					<ul class="client-delete__list" aria-busy={previewQuery.isPending}>
						{#each goes as kind (kind.key)}
							<li class="client-delete__row">
								{#if previewQuery.isPending}
									<span class="client-delete__bone client-delete__bone--tile"></span>
									<span class="client-delete__bone client-delete__bone--label"></span>
								{:else}
									<IconTile icon={kind.icon} tone={kind.tone} size={24} />
									<span class="client-delete__kind">{kind.label}</span>
									<span class="client-delete__count">{kind.count}</span>
								{/if}
							</li>
						{/each}
					</ul>
				{/if}
			</section>

			<aside class="client-delete__stays">
				<h3 class="client-delete__heading">
					<span aria-hidden="true">{@html shieldIcon}</span>
					What stays
				</h3>
				{#if previewQuery.isError}
					<p class="client-delete__why">Invoices and payments always stay.</p>
				{:else}
					<div class="client-delete__card">
						<IconTile icon={invoiceIcon} tone="invoice" size={32} />
						<span>
							<span class="client-delete__card-title">
								{keptInvoices}
								{keptInvoices === 1 ? 'invoice' : 'invoices'} and their payments
							</span>
							<span class="client-delete__why">Tax law needs them as they were issued.</span>
						</span>
					</div>
					<div class="client-delete__card">
						<IconTile icon={stopTextIcon} tone="conversation" size={32} />
						<span>
							<span class="client-delete__card-title">Any "stop texting" choice</span>
							<span class="client-delete__why">So nobody can text or email them by mistake.</span>
						</span>
					</div>
				{/if}

				<p class="client-delete__next">What happens next</p>
				<ol class="client-delete__steps">
					<li class="client-delete__step">
						<span class="client-delete__dot" aria-hidden="true">{@html hiddenIcon}</span>
						<span>
							<span class="client-delete__when">Today</span>
							<span class="client-delete__step-line"
								>Hidden from lists, search, the schedule and the inbox.</span
							>
						</span>
					</li>
					<li class="client-delete__step">
						<span class="client-delete__dot" aria-hidden="true">{@html restoreIcon}</span>
						<span>
							<span class="client-delete__when">Until {purgeDate || '30 days from now'}</span>
							<span class="client-delete__step-line"
								>Restore from Recently Deleted, exactly as it was.</span
							>
						</span>
					</li>
					<li class="client-delete__step client-delete__step--last">
						<span class="client-delete__dot" aria-hidden="true">{@html trashIcon}</span>
						<span>
							<span class="client-delete__when">Deleted for good</span>
							<span class="client-delete__step-line">Everything except invoices and payments.</span>
						</span>
					</li>
				</ol>
			</aside>
		</div>

		{#snippet footer()}
			<span></span>
			<div class="client-delete__actions">
				<Button variant="secondary" onclick={onClose} disabled={deleteMutation.isPending}
					>Cancel</Button
				>
				<Button
					variant="primary"
					variation="destructive"
					disabled={!preview || deletable.length === 0 || previewQuery.isFetching}
					loading={deleteMutation.isPending}
					onclick={() => deleteMutation.mutate()}
				>
					{@html trashIcon}
					{many ? `Delete ${deletable.length} clients` : 'Delete client'}
				</Button>
			</div>
		{/snippet}
	</Dialog>
{/if}

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.client-delete {
		display: grid;
		grid-template-columns: minmax(0, 1fr) 360px;

		&__goes {
			display: flex;
			flex-direction: column;
			gap: 14px;
			padding: var(--space-medium);
		}

		&__stays {
			display: flex;
			flex-direction: column;
			gap: 14px;
			padding: var(--space-medium);
			border-left: var(--border-base) solid var(--color-client--surface-edge);
			background: var(--color-client--surface);
		}

		&__heading {
			display: flex;
			align-items: center;
			gap: var(--space-small);
			margin: 0;
			color: var(--color-heading);
			font-size: var(--typography--fontSize-large);
			font-weight: 600;

			span {
				display: inline-flex;
				color: var(--color-client);
			}

			:global(svg) {
				width: 16px;
				height: 16px;
			}

			&--critical span {
				color: var(--color-critical);
			}
		}

		&__list {
			overflow: hidden;
			margin: 0;
			padding: 0;
			border: var(--border-base) solid var(--color-border);
			border-radius: 12px;
			list-style: none;
		}

		&__row {
			display: flex;
			align-items: center;
			gap: 12px;
			min-height: 48px;
			padding: 10px 14px;

			& + & {
				border-top: var(--border-base) solid var(--color-border);
			}

			&--blocker {
				gap: 12px;
			}
		}

		&__kind {
			flex: 1;
			color: var(--color-text);
			font-size: var(--typography--fontSize-label);
			font-weight: 500;
		}

		&__count {
			color: var(--color-heading);
			font-size: var(--typography--fontSize-label);
			font-weight: 700;
		}

		&__bone {
			display: block;
			border-radius: var(--radius-small);
			background: var(--color-border);

			&--tile {
				width: 24px;
				height: 24px;
				border-radius: var(--radius-base);
			}

			&--label {
				width: 120px;
				height: 10px;
			}
		}

		&__card {
			display: flex;
			align-items: center;
			gap: 12px;
			padding: 12px 14px;
			border: var(--border-base) solid var(--color-client--surface-edge);
			border-radius: 12px;
			background: var(--color-surface);

			> span {
				display: grid;
				gap: 2px;
			}
		}

		&__card-title,
		&__when {
			color: var(--color-heading);
			font-size: var(--typography--fontSize-label);
			font-weight: 600;
		}

		&__why {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__next {
			margin: var(--space-small) 0 0;
			color: var(--color-client--onSurface);
			font-size: var(--typography--fontSize-small);
			font-weight: 600;
			letter-spacing: 0.06em;
			text-transform: uppercase;
		}

		&__steps {
			display: grid;
			gap: 14px;
			margin: 0;
			padding: 0;
			list-style: none;
		}

		&__step {
			position: relative;
			display: flex;
			gap: 12px;

			> span:last-child {
				display: grid;
				gap: 2px;
			}

			&:not(:last-child)::after {
				position: absolute;
				top: 28px;
				bottom: -14px;
				left: 13px;
				width: 2px;
				background: var(--color-client--surface-edge);
				content: '';
			}

			&--last .client-delete__dot,
			&--last .client-delete__when {
				color: var(--color-critical);
			}
		}

		&__dot {
			display: grid;
			flex: 0 0 auto;
			width: 28px;
			height: 28px;
			place-items: center;
			border: var(--border-base) solid var(--color-client--surface-edge);
			border-radius: var(--radius-circle);
			color: var(--color-client);
			background: var(--color-surface);

			:global(svg) {
				width: 14px;
				height: 14px;
			}
		}

		&__step-line {
			color: var(--color-client--onSurface);
			font-size: var(--typography--fontSize-small);
		}

		&__actions {
			display: flex;
			gap: var(--space-small);
		}

		&__refusal {
			display: flex;
			flex-direction: column;
			gap: 14px;
		}

		&__intro {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-label);
		}

		&__blocker {
			display: grid;
			flex: 1;
			gap: 2px;
			min-width: 0;
		}

		&__blocker-title {
			color: var(--color-heading);
			font-size: var(--typography--fontSize-label);
			font-weight: 600;
		}

		&__amount {
			color: var(--color-warning--onSurface);
		}

		&__blocker-how {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}
	}
</style>
