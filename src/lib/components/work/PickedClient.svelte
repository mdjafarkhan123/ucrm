<script lang="ts">
	import IconTile from '$lib/components/ui/IconTile.svelte';
	import type { Snippet } from 'svelte';
	import Avatar from '$lib/components/ui/Avatar.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import phoneIcon from '@tabler/icons/outline/phone.svg?raw';
	import mailIcon from '@tabler/icons/outline/mail.svg?raw';
	import mapPinIcon from '@tabler/icons/outline/map-pin.svg?raw';
	import switchIcon from '@tabler/icons/outline/arrows-exchange.svg?raw';
	import lockIcon from '@tabler/icons/outline/lock.svg?raw';

	// The client a create form has picked, shown as a box instead of a filled-in search field (New job
	// `zUFDO`): who they are, how to reach them, and the property the work is at. The form decides what
	// "Change client" and "Change property" do; a form whose client is fixed (a converted request) shows a
	// lock and the reason instead.
	let {
		id,
		name,
		subtitle,
		phone = null,
		email = null,
		property,
		propertyHint,
		lockedReason,
		onChangeClient,
		onChangeProperty,
		propertyPicker
	}: {
		/** The client's id, for their avatar colour. */
		id: string;
		name: string;
		/** A quiet line under the name, e.g. the company. */
		subtitle?: string | null;
		phone?: string | null;
		email?: string | null;
		/** The work's address, on one line. */
		property: string;
		/** A quiet line under the address, e.g. "Home · Sarah has 2 properties". */
		propertyHint?: string;
		/** Set when the client cannot change, with the reason shown in place of the button. */
		lockedReason?: string;
		onChangeClient?: () => void;
		/** Offered only when the client has another property to choose. */
		onChangeProperty?: () => void;
		/** The property choice, shown under the address while it is being changed. */
		propertyPicker?: Snippet;
	} = $props();
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<div class="picked-client">
	<div class="picked-client__top">
		<Avatar {id} {name} size="medium" />
		<div class="picked-client__who">
			<p class="picked-client__name">{name}</p>
			{#if subtitle}<p class="picked-client__hint">{subtitle}</p>{/if}
		</div>
		{#if lockedReason}
			<span class="picked-client__locked">
				<span class="picked-client__locked-icon" aria-hidden="true">{@html lockIcon}</span>
				{lockedReason}
			</span>
		{:else if onChangeClient}
			<Button variant="secondary" size="small" onclick={onChangeClient}>
				<span class="picked-client__button-icon" aria-hidden="true">{@html switchIcon}</span>
				Change client
			</Button>
		{/if}
	</div>

	{#if phone || email}
		<ul class="picked-client__contact">
			{#if phone}
				<li>
					<IconTile icon={phoneIcon} tone="conversation" size={24} />
					{phone}
				</li>
			{/if}
			{#if email}
				<li>
					<IconTile icon={mailIcon} tone="conversation" size={24} />
					{email}
				</li>
			{/if}
		</ul>
	{/if}

	<div class="picked-client__property">
		<IconTile icon={mapPinIcon} tone="client" size={32} />
		<div class="picked-client__who">
			<p class="picked-client__address">{property}</p>
			{#if propertyHint}<p class="picked-client__hint">{propertyHint}</p>{/if}
		</div>
		{#if onChangeProperty && !propertyPicker}
			<Button variant="secondary" size="small" onclick={onChangeProperty}>
				{@html mapPinIcon}Change property</Button
			>
		{/if}
	</div>
	{#if propertyPicker}
		<div class="picked-client__picker">{@render propertyPicker()}</div>
	{/if}
</div>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.picked-client {
		display: flex;
		flex-direction: column;
		gap: var(--space-slim);
		padding: var(--space-base);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-large);
		background: var(--color-surface);

		&__top,
		&__property {
			display: flex;
			align-items: center;
			gap: var(--space-slim);
		}

		&__property {
			padding-top: var(--space-slim);
			border-top: var(--border-base) solid var(--color-border);
		}

		&__who {
			display: grid;
			flex: 1 1 auto;
			min-width: 0;
			gap: 2px;
		}

		&__name {
			color: var(--color-heading);
			font-size: var(--typography--fontSize-large);
			font-weight: 600;
		}

		&__address {
			color: var(--color-heading);
			font-size: var(--typography--fontSize-base);
			font-weight: 600;
		}

		&__name,
		&__address,
		&__hint {
			margin: 0;
		}

		&__hint {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__button-icon,
		&__locked-icon {
			display: inline-flex;

			:global(svg) {
				display: block;
				width: 16px;
				height: 16px;
			}
		}

		&__locked {
			display: inline-flex;
			flex: 0 0 auto;
			align-items: center;
			gap: 6px;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__locked-icon {
			color: var(--color-icon--secondary);
		}

		&__contact {
			display: flex;
			flex-wrap: wrap;
			gap: var(--space-small) var(--space-large);
			margin: 0;
			padding: 0;
			list-style: none;

			li {
				display: inline-flex;
				align-items: center;
				gap: 6px;
				color: var(--color-text);
				font-size: var(--typography--fontSize-base);
			}
		}
	}
</style>
