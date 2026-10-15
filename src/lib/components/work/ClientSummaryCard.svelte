<script lang="ts">
	import { page } from '$app/state';
	import { resolve } from '$app/paths';
	import { createQuery } from '@tanstack/svelte-query';
	import { communicationsAccessKey, fetchCommunicationsAccess } from '$lib/communications/inbox';
	import { handOffComposerDraft } from '$lib/communications/composer-draft';
	import messageIcon from '@tabler/icons/outline/message.svg?raw';
	import navigationIcon from '@tabler/icons/outline/navigation.svg?raw';
	import DropdownMenu from '$lib/components/ui/DropdownMenu.svelte';
	import type { SummaryAddress } from './types';
	import mapPinIcon from '@tabler/icons/outline/map-pin.svg?raw';
	import phoneIcon from '@tabler/icons/outline/phone.svg?raw';
	import mailIcon from '@tabler/icons/outline/mail.svg?raw';

	// Who this piece of work is for, shown on every request, quote, job and invoice. The card names the
	// client, lists whichever addresses that record carries, and gives the two ways to reach them.
	//
	// The `...` menu is the page's, not this card's — a request offers "View client profile" and
	// "Change property", an invoice offers something else — so the items are passed in.
	type MenuItem = {
		label: string;
		icon?: string;
		onSelect: () => void;
		destructive?: boolean;
		disabled?: boolean;
	};

	let {
		name,
		clientId,
		directionsAddress,
		href,
		addresses = [],
		phone = null,
		email = null,
		menuItems = [],
		class: className = ''
	}: {
		name: string;
		clientId?: string;
		/** Service address only; a billing address is not a work destination. */
		directionsAddress?: string | null;
		/** Where the client's own page lives. Omit and the name renders as plain text. */
		href?: string;
		addresses?: SummaryAddress[];
		phone?: string | null;
		email?: string | null;
		menuItems?: MenuItem[];
		class?: string;
	} = $props();

	const initials = $derived(
		name
			.trim()
			.split(/\s+/)
			.slice(0, 2)
			.map((part) => part[0])
			.join('')
			.toUpperCase()
	);
	const access = createQuery(() => ({
		queryKey: communicationsAccessKey(page.data.user?.id ?? null),
		queryFn: fetchCommunicationsAccess,
		enabled: page.data.presentation === 'classic' && Boolean(clientId),
		staleTime: 5 * 60_000
	}));
	const canMessage = $derived(
		Boolean(clientId && access.data?.canSend && access.data?.inbox && (phone || email))
	);
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<div class={`client-summary ${className}`}>
	<div class="client-summary__top">
		<span class="client-summary__avatar" aria-hidden="true">{initials}</span>
		<h3 class="client-summary__name">
			{#if href}
				<!-- The caller resolves the path; this card only renders what it is handed. -->
				<!-- eslint-disable svelte/no-navigation-without-resolve -->
				<a {href}>{name}</a>
			{:else}
				{name}
			{/if}
		</h3>
		{#if menuItems.length > 0}
			<DropdownMenu items={menuItems} triggerLabel="Actions for {name}" />
		{/if}
	</div>

	<ul class="client-summary__lines">
		<!-- Keyed by the row object: two empty slots would otherwise share the same key. -->
		{#each addresses as address (address)}
			<li class="client-summary__line">
				<span class="client-summary__icon" aria-hidden="true">{@html mapPinIcon}</span>
				<span class="client-summary__text">
					{#if address.label}<span class="client-summary__label">{address.label}</span>{/if}
					{#if address.value}
						<span>{address.value}</span>
					{:else}
						<span class="client-summary__blank">{address.empty ?? 'No address yet'}</span>
					{/if}
				</span>
			</li>
		{/each}

		<li class="client-summary__line client-summary__line--contact">
			<span class="client-summary__icon" aria-hidden="true">{@html phoneIcon}</span>
			<span class="client-summary__text">
				{#if phone}
					<a href={`tel:${phone}`}>{phone}</a>
				{:else}
					<span class="client-summary__blank">No phone number yet</span>
				{/if}
			</span>
		</li>

		<li class="client-summary__line client-summary__line--contact">
			<span class="client-summary__icon" aria-hidden="true">{@html mailIcon}</span>
			<span class="client-summary__text">
				{#if email}
					<a href={`mailto:${email}`}>{email}</a>
				{:else}
					<span class="client-summary__blank">No email address yet</span>
				{/if}
			</span>
		</li>
	</ul>
	<div class="client-summary__actions" role="group" aria-label="Contact {name}">
		{#if phone}<a
				class="client-summary__action"
				href={`tel:${phone}`}
				aria-label="Call {name}"
				title="Call {phone}"><span aria-hidden="true">{@html phoneIcon}</span></a
			>{/if}
		{#if canMessage}
			<!-- The href starts with the resolved Communications route. -->
			<!-- eslint-disable svelte/no-navigation-without-resolve -->
			<a
				class="client-summary__action"
				href={`${resolve('/(app)/communications')}?client=${encodeURIComponent(clientId ?? '')}`}
				aria-label="Message {name}"
				title="Message {name}"
				onclick={() => {
					if (clientId)
						handOffComposerDraft({
							clientId,
							channel: phone ? 'sms' : 'email',
							subject: '',
							body: ''
						});
				}}><span aria-hidden="true">{@html messageIcon}</span></a
			>
			<!-- eslint-enable svelte/no-navigation-without-resolve -->
		{/if}
		{#if email}<a
				class="client-summary__action"
				href={`mailto:${email}`}
				aria-label="Email {name}"
				title="Email {email}"><span aria-hidden="true">{@html mailIcon}</span></a
			>{/if}
		{#if directionsAddress}<a
				class="client-summary__action"
				href={`https://www.google.com/maps/dir/?api=1&destination=${encodeURIComponent(directionsAddress)}`}
				target="_blank"
				rel="noopener noreferrer"
				aria-label="Directions to {directionsAddress}"
				title="Directions"><span aria-hidden="true">{@html navigationIcon}</span></a
			>{/if}
	</div>
</div>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.client-summary {
		&__avatar,
		&__actions {
			display: none;
		}
		display: flex;
		min-width: 0;
		flex-direction: column;
		gap: var(--space-small);
		padding: var(--space-base);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface);

		&__top {
			display: flex;
			align-items: center;
			justify-content: space-between;
			gap: var(--space-small);
		}

		&__name {
			overflow: hidden;
			color: var(--color-heading);
			font-size: var(--typography--fontSize-base);
			font-weight: 700;
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

		&__lines {
			display: flex;
			flex-direction: column;
			gap: var(--space-small);
			margin: 0;
			padding: 0;
			font-size: var(--typography--fontSize-base);
		}

		&__line {
			display: flex;
			min-width: 0;
			align-items: flex-start;
			gap: var(--space-small);
		}

		&__icon :global(svg) {
			display: block;
			width: 18px;
			height: 18px;
			margin-top: 1px;
			color: var(--color-icon--secondary);
		}

		&__text {
			display: flex;
			min-width: 0;
			flex-direction: column;
			color: var(--color-text);
			word-break: break-word;

			a {
				color: inherit;
				text-decoration: none;

				&:hover {
					text-decoration: underline;
				}
			}
		}

		&__label {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__blank {
			color: var(--color-text--secondary);
		}
	}

	:global(:root:has(.app-shell[data-presentation='classic'])) .client-summary {
		flex-direction: row;
		align-items: center;
		flex-wrap: wrap;
		gap: 12px 16px;
		padding: 0;
		border: 0;
		border-radius: 0;
		background: transparent;
		&__top {
			justify-content: flex-start;
			gap: 8px;
		}
		&__avatar {
			display: inline-flex;
			align-items: center;
			justify-content: center;
			flex-shrink: 0;
			width: 28px;
			height: 28px;
			border-radius: 50%;
			background: var(--classic2-violet-tint);
			color: var(--classic2-violet);
			font-size: 10px;
			font-weight: 700;
		}
		&__name {
			white-space: normal;
			overflow-wrap: anywhere;
			font-size: var(--classic2-font-body);
			color: var(--classic2-ink);
		}
		&__lines {
			flex: 1 1 180px;
			gap: 6px;
			font-size: var(--classic2-font-body);
		}
		&__text {
			color: var(--classic2-secondary);
		}
		&__label,
		&__blank {
			color: var(--classic2-muted);
		}
		&__line--contact {
			display: none;
		}
		&__icon :global(svg) {
			width: 15px;
			height: 15px;
			color: var(--classic2-icon-muted);
		}
		&__actions {
			display: flex;
			flex-wrap: wrap;
			gap: 6px;
			margin-left: auto;
		}
		&__action {
			display: inline-flex;
			justify-content: center;
			align-items: center;
			width: 34px;
			height: 34px;
			border-radius: 50%;
			border: 1px solid var(--classic2-border);
			background: var(--classic2-surface-soft);
			color: var(--classic2-secondary);
		}
		&__action span {
			display: inline-flex;
		}
		&__action :global(svg) {
			width: 15px;
			height: 15px;
		}
		&__action:hover {
			background: var(--classic2-chip);
			color: var(--classic2-ink);
			border-color: var(--classic2-border-control);
		}
		&__action:focus-visible,
		&__name a:focus-visible {
			outline: 2px solid var(--classic2-green);
			outline-offset: 3px;
		}
	}
</style>
