<script lang="ts">
	import type { Snippet } from 'svelte';
	import { resolve } from '$app/paths';
	import Button from '$lib/components/ui/Button.svelte';
	import PencilButton from '$lib/components/ui/PencilButton.svelte';
	import DropdownMenu from '$lib/components/ui/DropdownMenu.svelte';
	import StatusBadge from '$lib/components/ui/StatusBadge.svelte';
	import RecordFactsList from '$lib/components/work/RecordFactsList.svelte';
	import type { RecordFact } from '$lib/components/work/types';
	import QuickContactButtons from '$lib/components/work/QuickContactButtons.svelte';
	import ManualEmailDialog from '$lib/components/clients/ManualEmailDialog.svelte';
	import RequestReviewButton from '$lib/components/reviews/RequestReviewButton.svelte';
	import type { ClientDetail } from '$lib/clients/api';
	import phoneIcon from '@tabler/icons/outline/phone.svg?raw';
	import mailIcon from '@tabler/icons/outline/mail.svg?raw';
	import receiptIcon from '@tabler/icons/outline/receipt.svg?raw';
	import calendarCheckIcon from '@tabler/icons/outline/calendar-check.svg?raw';
	import historyIcon from '@tabler/icons/outline/history.svg?raw';
	import externalIcon from '@tabler/icons/outline/external-link.svg?raw';
	import archiveIcon from '@tabler/icons/outline/archive.svg?raw';
	import mergeIcon from '@tabler/icons/outline/arrow-merge.svg?raw';
	import chevronDownIcon from '@tabler/icons/outline/chevron-down.svg?raw';

	// The card at the top of a client's page, in the App look: where the client stands and the page's
	// actions on the first row, the name with the ways to reach them under it, a strip of their contact
	// details, and the page's tabs along the foot. Money and job counts live in the Lifetime card in the rail.
	// History matches the work records' own header: one icon button that swaps the rail, warmed on hover.
	//
	// Editing follows Jobber: the name's pencil turns this card into the details form where it sits (the
	// page hands it in as `editor`), and the ... menu opens the full edit page in a new tab.
	let {
		client,
		onEdit,
		editing = false,
		editor,
		tabs,
		onHistory,
		onHistoryHover,
		canMessage = true,
		onArchive,
		onRestore,
		onMerge,
		archiving = false
	}: {
		client: ClientDetail;
		onEdit: () => void;
		/** True while the details form is open in place of the name and contact facts. */
		editing?: boolean;
		editor?: Snippet;
		/** The page's tab row, drawn along the foot of the card. */
		tabs?: Snippet;
		/** False for a member without conversations.send, who would only be refused on Send. */
		canMessage?: boolean;
		onHistory?: () => void;
		onHistoryHover?: () => void;
		/** Both absent for a member without customers.archive, who would only be refused by the API. */
		onArchive?: () => void;
		onRestore?: () => void;
		/** Absent for a member without customers.merge. */
		onMerge?: () => void;
		archiving?: boolean;
	} = $props();

	// Directions go to the client's main property, written the way a map search reads it.
	const directionsAddress = $derived.by(() => {
		const property = client.primary_property ?? client.properties[0];
		if (!property) return null;
		const parts = [
			property.address_line1,
			property.address_line2,
			property.city,
			property.state_region,
			property.postal_code
		].filter((part): part is string => typeof part === 'string' && part.length > 0);
		return parts.length ? parts.join(', ') : null;
	});

	const isCustomer = $derived(client.lifecycle_status === 'customer');
	const isArchived = $derived(client.archived_at !== null);
	const propertyCount = $derived(client.properties.length);

	const monthFormat = new Intl.DateTimeFormat(undefined, { month: 'short', year: 'numeric' });
	const clientSince = $derived(
		client.created_at ? monthFormat.format(new Date(client.created_at)) : ''
	);

	let manualEmailOpen = $state(false);

	const menuItems = $derived([
		{
			label: 'Edit client details',
			icon: externalIcon,
			onSelect: () =>
				window.open(
					resolve('/(app)/clients/[id=uuid]/edit', { id: client.id }),
					'_blank',
					'noopener'
				)
		},
		// Jobber puts Archive in this same ... menu, and swaps it for an Unarchive button once the client
		// is archived — which is why restoring is a button beside the menu, not an item inside it.
		...(onMerge ? [{ label: 'Merge client', icon: mergeIcon, onSelect: onMerge }] : []),
		...(onArchive && !isArchived
			? [{ label: 'Archive client', icon: archiveIcon, onSelect: onArchive }]
			: [])
	]);

	const facts = $derived<RecordFact[]>([
		{
			label: 'Main phone',
			value: client.phone,
			empty: 'Not added yet',
			icon: phoneIcon,
			fixed: true,
			href: client.phone ? `tel:${client.phone}` : undefined
		},
		{
			label: 'Main email',
			value: client.email,
			empty: 'Not added yet',
			icon: mailIcon,
			href: client.email ? `mailto:${client.email}` : undefined
		},
		...(client.billing_email
			? [
					{
						label: 'Billing email',
						value: client.billing_email,
						icon: receiptIcon,
						href: `mailto:${client.billing_email}`
					}
				]
			: []),
		{ label: 'Client since', value: clientSince, icon: calendarCheckIcon, fixed: true }
	]);
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<section class="client-header" aria-label="Client summary">
	<div class="client-header__top">
		<div class="client-header__status">
			{#if isArchived}
				<StatusBadge status="inactive">Archived</StatusBadge>
			{:else}
				<StatusBadge status={isCustomer ? 'success' : 'informative'}>
					{isCustomer ? 'Customer' : 'Lead'}
				</StatusBadge>
			{/if}
			<span class="client-header__eyebrow">Client</span>
			<span class="client-header__sep" aria-hidden="true"></span>
			<span class="client-header__meta">
				{propertyCount === 1 ? '1 property' : `${propertyCount} properties`}
			</span>
		</div>

		<div class="client-header__buttons">
			{#if isArchived && onRestore}
				<Button
					variant="secondary"
					class="client-header__button"
					loading={archiving}
					onclick={onRestore}>Restore</Button
				>
			{/if}
			{#if onHistory}
				<button
					type="button"
					class="client-header__icon-button"
					aria-label="Client history"
					title="Client history"
					onclick={onHistory}
					onmouseenter={onHistoryHover}
					onfocus={onHistoryHover}
				>
					<span aria-hidden="true">{@html historyIcon}</span>
				</button>
			{/if}
			<DropdownMenu
				items={menuItems}
				triggerLabel="More client actions"
				triggerClass="client-header__more"
			>
				{#snippet trigger()}
					More
					<span class="client-header__chevron" aria-hidden="true">{@html chevronDownIcon}</span>
				{/snippet}
			</DropdownMenu>
		</div>
	</div>

	{#if editing && editor}
		<div class="client-header__editor">{@render editor()}</div>
	{:else}
		<div class="client-header__identity">
			<div class="client-header__name">
				<h1 title={client.display_name}>{client.display_name}</h1>
				<PencilButton size="base" onclick={onEdit} label="Edit {client.display_name}" />
			</div>

			<div class="client-header__actions">
				<div class="client-header__quick">
					<QuickContactButtons phone={client.phone} address={directionsAddress} />
				</div>
				{#if canMessage}
					<Button
						variant="secondary"
						class="client-header__button"
						onclick={() => (manualEmailOpen = true)}
					>
						<span class="client-header__button-icon" aria-hidden="true">{@html mailIcon}</span>
						Message
					</Button>
				{/if}
				{#if client.can_request_review}
					<RequestReviewButton
						target={{ clientId: client.id }}
						size="base"
						class="client-header__button"
					/>
				{/if}
			</div>
		</div>

		<div class="client-header__facts">
			<RecordFactsList {facts} neutralIcons />
		</div>
	{/if}

	{#if tabs}<div class="client-header__tabs">{@render tabs()}</div>{/if}
</section>

{#if manualEmailOpen}
	<ManualEmailDialog open={manualEmailOpen} {client} onClose={() => (manualEmailOpen = false)} />
{/if}

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.client-header__quick {
		display: inline-flex;
		align-items: center;
		gap: 6px;
	}

	.client-header {
		display: flex;
		flex-direction: column;
		padding: 24px 28px 0;
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface);

		&__top {
			display: flex;
			align-items: center;
			justify-content: space-between;
			gap: var(--space-base);
		}

		&__status {
			display: flex;
			align-items: center;
			gap: 10px;
			min-width: 0;
			color: var(--color-text--secondary);
			font-size: 12px;
		}

		&__eyebrow {
			font-weight: 600;
			letter-spacing: 0.6px;
			text-transform: uppercase;
		}

		&__sep {
			width: 3px;
			height: 3px;
			border-radius: 50%;
			background: var(--color-icon--secondary);
		}

		&__meta {
			font-weight: 500;
		}

		&__buttons,
		&__actions {
			display: flex;
			align-items: center;
			gap: var(--space-small);
		}

		&__buttons {
			flex: 0 0 auto;
		}

		&__actions {
			flex: 0 0 auto;
			justify-content: flex-end;
		}

		// Same square icon button the work records' header uses, so History reads identically wherever it is.
		&__icon-button {
			display: inline-flex;
			box-sizing: border-box;
			width: 40px;
			height: 40px;
			flex: 0 0 auto;
			align-items: center;
			justify-content: center;
			padding: 0;
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-base);
			background: var(--color-surface);
			color: var(--color-text--secondary);
			cursor: pointer;
			transition: all var(--timing-base) ease-out;

			:global(svg) {
				display: block;
				width: 18px;
				height: 18px;
			}

			&:hover,
			&:focus-visible {
				border-color: var(--color-interactive--subtle--hover);
				background: var(--color-surface--hover);
				color: var(--color-interactive--subtle--hover);
			}

			&:active {
				background: var(--color-surface--active);
			}

			&:focus-visible {
				outline: transparent;
				box-shadow: var(--shadow-focus);
			}
		}

		&__identity {
			display: flex;
			align-items: center;
			justify-content: space-between;
			gap: var(--space-base);
			padding: 18px 0 24px;
		}

		&__name {
			display: flex;
			align-items: center;
			gap: 12px;
			min-width: 0;
			flex: 1 1 auto;

			h1 {
				overflow: hidden;
				color: var(--color-heading);
				font-size: var(--typography--fontSize-largest);
				font-weight: 700;
				letter-spacing: -0.8px;
				line-height: 1.15;
				text-overflow: ellipsis;
				white-space: nowrap;
			}
		}

		&__editor {
			padding: 18px 0 24px;
		}

		&__facts {
			padding: 18px 0 22px;
			border-top: var(--border-base) solid var(--color-border);
		}

		// The tab row closes the card. Its own divider is the card's edge.
		&__tabs {
			:global(.tabs__list) {
				gap: 28px;
				margin-bottom: 0;
				border-bottom: 0;
			}
			:global(.tabs__tab) {
				height: auto;
				padding: 0 0 12px;
				border-radius: 0;
				background: transparent;
				font-size: var(--typography--fontSize-base);
			}
			:global(.tabs__tab:focus-visible) {
				border-radius: var(--radius-small);
				background: transparent;
				box-shadow: var(--shadow-focus);
			}
			:global(.tabs__tab[data-state='active'])::after {
				height: 2px;
			}
		}
	}

	:global(.client-header__button-icon) {
		display: inline-flex;
		color: var(--color-text--secondary);

		:global(svg) {
			width: 16px;
			height: 16px;
		}
	}
	:global(.client-header__more) {
		display: inline-flex;
		align-items: center;
		gap: 6px;
		height: 40px;
		padding: 0 14px;
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		color: var(--color-heading);
		background: var(--color-surface);
		font-size: var(--typography--fontSize-base);
		font-weight: 600;
		cursor: pointer;
		transition: all var(--timing-base) ease-out;

		&:hover,
		&:focus-visible {
			border-color: var(--color-interactive--subtle--hover);
			background: var(--color-surface--hover);
		}
		&:focus-visible {
			outline: transparent;
			box-shadow: var(--shadow-focus);
		}
	}
	:global(.client-header__chevron) {
		display: inline-flex;
		color: var(--color-text--secondary);

		:global(svg) {
			width: 16px;
			height: 16px;
		}
	}

	// A narrower laptop has no room for the name and three buttons side by side, so the buttons drop under it.
	@media (max-width: 1359px) {
		.client-header__identity {
			flex-wrap: wrap;
		}
		.client-header__actions {
			flex-wrap: wrap;
			justify-content: flex-start;
		}
	}

	@media (max-width: 767px) {
		.client-header {
			padding: var(--space-base) var(--space-base) 0;

			&__top {
				flex-wrap: wrap;
			}
			&__buttons,
			&__actions {
				flex-wrap: wrap;
			}
		}
	}
</style>
