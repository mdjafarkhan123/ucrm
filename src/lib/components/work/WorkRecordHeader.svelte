<script lang="ts">
	import type { Snippet } from 'svelte';
	import Avatar from '$lib/components/ui/Avatar.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import DropdownMenu from '$lib/components/ui/DropdownMenu.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import StatusBadge from '$lib/components/ui/StatusBadge.svelte';
	import RecordFactsList from './RecordFactsList.svelte';
	import type { RecordFact, StatusTone } from './types';
	import historyIcon from '@tabler/icons/outline/history.svg?raw';
	import pencilIcon from '@tabler/icons/outline/pencil.svg?raw';
	import mapPinIcon from '@tabler/icons/outline/map-pin.svg?raw';
	import phoneIcon from '@tabler/icons/outline/phone.svg?raw';
	import mailIcon from '@tabler/icons/outline/mail.svg?raw';

	// The card at the top of every record page — client, request, quote, job, invoice and payment (Pencil
	// "Record header · C", approved 2026-10-20). One part for all six; only its data changes:
	//
	//   coloured top   the record tile and status pill, the actions at the right, then the title. The top
	//                  takes the record type's own soft colour, never the status's — the pill carries that.
	//   client line    who the work is for, with their address, phone and email as plain links. The client
	//                  page hands in its own line instead (its address and Message / Request a review).
	//   facts          up to four facts the page chooses, in even columns.
	//   foot           the Request → Paid track on a work record, or the client page's tabs.
	//
	// The pencil swaps the title for a field where it sits, the way Jobber does it. The page owns the text
	// being typed and saves it with everything else from the save bar.
	type MenuItem = {
		label: string;
		icon?: string;
		onSelect: () => void;
		destructive?: boolean;
		disabled?: boolean;
	};

	type PrimaryAction = {
		label: string;
		/** A Tabler icon (raw SVG) drawn before the label. */
		icon?: string;
		onclick?: (event: MouseEvent) => void;
		href?: string;
		disabled?: boolean;
		loading?: boolean;
		/** Fires on hover, before the press. Start loading whatever the action opens. */
		onhover?: () => void;
	};

	/** Who the record is for, on the line under the coloured top. */
	export type HeaderClient = {
		name: string;
		/** The client's own page. Omit and the name is plain text. */
		href?: string;
		/** The client's id, for their initials' avatar. */
		avatarId?: string;
		/** The address on one line; it opens in Google Maps. Null shows `addressEmpty`. */
		address?: string | null;
		addressEmpty?: string;
		phone?: string | null;
		email?: string | null;
		/** For a record that never carries an address or a phone (a payment), so nothing nags about one. */
		hideAddress?: boolean;
		hidePhone?: boolean;
	};

	let {
		icon,
		recordType,
		title,
		statusLabel,
		statusTone = 'informative',
		badges,
		primaryAction,
		menuItems = [],
		actions,
		onHistory,
		onHistoryHover,
		onEditTitle,
		editLabel,
		editingTitle = false,
		titleDraft = $bindable(''),
		titleLabel,
		titleMaxLength = 160,
		client,
		line,
		facts = [],
		factsAction,
		body,
		track,
		tabs,
		class: className = ''
	}: {
		/** Tabler icon for this kind of record, imported with `?raw`. */
		icon: string;
		/** "Client", "Request", "Quote", "Job", "Invoice" or "Payment": names the controls out loud and picks
		 *  the coloured top. */
		recordType: string;
		title: string;
		statusLabel: string;
		statusTone?: StatusTone;
		/** Extra status context beside the pill, e.g. a quote's deposit readiness. */
		badges?: Snippet;
		/** The one action that moves this record to its next step. Omit where there isn't one. */
		primaryAction?: PrimaryAction;
		menuItems?: MenuItem[];
		/** Buttons drawn before the pencil, e.g. the client's Restore. */
		actions?: Snippet;
		/** Opens the record's history panel. Omit and the button is not drawn. */
		onHistory?: () => void;
		/** Fires when the history button is reached, so the panel's own data can start loading. */
		onHistoryHover?: () => void;
		/** Draws the pencil. Omit it for a record nobody may rename. */
		onEditTitle?: () => void;
		/** Names the pencil; defaults to "Edit {title}". */
		editLabel?: string;
		/** True while the title is being renamed: the heading becomes a field in the same place. */
		editingTitle?: boolean;
		/** The name being typed. Bound, so the page can save it and throw it away. */
		titleDraft?: string;
		/** Defaults to "Request title", "Quote title", and so on. */
		titleLabel?: string;
		titleMaxLength?: number;
		client?: HeaderClient;
		/** The client page's own line in place of `client`. */
		line?: Snippet;
		facts?: RecordFact[];
		/** A control at the end of the facts row, e.g. the invoice's "Edit the terms and dates" pencil. */
		factsAction?: Snippet;
		/** Drawn in place of the line and facts, e.g. the client details form while it is open. */
		body?: Snippet;
		/** The record's place on Request → Quote → Job → Invoice → Paid. Normally `RecordTrack`. */
		track?: Snippet;
		/** The page's tab row, drawn on the band along the card's foot. */
		tabs?: Snippet;
		class?: string;
	} = $props();

	// A payment belongs to the money side, so it shares the invoice's blue.
	const tone = $derived.by(() => {
		const kind = recordType.toLowerCase();
		return kind === 'payment' ? 'invoice' : kind;
	});

	const titleFieldId = $derived(`${recordType.toLowerCase().replace(/\s+/g, '-')}-title`);

	const mapsHref = (address: string) =>
		`https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(address)}`;

	// The cursor belongs in the field the pencil just opened, so renaming is one click and then typing.
	let titleField = $state<HTMLDivElement>();
	$effect(() => {
		if (editingTitle) titleField?.querySelector('input')?.focus();
	});
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<section
	class={`record-header ${className}`}
	style:--record-tone={`var(--color-${tone})`}
	style:--record-surface={`var(--color-${tone}--surface)`}
	aria-label="{recordType} summary"
>
	<div class="record-header__top">
		<div class="record-header__row">
			<span class="record-header__tile" aria-hidden="true">{@html icon}</span>
			<div class="record-header__status">
				<StatusBadge status={statusTone}>{statusLabel}</StatusBadge>
				{#if badges}{@render badges()}{/if}
			</div>

			<div class="record-header__actions">
				{#if actions}{@render actions()}{/if}
				{#if onEditTitle && !editingTitle}
					<Button
						variant="secondary"
						iconOnly
						label={editLabel ?? `Edit ${title}`}
						onclick={onEditTitle}
					>
						{@html pencilIcon}
					</Button>
				{/if}
				{#if onHistory}
					<Button
						variant="secondary"
						iconOnly
						label="{recordType} history"
						onclick={onHistory}
						onhover={onHistoryHover}
					>
						{@html historyIcon}
					</Button>
				{/if}
				{#if menuItems.length > 0}
					<DropdownMenu
						items={menuItems}
						triggerText="More"
						triggerLabel="More {recordType.toLowerCase()} actions"
					/>
				{/if}
				{#if primaryAction}
					<Button
						variant="primary"
						href={primaryAction.href}
						onclick={primaryAction.onclick}
						disabled={primaryAction.disabled}
						loading={primaryAction.loading}
						onhover={primaryAction.onhover}
					>
						{#if primaryAction.icon}
							<span class="record-header__action-icon" aria-hidden="true"
								>{@html primaryAction.icon}</span
							>
						{/if}
						{primaryAction.label}
					</Button>
				{/if}
			</div>
		</div>

		{#if editingTitle}
			<div class="record-header__title-field" bind:this={titleField}>
				<Input
					id={titleFieldId}
					label={titleLabel ?? `${recordType} title`}
					bind:value={titleDraft}
					maxlength={titleMaxLength}
				/>
			</div>
		{:else}
			<h1 class="record-header__title">{title}</h1>
		{/if}
	</div>

	{#if body}
		<div class="record-header__body">{@render body()}</div>
	{:else}
		{#if line}
			<div class="record-header__line">{@render line()}</div>
		{:else if client}
			<div class="record-header__line">
				{#if client.avatarId}
					<span class="record-header__avatar" aria-hidden="true">
						<Avatar id={client.avatarId} name={client.name} size="base" />
					</span>
				{/if}
				<div class="record-header__client">
					<p class="record-header__name">
						{#if client.href}
							<!-- The caller resolves the path; this card only renders what it is handed. -->
							<!-- eslint-disable-next-line svelte/no-navigation-without-resolve -->
							<a href={client.href}>{client.name}</a>
						{:else}
							{client.name}
						{/if}
					</p>
					<ul class="record-header__contact">
						{#if !client.hideAddress}
							<li class="record-header__contact-item record-header__contact-item--address">
								<span class="record-header__contact-icon" aria-hidden="true"
									>{@html mapPinIcon}</span
								>
								{#if client.address}
									<a
										href={mapsHref(client.address)}
										target="_blank"
										rel="noopener noreferrer"
										title="{client.address} · Click to open in Google Maps">{client.address}</a
									>
								{:else}
									<span class="record-header__blank">{client.addressEmpty ?? 'No address yet'}</span
									>
								{/if}
							</li>
						{/if}
						{#if !client.hidePhone}
							<li class="record-header__contact-item record-header__contact-item--phone">
								<span class="record-header__contact-icon" aria-hidden="true">{@html phoneIcon}</span
								>
								{#if client.phone}
									<a href={`tel:${client.phone}`}>{client.phone}</a>
								{:else}
									<span class="record-header__blank">No phone number yet</span>
								{/if}
							</li>
						{/if}
						<li class="record-header__contact-item record-header__contact-item--email">
							<span class="record-header__contact-icon" aria-hidden="true">{@html mailIcon}</span>
							{#if client.email}
								<a href={`mailto:${client.email}`}>{client.email}</a>
							{:else}
								<span class="record-header__blank">No email yet</span>
							{/if}
						</li>
					</ul>
				</div>
			</div>
		{/if}

		{#if facts.length > 0}
			<div class="record-header__facts">
				<RecordFactsList {facts} />
				{#if factsAction}<div class="record-header__facts-action">{@render factsAction()}</div>{/if}
			</div>
		{/if}
	{/if}

	{#if tabs}
		<div class="record-header__tabs">{@render tabs()}</div>
	{:else if track}
		<div class="record-header__track">{@render track()}</div>
	{/if}
</section>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.record-header {
		display: flex;
		flex-direction: column;
		overflow: hidden;
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-large);
		background: var(--color-surface);

		&__top {
			display: flex;
			flex-direction: column;
			gap: 14px;
			padding: var(--space-medium) var(--space-large) 22px;
			background: var(--record-surface);
		}

		&__row {
			display: flex;
			align-items: center;
			gap: 10px;
		}

		&__tile {
			display: inline-grid;
			flex: 0 0 auto;
			width: 40px;
			height: 40px;
			place-items: center;
			border-radius: var(--radius-tile-large);
			color: var(--record-tone);
			background: var(--color-surface);

			:global(svg) {
				display: block;
				width: 20px;
				height: 20px;
			}
		}

		// The pill sits on white so it reads on any record's colour.
		&__status {
			display: flex;
			flex: 1 1 auto;
			min-width: 0;
			flex-wrap: wrap;
			align-items: center;
			gap: var(--space-small);

			> :global(.status-badge) {
				background: var(--color-surface);
			}
		}

		&__actions {
			display: flex;
			flex: 0 0 auto;
			align-items: center;
			gap: var(--space-small);
			white-space: nowrap;
		}

		&__action-icon {
			display: inline-flex;

			:global(svg) {
				display: block;
				width: 16px;
				height: 16px;
			}
		}

		&__title {
			overflow-wrap: anywhere;
			color: var(--color-heading);
			font-size: 26px;
			font-weight: 700;
			letter-spacing: -0.6px;
			line-height: 1.2;
		}

		&__title-field {
			min-width: 0;
		}

		&__line {
			display: flex;
			min-width: 0;
			align-items: center;
			gap: var(--space-slim);
			padding: var(--space-base) var(--space-large);
			border-bottom: var(--border-base) solid var(--color-border);

			// Buttons on the line (the client's Message, Request a review) keep their size; the address gives way.
			> :global(.button) {
				flex: 0 0 auto;
				white-space: nowrap;
			}
		}

		&__avatar :global(.avatar) {
			width: 36px;
			height: 36px;
			border: 0;
			color: var(--color-client--onSurface);
			background: var(--color-client--surface);
			font-size: var(--typography--fontSize-small);
		}

		&__client {
			display: flex;
			flex: 1 1 auto;
			flex-direction: column;
			gap: 2px;
			min-width: 0;
		}

		&__name {
			overflow: hidden;
			color: var(--color-heading);
			font-size: var(--typography--fontSize-base);
			font-weight: 600;
			text-overflow: ellipsis;
			white-space: nowrap;

			a {
				color: inherit;
				text-decoration: none;

				&:hover {
					color: var(--color-interactive);
					text-decoration: underline;
				}
			}
		}

		&__contact {
			display: flex;
			min-width: 0;
			align-items: center;
			gap: var(--space-base);
			margin: 0;
			padding: 0;
			list-style: none;
		}

		&__contact-item {
			--contact-tone: var(--color-client);
			display: inline-flex;
			flex: 0 0 auto;
			min-width: 0;
			align-items: center;
			gap: 6px;
			color: var(--color-text);
			font-size: var(--typography--fontSize-label);
			font-weight: 500;

			a {
				overflow: hidden;
				color: inherit;
				text-decoration: none;
				text-overflow: ellipsis;
				white-space: nowrap;

				&:hover {
					color: var(--color-interactive);
					text-decoration: underline;
				}
			}

			// A long address gives way first; its whole text is in the link's hover title.
			&--address {
				flex: 0 1 auto;
			}

			&--phone {
				--contact-tone: var(--color-time);
			}

			&--email {
				--contact-tone: var(--color-conversation);
			}
		}

		&__contact-icon {
			display: inline-flex;
			flex: 0 0 auto;
			color: var(--contact-tone);

			:global(svg) {
				display: block;
				width: 14px;
				height: 14px;
			}
		}

		&__blank {
			color: var(--color-text--secondary);
			white-space: nowrap;
		}

		&__facts {
			display: flex;
			align-items: flex-start;
			gap: var(--space-base);
			padding: var(--space-base) var(--space-large) var(--space-medium);

			> :global(.record-facts) {
				flex: 1 1 auto;
				min-width: 0;
			}
		}

		&__facts-action {
			flex: 0 0 auto;
		}

		&__body {
			padding: var(--space-base) var(--space-large) var(--space-medium);
		}

		&__track {
			padding: var(--space-slim) var(--space-large);
			border-top: var(--border-base) solid var(--color-border);
			background: var(--color-surface--background--subtle);
		}

		// The page tabs ride the band itself, with no track behind them (tabs.md, "Page tabs on a record").
		&__tabs {
			padding: 10px var(--space-medium);
			border-top: var(--border-base) solid var(--color-border);
			background: var(--color-surface--background--subtle);

			:global(.tabs__list) {
				padding: 0;
				background: transparent;
			}
		}

		// The coloured top already ends the card when nothing follows it.
		&__top:last-child {
			padding-bottom: var(--space-large);
		}
	}

	@media (max-width: 767px) {
		.record-header {
			&__top {
				padding: var(--space-base);
			}

			&__row {
				flex-wrap: wrap;
			}

			&__actions {
				flex-wrap: wrap;
				width: 100%;
			}

			&__title {
				font-size: var(--typography--fontSize-largest);
			}

			&__line,
			&__facts,
			&__body,
			&__track {
				padding-right: var(--space-base);
				padding-left: var(--space-base);
			}

			&__line {
				flex-wrap: wrap;
			}

			&__contact {
				flex-wrap: wrap;
				gap: 6px var(--space-base);
			}
		}
	}
</style>
