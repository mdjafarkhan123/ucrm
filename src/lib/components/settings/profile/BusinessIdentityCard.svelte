<script lang="ts">
	import type { Snippet } from 'svelte';
	import { resolve } from '$app/paths';
	import Button from '$lib/components/ui/Button.svelte';
	import IconTile from '$lib/components/ui/IconTile.svelte';
	import StatusBadge from '$lib/components/ui/StatusBadge.svelte';
	import ProfileConflictNotice from './ProfileConflictNotice.svelte';
	import ProfileSectionFooter from './ProfileSectionFooter.svelte';
	import leafIcon from '@tabler/icons/outline/leaf.svg?raw';
	import pencilIcon from '@tabler/icons/outline/pencil.svg?raw';
	import hardHatIcon from '@tabler/icons/outline/helmet.svg?raw';
	import arrowUpRightIcon from '@tabler/icons/outline/arrow-up-right.svg?raw';
	import fileTextIcon from '@tabler/icons/outline/file-text.svg?raw';
	import receiptIcon from '@tabler/icons/outline/receipt.svg?raw';
	import mailIcon from '@tabler/icons/outline/mail.svg?raw';
	import userIcon from '@tabler/icons/outline/user.svg?raw';
	import inboxIcon from '@tabler/icons/outline/inbox.svg?raw';

	// The business card at the top of the Business profile page (Pencil: "Batch 64 · Business profile"): the
	// logo, the name customers see, the trade and city, the tagline, and where all of that shows up. Edit
	// name and trade opens the card in place with the logo column and the fields.
	let {
		name,
		trade,
		city,
		tagline,
		logoUrl,
		complete,
		open,
		canEdit,
		saving = false,
		saveDisabled = false,
		conflict = null,
		onEdit,
		onCancel,
		onSave,
		onSeeTheirs,
		form
	}: {
		name: string;
		trade: string | null;
		city: string | null;
		tagline: string | null;
		logoUrl: string | null;
		complete: boolean;
		open: boolean;
		canEdit: boolean;
		saving?: boolean;
		saveDisabled?: boolean;
		conflict?: { who: string; when: string; theirs: string[] | null; checking: boolean } | null;
		onEdit: () => void;
		onCancel: () => void;
		onSave: () => void;
		onSeeTheirs: () => void;
		/** The open card's fields. */
		form: Snippet;
	} = $props();

	const places = [
		{ label: 'Quotes', icon: fileTextIcon, tone: 'quote' },
		{ label: 'Invoices and receipts', icon: receiptIcon, tone: 'invoice' },
		{ label: 'Emails and texts', icon: mailIcon, tone: 'conversation' },
		{ label: 'Client portal', icon: userIcon, tone: 'client' },
		{ label: 'Booking forms', icon: inboxIcon, tone: 'request' }
	];
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<section
	class={['identity', open && 'identity--open', conflict && 'identity--conflict']}
	aria-labelledby="business-profile-name"
>
	{#if open}
		<div class="identity__edit">
			<div class="identity__logo-column">
				<span class="identity__logo" aria-hidden="true">
					{#if logoUrl}<img src={logoUrl} alt="" />{:else}{@html leafIcon}{/if}
				</span>
				<a class="identity__logo-link" href={resolve('/(app)/settings/branding')}
					>Logo in Branding <span aria-hidden="true">{@html arrowUpRightIcon}</span></a
				>
			</div>
			<div class="identity__fields">
				<h2 id="business-profile-name" class="identity__sr">Edit name and trade</h2>
				{#if conflict}<ProfileConflictNotice {...conflict} />{/if}
				{@render form()}
			</div>
		</div>
		<ProfileSectionFooter
			hint={conflict ? 'Your changes are kept' : 'Only this section is saved'}
			{saving}
			saveLabel="Save name and trade"
			{saveDisabled}
			{onCancel}
			{onSave}
			{onSeeTheirs}
			seeTheirsLoading={conflict?.checking ?? false}
			showSeeTheirs={Boolean(conflict && !conflict.theirs)}
		/>
	{:else}
		<div class="identity__top">
			<span class="identity__logo" aria-hidden="true">
				{#if logoUrl}<img src={logoUrl} alt="" />{:else}{@html leafIcon}{/if}
			</span>
			<div class="identity__copy">
				<div class="identity__name-row">
					<h2 id="business-profile-name" class="identity__name">{name}</h2>
					<StatusBadge status={complete ? 'success' : 'warning'}>
						{complete ? 'Profile complete' : 'Profile incomplete'}
					</StatusBadge>
				</div>
				{#if trade || city}
					<p class="identity__line">
						{#if trade}
							<span class="identity__trade-icon" aria-hidden="true">{@html hardHatIcon}</span>
							<span class="identity__trade">{trade}</span>
						{/if}
						{#if trade && city}<span class="identity__dot" aria-hidden="true"></span>{/if}
						{#if city}<span>{city}</span>{/if}
					</p>
				{/if}
				{#if tagline}<p class="identity__tagline">“{tagline}”</p>{/if}
			</div>
			{#if canEdit}
				<Button variant="secondary" size="small" onclick={onEdit}>
					<span aria-hidden="true">{@html pencilIcon}</span>Edit name and trade
				</Button>
			{/if}
		</div>
		<div class="identity__places">
			<span class="identity__places-label">Customers see this on</span>
			<ul class="identity__chips">
				{#each places as place (place.label)}
					<li class="identity__chip">
						<IconTile icon={place.icon} tone={place.tone} size={20} />{place.label}
					</li>
				{/each}
			</ul>
		</div>
	{/if}
</section>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.identity {
		display: flex;
		flex-direction: column;
		overflow: hidden;
		background: var(--color-surface);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-large);

		&--open {
			border: 1.5px solid var(--color-interactive);
			box-shadow: var(--shadow-high);
		}
		&--conflict {
			border-color: var(--color-critical);
		}
		&__sr {
			position: absolute;
			width: 1px;
			height: 1px;
			overflow: hidden;
			clip-path: inset(50%);
			white-space: nowrap;
		}
		&__top {
			display: flex;
			align-items: flex-start;
			gap: var(--space-large);
			padding: var(--space-large) var(--space-large) var(--space-medium);
		}
		&__logo {
			display: grid;
			flex: none;
			place-items: center;
			width: 72px;
			height: 72px;
			overflow: hidden;
			background: var(--color-interactive);
			color: var(--color-white);
			border-radius: var(--radius-large);

			:global(svg) {
				width: 34px;
				height: 34px;
			}
			img {
				width: 100%;
				height: 100%;
				object-fit: cover;
			}
		}
		&__copy {
			display: flex;
			flex: 1;
			flex-direction: column;
			gap: var(--space-small);
			min-width: 0;
		}
		&__name-row {
			display: flex;
			flex-wrap: wrap;
			align-items: center;
			gap: var(--space-slim);
		}
		&__name {
			margin: 0;
			color: var(--color-heading);
			font-size: var(--typography--fontSize-display);
			font-weight: 700;
			letter-spacing: -0.6px;
		}
		&__line {
			display: flex;
			align-items: center;
			gap: var(--space-small);
			margin: 0;
			color: var(--color-text);
			font-size: var(--typography--fontSize-base);
			font-weight: 500;
		}
		&__trade-icon {
			display: grid;
			color: var(--color-job);

			:global(svg) {
				width: 16px;
				height: 16px;
			}
		}
		&__trade {
			color: var(--color-heading);
			font-weight: 600;
		}
		&__dot {
			width: var(--space-smaller);
			height: var(--space-smaller);
			background: var(--color-inactive);
			border-radius: var(--radius-circle);
		}
		&__tagline {
			max-width: 640px;
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-base);
			line-height: 1.5;
		}
		&__places {
			display: flex;
			flex-wrap: wrap;
			align-items: center;
			gap: var(--space-slim);
			padding: var(--space-slim) var(--space-large);
			background: var(--color-surface--background--subtle);
			border-top: var(--border-base) solid var(--color-border);
		}
		&__places-label {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-smaller);
			font-weight: 600;
		}
		&__chips {
			display: flex;
			flex-wrap: wrap;
			gap: var(--space-small);
			margin: 0;
			padding: 0;
			list-style: none;
		}
		&__chip {
			display: inline-flex;
			align-items: center;
			gap: var(--space-small);
			padding: var(--space-smaller) var(--space-slim) var(--space-smaller) var(--space-smaller);
			background: var(--color-surface);
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-circle);
			color: var(--color-heading);
			font-size: var(--typography--fontSize-smaller);
			font-weight: 600;
		}
		&__edit {
			display: flex;
			gap: var(--space-large);
			padding: var(--space-medium) var(--space-large);
		}
		&__logo-column {
			display: flex;
			flex: none;
			flex-direction: column;
			align-items: center;
			gap: var(--space-small);
		}
		&__logo-link {
			display: inline-flex;
			align-items: center;
			gap: var(--space-smaller);
			color: var(--color-interactive);
			font-size: var(--typography--fontSize-smaller);
			font-weight: 600;
			text-decoration: none;

			:global(svg) {
				width: 12px;
				height: 12px;
			}
		}
		&__fields {
			display: flex;
			flex: 1;
			flex-direction: column;
			gap: var(--space-base);
			min-width: 0;
		}
	}
</style>
