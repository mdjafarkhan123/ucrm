<script lang="ts">
	import type { Snippet } from 'svelte';
	import { resolve } from '$app/paths';
	import Avatar from '$lib/components/ui/Avatar.svelte';
	import Badge from '$lib/components/ui/Badge.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import PencilButton from '$lib/components/ui/PencilButton.svelte';
	import DropdownMenu from '$lib/components/ui/DropdownMenu.svelte';
	import ManualEmailDialog from '$lib/components/clients/ManualEmailDialog.svelte';
	import RequestReviewButton from '$lib/components/reviews/RequestReviewButton.svelte';
	import type { ClientDetail } from '$lib/clients/api';
	import phoneIcon from '@tabler/icons/outline/phone.svg?raw';
	import messageIcon from '@tabler/icons/outline/message.svg?raw';
	import receiptIcon from '@tabler/icons/outline/receipt.svg?raw';
	import coinIcon from '@tabler/icons/outline/coin.svg?raw';
	import fileIcon from '@tabler/icons/outline/file-text.svg?raw';
	import toolIcon from '@tabler/icons/outline/tool.svg?raw';
	import historyIcon from '@tabler/icons/outline/history.svg?raw';
	import externalIcon from '@tabler/icons/outline/external-link.svg?raw';
	import archiveIcon from '@tabler/icons/outline/archive.svg?raw';

	// The identity card at the top of a client's page: who they are, how to reach them, and how much work
	// they represent. Money and job counts have no source yet, so they read as not-yet rather than zero.
	// History matches the work records' own header: one icon button that swaps the rail, warmed on hover.
	//
	// Editing follows Jobber: the name's pencil turns this card into the details form where it sits (the
	// page hands it in as `editor`), and the ... menu opens the full edit page in a new tab.
	let {
		client,
		onEdit,
		editing = false,
		editor,
		onHistory,
		onHistoryHover,
		canMessage = true,
		onArchive,
		onRestore,
		archiving = false
	}: {
		client: ClientDetail;
		onEdit: () => void;
		/** True while the details form is open in place of the name and contact facts. */
		editing?: boolean;
		editor?: Snippet;
		/** False for a member without conversations.send, who would only be refused on Send. */
		canMessage?: boolean;
		onHistory?: () => void;
		onHistoryHover?: () => void;
		/** Both absent for a member without customers.archive, who would only be refused by the API. */
		onArchive?: () => void;
		onRestore?: () => void;
		archiving?: boolean;
	} = $props();

	const isCustomer = $derived(client.lifecycle_status === 'customer');
	const isArchived = $derived(client.archived_at !== null);

	const dateFormat = new Intl.DateTimeFormat(undefined, {
		day: 'numeric',
		month: 'short',
		year: 'numeric'
	});
	const clientSince = $derived(
		client.created_at ? dateFormat.format(new Date(client.created_at)) : '—'
	);

	// Spelled out for screen readers as well as the hover title, because a disabled button never takes
	// focus and its reason would otherwise reach mouse users only.
	const callReason = 'Calling arrives with the communications work';
	const messageReason = 'Messaging arrives with the communications work';
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
		...(onArchive && !isArchived
			? [{ label: 'Archive client', icon: archiveIcon, onSelect: onArchive }]
			: [])
	]);

	const moneyFormatters: Record<string, Intl.NumberFormat> = {};
	function formatMoney(amountMinor: number, currency: string) {
		let formatter = moneyFormatters[currency];
		if (!formatter) {
			formatter = new Intl.NumberFormat(undefined, { style: 'currency', currency });
			moneyFormatters[currency] = formatter;
		}
		return formatter.format(amountMinor / 100);
	}

	// Each figure is null when this member lacks the permission that gates it (customers.view_financials,
	// quotes.view, jobs.view) -- it then says why instead of showing a zero that may not be true.
	const summary = $derived(client.work_summary);
	const stats = $derived([
		{
			icon: coinIcon,
			label: 'Lifetime',
			value:
				summary.lifetime_billed_minor === null
					? null
					: formatMoney(summary.lifetime_billed_minor, summary.currency_code),
			waiting: 'You do not have access to this client’s billing'
		},
		{
			icon: fileIcon,
			label: 'Open quotes',
			value: summary.open_quotes_count === null ? null : String(summary.open_quotes_count),
			waiting: 'You do not have access to quotes'
		},
		{
			icon: toolIcon,
			label: 'Active jobs',
			value: summary.active_jobs_count === null ? null : String(summary.active_jobs_count),
			waiting: 'You do not have access to jobs'
		}
	]);
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<section class="client-header" aria-label="Client summary">
	<div class="client-header__top">
		<Avatar id={client.id} name={client.display_name} size="medium" />
		{#if isArchived}
			<Badge>Archived</Badge>
		{:else}
			<Badge status={isCustomer ? 'success' : 'informative'}
				>{isCustomer ? 'Customer' : 'Lead'}</Badge
			>
		{/if}
		<div class="client-header__buttons">
			{#if isArchived && onRestore}
				<Button variant="secondary" size="small" loading={archiving} onclick={onRestore}
					>Restore</Button
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
			<span class="client-header__waiting" title={callReason}>
				<Button variant="secondary" size="small" disabled>Call</Button>
				<span class="client-header__reason">{callReason}</span>
			</span>
			{#if canMessage}
				<Button variant="secondary" size="small" onclick={() => (manualEmailOpen = true)}
					>Message</Button
				>
			{/if}
			{#if client.can_request_review}
				<RequestReviewButton target={{ clientId: client.id }} />
			{/if}
			<DropdownMenu items={menuItems} triggerLabel="More client actions" />
		</div>
	</div>

	{#if editing && editor}
		{@render editor()}
	{:else}
		<div class="client-header__identity">
			<h1>{client.display_name}</h1>
			<PencilButton size="base" onclick={onEdit} label="Edit {client.display_name}" />
		</div>

		<div class="client-header__body">
			<dl class="client-header__facts">
				<div class="client-header__fact">
					<dt><span aria-hidden="true">{@html phoneIcon}</span>Main phone</dt>
					<dd>
						{#if client.phone}
							<a href={`tel:${client.phone}`}>{client.phone}</a>
						{:else}
							<span class="client-header__blank">Not added yet</span>
						{/if}
					</dd>
				</div>
				<div class="client-header__fact">
					<dt><span aria-hidden="true">{@html messageIcon}</span>Main email</dt>
					<dd>
						{#if client.email}
							<a href={`mailto:${client.email}`}>{client.email}</a>
						{:else}
							<span class="client-header__blank">Not added yet</span>
						{/if}
					</dd>
				</div>
				{#if client.billing_email}
					<div class="client-header__fact">
						<dt><span aria-hidden="true">{@html receiptIcon}</span>Billing email</dt>
						<dd><a href={`mailto:${client.billing_email}`}>{client.billing_email}</a></dd>
					</div>
				{/if}
				<div class="client-header__fact">
					<dt>Client since</dt>
					<dd>{clientSince}</dd>
				</div>
			</dl>

			<ul class="client-header__stats">
				{#each stats as stat (stat.label)}
					<li class="client-header__stat">
						<span class="client-header__stat-icon" aria-hidden="true">{@html stat.icon}</span>
						<span class="client-header__stat-text">
							<span class="client-header__stat-label">{stat.label}</span>
							<span class="client-header__stat-value">{stat.value ?? stat.waiting}</span>
						</span>
					</li>
				{/each}
			</ul>
		</div>
	{/if}
</section>

{#if manualEmailOpen}
	<ManualEmailDialog open={manualEmailOpen} {client} onClose={() => (manualEmailOpen = false)} />
{/if}

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.client-header__waiting {
		display: inline-flex;
		align-items: center;
	}

	.client-header__reason {
		position: absolute;
		width: 1px;
		height: 1px;
		margin: -1px;
		padding: 0;
		overflow: hidden;
		clip: rect(0 0 0 0);
		white-space: nowrap;
		border: 0;
	}

	.client-header {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);
		padding: var(--space-large);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface--background);

		&__top {
			display: flex;
			align-items: center;
			gap: var(--space-small);
		}

		&__buttons {
			display: flex;
			align-items: center;
			gap: var(--space-small);
			margin-left: auto;
		}

		// Same square icon button the work records' header uses, so History reads identically wherever it is.
		&__icon-button {
			display: inline-flex;
			box-sizing: border-box;
			width: var(--space-larger);
			height: var(--space-larger);
			flex: 0 0 auto;
			align-items: center;
			justify-content: center;
			padding: 0;
			border: var(--border-base) solid var(--color-border--interactive);
			border-radius: var(--radius-base);
			background: var(--color-surface);
			color: var(--color-interactive--subtle);
			cursor: pointer;
			transition: all var(--timing-base) ease-out;

			:global(svg) {
				display: block;
				width: 20px;
				height: 20px;
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
			gap: var(--space-small);

			h1 {
				color: var(--color-heading);
				font-size: var(--typography--fontSize-largest);
				font-weight: 700;
				line-height: var(--typography--lineHeight-tight);
			}
		}

		&__body {
			display: grid;
			grid-template-columns: minmax(0, 1fr) minmax(0, 1fr);
			gap: var(--space-large);
			align-items: start;
		}

		&__facts {
			display: flex;
			flex-direction: column;
		}

		&__fact {
			display: flex;
			align-items: center;
			justify-content: space-between;
			gap: var(--space-base);
			padding: var(--space-small) 0;

			& + & {
				border-top: var(--border-base) solid var(--color-border);
			}

			dt {
				display: flex;
				align-items: center;
				gap: var(--space-small);
				color: var(--color-text--secondary);

				:global(svg) {
					display: block;
					width: 16px;
					height: 16px;
					color: var(--color-icon--secondary);
				}
			}

			dd {
				overflow: hidden;
				color: var(--color-heading);
				font-weight: 600;
				text-overflow: ellipsis;
				white-space: nowrap;

				a {
					color: inherit;
					text-decoration: none;

					&:hover {
						text-decoration: underline;
					}
				}
			}
		}

		&__blank {
			color: var(--color-text--secondary);
			font-weight: 400;
		}

		&__stats {
			display: flex;
			flex-direction: column;
			gap: var(--space-base);
		}

		&__stat {
			display: flex;
			align-items: center;
			gap: var(--space-small);
		}

		&__stat-icon {
			display: inline-flex;
			flex: 0 0 auto;
			align-items: center;
			justify-content: center;
			width: var(--space-larger);
			height: var(--space-larger);
			border-radius: var(--radius-base);
			color: var(--color-icon);
			background: var(--color-surface);

			:global(svg) {
				display: block;
				width: 20px;
				height: 20px;
			}
		}

		&__stat-text {
			display: flex;
			min-width: 0;
			flex-direction: column;
		}

		&__stat-label {
			color: var(--color-heading);
			font-weight: 700;
		}

		&__stat-value {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}
	}

	@media (max-width: 767px) {
		.client-header {
			padding: var(--space-base);

			&__body {
				grid-template-columns: 1fr;
				gap: var(--space-base);
			}
			&__buttons {
				width: 100%;
				margin-left: 0;
			}
			&__top {
				flex-wrap: wrap;
			}
		}
	}
</style>
