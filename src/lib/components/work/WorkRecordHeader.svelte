<script lang="ts">
	import type { Snippet } from 'svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import DropdownMenu from '$lib/components/ui/DropdownMenu.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import PencilButton from '$lib/components/ui/PencilButton.svelte';
	import StatusBadge from '$lib/components/ui/StatusBadge.svelte';
	import type { StatusTone, RecordLifecycleStep } from './types';
	import RecordLifecycleTrack from './RecordLifecycleTrack.svelte';
	import dotsIcon from '@tabler/icons/outline/dots-vertical.svg?raw';
	import chevronIcon from '@tabler/icons/outline/chevron-down.svg?raw';
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
		/** A Tabler icon (`?raw`) drawn before the label. */
		icon?: string;
		/** Fires on hover, before the press. Start loading whatever the action opens. */
		onhover?: () => void;
	};

	let {
		icon,
		recordType,
		recordNumber,
		meta,
		lifecycle = [],
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
		recordNumber?: string | number;
		/** A short line after the record number in Classic, e.g. "Multi-day · 4 visits". */
		meta?: string;
		lifecycle?: RecordLifecycleStep[];
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
<section
	class={`work-header work-header--${recordType.toLowerCase()} ${className}`}
	aria-label="{recordType} summary"
>
	<div class="work-header__top">
		<span class="work-header__type" aria-hidden="true">{@html icon}</span>
		<StatusBadge status={statusTone}>{statusLabel}</StatusBadge>
		{#if recordNumber != null}
			<span class="work-header__number">{recordType} #{recordNumber}</span>
		{/if}
		{#if meta}
			<span class="work-header__meta"
				><span class="work-header__meta-dot" aria-hidden="true"></span>{meta}</span
			>
		{/if}
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
					{#if primaryAction.icon}<span class="work-header__primary-icon" aria-hidden="true"
							>{@html primaryAction.icon}</span
						>{/if}{primaryAction.label}
				</Button>
			{/if}
			{#if menuItems.length > 0}
				<DropdownMenu
					items={menuItems}
					triggerLabel="More {recordType.toLowerCase()} actions"
					triggerClass="dropdown-menu__trigger work-header__menu"
				>
					{#snippet trigger()}
						<span class="work-header__more"
							>More<span aria-hidden="true">{@html chevronIcon}</span></span
						>
						<span class="work-header__legacy-menu" aria-hidden="true">{@html dotsIcon}</span>
					{/snippet}
				</DropdownMenu>
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

	<div class="work-header__body">
		{#if summary}
			<div class="work-header__summary">{@render summary()}</div>
		{/if}
		{#if lifecycle.length}
			<RecordLifecycleTrack steps={lifecycle} tone={statusTone} />
		{/if}
		{#if facts}
			<div class="work-header__facts">{@render facts()}</div>
		{/if}
	</div>
</section>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.work-header {
		&__more {
			display: none;
		}
		&__legacy-menu {
			display: inline-flex;
		}
		&__number,
		&__meta {
			display: none;
		}
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

	:global(:root:has(.app-shell[data-presentation='classic'])) .work-header {
		gap: 0;
		padding: 24px 28px 0;
		border: 1px solid var(--classic2-border);
		border-radius: var(--classic2-radius-card);
		background: var(--classic2-surface);
		box-shadow:
			0 1px 2px var(--classic2-shadow-near),
			0 10px 28px var(--classic2-shadow-far);
		font-family: var(--classic2-font);

		&__top {
			flex-wrap: wrap;
			gap: 10px;
		}
		&__type {
			display: none;
		}
		&__number {
			display: inline;
			color: var(--classic2-secondary);
			font-size: var(--classic2-font-small);
			font-weight: 600;
			letter-spacing: 0.6px;
			text-transform: uppercase;
		}
		&__meta {
			display: inline-flex;
			align-items: center;
			gap: 10px;
			color: var(--classic2-secondary);
			font-size: var(--classic2-font-small);
			font-weight: 500;
		}
		&__meta-dot {
			width: 3px;
			height: 3px;
			border-radius: 50%;
			background: var(--classic2-icon-muted);
		}
		&__primary-icon {
			display: inline-flex;
		}
		&__primary-icon :global(svg) {
			width: 18px;
			height: 18px;
		}
		&__actions :global(.button--primary) {
			gap: 8px;
		}
		&__more {
			display: inline-flex;
			align-items: center;
			gap: 6px;
		}
		&__more span {
			display: inline-flex;
		}
		&__more :global(svg) {
			width: 16px;
			height: 16px;
		}
		&__legacy-menu {
			display: none;
		}
		&__actions :global(.work-header__menu) {
			order: 2;
			width: auto;
			height: 40px;
			padding: 0 14px;
			border: 1px solid var(--classic2-border-control);
			background: var(--classic2-surface);
			color: var(--classic2-ink);
			font-weight: 600;
		}
		&__actions :global(.button--primary) {
			order: 3;
			min-height: 40px;
			padding: 0 16px;
		}
		&__actions {
			flex-wrap: wrap;
		}
		&__identity {
			justify-content: flex-start;
			padding-top: 18px;
		}
		// The approved header shows a clean title: the rename pencil waits beside it until the title is
		// pointed at or reached by keyboard.
		&__identity :global(.pencil-button) {
			flex: 0 0 auto;
			opacity: 0;
			transition: opacity var(--timing-base) ease-out;
		}
		&__identity:hover :global(.pencil-button),
		&__identity:focus-within :global(.pencil-button) {
			opacity: 1;
		}
		&__actions :global(.work-header__menu),
		&__icon-button {
			box-shadow: 0 1px 2px var(--classic2-shadow-near);
		}
		&__identity h1 {
			overflow: visible;
			overflow-wrap: anywhere;
			font-size: 32px;
			line-height: 1.15;
			letter-spacing: -0.8px;
			color: var(--classic2-ink);
		}
		&__body {
			display: flex;
			flex-direction: column;
			gap: 0;
			width: 100%;
		}
		&__summary {
			width: 100%;
			padding-top: 14px;
		}
		// The facts flow to fit the card, so they must never be what makes the card wider.
		&__facts {
			overflow: hidden;
			contain: inline-size;
			width: 100%;
			margin-top: 20px;
			padding: 18px 0 22px;
			border-top: 1px solid var(--classic2-divider);
		}
		&__icon-button {
			width: 40px;
			height: 40px;
			border: 1px solid var(--classic2-border-control);
			border-radius: var(--classic2-radius-control);
			color: var(--classic2-secondary);
			background: var(--classic2-surface);
		}
		&__icon-button:hover {
			background: var(--classic2-surface-soft);
			color: var(--classic2-ink);
		}
		&__icon-button:focus-visible {
			outline: 2px solid var(--classic2-green);
			outline-offset: 3px;
		}
	}
	@media (max-width: 767px) {
		:global(:root:has(.app-shell[data-presentation='classic'])) .work-header {
			padding: 20px 16px 0;
			&__identity h1 {
				font-size: 26px;
			}
			&__actions {
				gap: 6px;
			}
		}
	}
</style>
