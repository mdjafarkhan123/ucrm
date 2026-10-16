<script lang="ts">
	import DropdownMenu from '$lib/components/ui/DropdownMenu.svelte';
	import Avatar from '$lib/components/ui/Avatar.svelte';
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
		href,
		addresses = [],
		phone = null,
		email = null,
		menuItems = [],
		avatarId,
		class: className = ''
	}: {
		name: string;
		/** Where the client's own page lives. Omit and the name renders as plain text. */
		href?: string;
		addresses?: SummaryAddress[];
		phone?: string | null;
		email?: string | null;
		menuItems?: MenuItem[];
		/** The client's id. Given, the App look header draws their initials beside the name. */
		avatarId?: string;
		class?: string;
	} = $props();
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<div class={`client-summary ${className}`}>
	<div class="client-summary__top">
		{#if avatarId}
			<span class="client-summary__avatar" aria-hidden="true">
				<Avatar id={avatarId} {name} size="small" />
			</span>
		{/if}
		<h3 class="client-summary__name">
			{#if href}
				<!-- The caller resolves the path; this card only renders what it is handed. -->
				<!-- eslint-disable-next-line svelte/no-navigation-without-resolve -->
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

		<li class="client-summary__line">
			<span class="client-summary__icon" aria-hidden="true">{@html phoneIcon}</span>
			<span class="client-summary__text">
				{#if phone}
					<a href={`tel:${phone}`}>{phone}</a>
				{:else}
					<span class="client-summary__blank">No phone number yet</span>
				{/if}
			</span>
		</li>

		<li class="client-summary__line">
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
</div>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.client-summary {
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

		&__avatar {
			display: inline-flex;
			flex: 0 0 auto;
		}
	}

	// App look: no inner card. The client reads as one row — avatar and name, then address, phone and email
	// as quiet details beside it — and the actions menu sits at the far end.
	:global(.record-detail--cards) .client-summary {
		display: flex;
		flex-flow: row wrap;
		align-items: center;
		gap: 10px 20px;
		padding: 0;
		border: 0;
		border-radius: 0;
		background: transparent;

		.client-summary__top {
			display: contents;
		}
		.client-summary__name {
			flex: 0 1 auto;
			order: 1;
			font-size: var(--typography--fontSize-base);
			font-weight: 600;
		}
		.client-summary__avatar {
			order: 0;
			margin-right: -12px;
		}
		.client-summary__lines {
			display: flex;
			flex: 1 0 100%;
			flex-flow: row wrap;
			gap: 6px 20px;
			order: 4;
			min-width: 0;
		}
		.client-summary__line {
			align-items: center;
			gap: 6px;
			color: var(--color-text--secondary);
			font-weight: 500;
		}
		.client-summary__icon :global(svg) {
			width: 15px;
			height: 15px;
			margin-top: 0;
		}
		.client-summary__text {
			color: var(--color-text--secondary);
		}
		:global(.dropdown-menu__trigger) {
			order: 3;
			margin-left: auto;
		}
	}
</style>
