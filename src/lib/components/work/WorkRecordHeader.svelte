<script lang="ts">
	import type { Snippet } from 'svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import DropdownMenu from '$lib/components/ui/DropdownMenu.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import PencilButton from '$lib/components/ui/PencilButton.svelte';
	import StatusBadge from '$lib/components/ui/StatusBadge.svelte';
	import type { StatusTone } from './types';
	import historyIcon from '@tabler/icons/outline/history.svg?raw';

	// The card at the top of every work record — request, quote, job, invoice. They all draw the same
	// thing: what kind of record this is and where it stands, the one action that moves it forward, the
	// title, and then who the work is for beside the few dates that identify it.
	//
	// Nothing here knows about requests. The page hands in its own icon, status wording, action label and
	// menu, and fills the two columns with `summary` and `facts`.
	//
	// The pencil swaps the heading for a field where the heading sits, the way Jobber does it — no separate
	// block appears underneath. The page owns the text being typed and saves it with everything else from
	// the bar at the bottom.
	type MenuItem = {
		label: string;
		icon?: string;
		onSelect: () => void;
		destructive?: boolean;
		disabled?: boolean;
	};

	type PrimaryAction = {
		label: string;
		onclick?: (event: MouseEvent) => void;
		href?: string;
		disabled?: boolean;
		loading?: boolean;
		/** Fires on hover, before the press. Start loading whatever the action opens. */
		onhover?: () => void;
	};

	let {
		icon,
		recordType,
		title,
		statusLabel,
		statusTone = 'informative',
		primaryAction,
		menuItems = [],
		onHistory,
		onHistoryHover,
		onEditTitle,
		editingTitle = false,
		titleDraft = $bindable(''),
		titleLabel,
		titleMaxLength = 160,
		summary,
		facts,
		badges,
		class: className = ''
	}: {
		/** Tabler icon for this kind of record, imported with `?raw`. */
		icon: string;
		/** What kind of record this is, e.g. "Request". Used to name the controls out loud. */
		recordType: string;
		title: string;
		statusLabel: string;
		statusTone?: StatusTone;
		/** The one action that moves this record to its next step. Omit where there isn't one yet. */
		primaryAction?: PrimaryAction;
		menuItems?: MenuItem[];
		/** Opens the record's history panel. Omit and the button is not drawn. */
		onHistory?: () => void;
		/** Fires when the history button is reached, so the panel's own data can start loading. */
		onHistoryHover?: () => void;
		/** Omit and the title carries no pencil, for a record nobody may rename. */
		onEditTitle?: () => void;
		/** True while the title is being renamed: the heading becomes a field in the same place. */
		editingTitle?: boolean;
		/** The name being typed. Bound, so the page can save it and throw it away. */
		titleDraft?: string;
		/** Defaults to "Request title", "Quote title", and so on. */
		titleLabel?: string;
		titleMaxLength?: number;
		/** The client summary card. Normally `ClientSummaryCard`. */
		summary?: Snippet;
		/** The label/value rows beside it. Normally `RecordFactsList`. */
		facts?: Snippet;
		/** Extra status context beside the main status badge, e.g. a quote's deposit readiness. Omit and
		 * nothing extra is drawn — the shared header stays ignorant of what any one record type means. */
		badges?: Snippet;
		class?: string;
	} = $props();

	const titleFieldId = $derived(`${recordType.toLowerCase().replace(/\s+/g, '-')}-title`);

	// The cursor belongs in the field the pencil just opened, so renaming is one click and then typing.
	let titleField = $state<HTMLDivElement>();
	$effect(() => {
		if (editingTitle) titleField?.querySelector('input')?.focus();
	});
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<section class={`work-header ${className}`} aria-label="{recordType} summary">
	<div class="work-header__top">
		<span class="work-header__type" aria-hidden="true">{@html icon}</span>
		<StatusBadge status={statusTone}>{statusLabel}</StatusBadge>
		{#if badges}{@render badges()}{/if}

		<div class="work-header__actions">
			{#if onHistory}
				<button
					type="button"
					class="work-header__icon-button"
					aria-label="{recordType} history"
					title="{recordType} history"
					onclick={onHistory}
					onmouseenter={onHistoryHover}
					onfocus={onHistoryHover}
				>
					<span aria-hidden="true">{@html historyIcon}</span>
				</button>
			{/if}
			{#if primaryAction}
				<Button
					variant="primary"
					size="small"
					href={primaryAction.href}
					onclick={primaryAction.onclick}
					disabled={primaryAction.disabled}
					loading={primaryAction.loading}
					onhover={primaryAction.onhover}
				>
					{primaryAction.label}
				</Button>
			{/if}
			{#if menuItems.length > 0}
				<DropdownMenu items={menuItems} triggerLabel="More {recordType.toLowerCase()} actions" />
			{/if}
		</div>
	</div>

	<div class="work-header__identity">
		{#if editingTitle}
			<div class="work-header__title-field" bind:this={titleField}>
				<Input
					id={titleFieldId}
					label={titleLabel ?? `${recordType} title`}
					bind:value={titleDraft}
					maxlength={titleMaxLength}
				/>
			</div>
		{:else}
			<h1>{title}</h1>
			{#if onEditTitle}
				<PencilButton size="base" onclick={onEditTitle} label="Edit {title}" />
			{/if}
		{/if}
	</div>

	{#if summary || facts}
		<div class="work-header__body">
			<div class="work-header__summary">
				{#if summary}{@render summary()}{/if}
			</div>
			<div class="work-header__facts">
				{#if facts}{@render facts()}{/if}
			</div>
		</div>
	{/if}
</section>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.work-header {
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

		&__type {
			display: inline-flex;
			flex: 0 0 auto;
			align-items: center;
			justify-content: center;
			width: var(--space-larger);
			height: var(--space-larger);
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-base);
			color: var(--color-icon);
			background: var(--color-surface);

			:global(svg) {
				display: block;
				width: 20px;
				height: 20px;
			}
		}

		&__actions {
			display: flex;
			align-items: center;
			gap: var(--space-small);
			margin-left: auto;
		}

		// The history control is a lone icon on this card, so it keeps a border to read as a button.
		&__icon-button {
			display: inline-flex;
			box-sizing: border-box;
			flex: 0 0 auto;
			align-items: center;
			justify-content: center;
			width: var(--space-larger);
			height: var(--space-larger);
			padding: 0;
			border: var(--border-base) solid var(--color-border--interactive);
			border-radius: var(--radius-base);
			color: var(--color-interactive--subtle);
			background: var(--color-surface);
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
				color: var(--color-interactive--subtle--hover);
				background: var(--color-surface--hover);
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
				overflow: hidden;
				color: var(--color-heading);
				font-size: var(--typography--fontSize-largest);
				font-weight: 700;
				line-height: var(--typography--lineHeight-tight);
				text-overflow: ellipsis;
			}
		}

		// The field takes the whole width the heading and its pencil had between them.
		&__title-field {
			flex: 1 1 auto;
			min-width: 0;
		}

		&__body {
			display: grid;
			align-items: start;
			gap: var(--space-large);
			grid-template-columns: minmax(0, 1fr) minmax(0, 1fr);
		}

		&__summary,
		&__facts {
			min-width: 0;
		}
	}

	@media (max-width: 767px) {
		.work-header {
			padding: var(--space-base);

			&__top {
				flex-wrap: wrap;
			}

			&__actions {
				width: 100%;
				margin-left: 0;
			}

			&__body {
				gap: var(--space-base);
				grid-template-columns: 1fr;
			}
		}
	}
</style>
