<script lang="ts">
	import type { Snippet } from 'svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import DropdownMenu from '$lib/components/ui/DropdownMenu.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import PencilButton from '$lib/components/ui/PencilButton.svelte';
	import StatusBadge from '$lib/components/ui/StatusBadge.svelte';
	import type { StatusTone } from './types';
	import historyIcon from '@tabler/icons/outline/history.svg?raw';
	import pencilIcon from '@tabler/icons/outline/pencil.svg?raw';

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
		/** A Tabler icon (raw SVG) drawn before the label. */
		icon?: string;
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
		look = 'default',
		meta = [],
		track,
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
		/** `app` draws the App look header from the approved design: the record's identifiers beside the
		 *  status, a bordered "More" button, an icon on the main action, and room for a lifecycle track.
		 *  `concept` is the new concept's header (Job details): the client in its own box beside the facts
		 *  column, and the lifecycle track as a strip along the bottom edge. */
		look?: 'default' | 'app' | 'concept';
		/** Short identifiers shown after the status in the App look, e.g. ["QUOTE #326", "Version 2"]. */
		meta?: string[];
		/** The record's place in the Request → Quote → Job → Invoice → Paid line. Normally `LifecycleTrack`. */
		track?: Snippet;
		class?: string;
	} = $props();

	const roomy = $derived(look !== 'default');

	const titleFieldId = $derived(`${recordType.toLowerCase().replace(/\s+/g, '-')}-title`);

	// The cursor belongs in the field the pencil just opened, so renaming is one click and then typing.
	let titleField = $state<HTMLDivElement>();
	$effect(() => {
		if (editingTitle) titleField?.querySelector('input')?.focus();
	});
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<section
	class={`work-header ${className}`}
	class:work-header--app={roomy}
	class:work-header--concept={look === 'concept'}
	aria-label="{recordType} summary"
>
	<div class="work-header__top">
		<span class="work-header__type" aria-hidden="true">{@html icon}</span>
		<StatusBadge status={statusTone}>{statusLabel}</StatusBadge>
		{#if badges}{@render badges()}{/if}
		{#if meta.length > 0}
			<p class="work-header__meta">
				{#each meta as part, index (index)}
					{#if index > 0}<span class="work-header__meta-dot" aria-hidden="true"></span>{/if}
					<span class={{ 'work-header__meta-first': index === 0 }}>{part}</span>
				{/each}
			</p>
		{/if}

		<div class="work-header__actions">
			{#if onHistory}
				<Button
					variant="secondary"
					size={roomy ? 'base' : 'small'}
					iconOnly
					label="{recordType} history"
					onclick={onHistory}
					onhover={onHistoryHover}
				>
					{@html historyIcon}
				</Button>
			{/if}
			{#if primaryAction}
				<Button
					class="work-header__primary"
					variant="primary"
					size={roomy ? 'base' : 'small'}
					href={primaryAction.href}
					onclick={primaryAction.onclick}
					disabled={primaryAction.disabled}
					loading={primaryAction.loading}
					onhover={primaryAction.onhover}
				>
					{#if primaryAction.icon}
						<span class="work-header__action-icon" aria-hidden="true"
							>{@html primaryAction.icon}</span
						>
					{/if}
					{primaryAction.label}
				</Button>
			{/if}
			{#if menuItems.length > 0}
				{#if roomy}
					<DropdownMenu
						items={menuItems}
						triggerText="More"
						triggerLabel="More {recordType.toLowerCase()} actions"
					/>
				{:else}
					<DropdownMenu items={menuItems} triggerLabel="More {recordType.toLowerCase()} actions" />
				{/if}
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
			{#if onEditTitle && look === 'concept'}
				<Button variant="quiet" iconOnly size="small" onclick={onEditTitle} label="Edit {title}">
					{@html pencilIcon}
				</Button>
			{:else if onEditTitle}
				<PencilButton size="base" onclick={onEditTitle} label="Edit {title}" />
			{/if}
		{/if}
	</div>

	{#if summary || facts}
		<div class="work-header__body">
			<div class="work-header__summary">
				{#if summary}{@render summary()}{/if}
			</div>
			{#if track && look !== 'concept'}<div class="work-header__track">{@render track()}</div>{/if}
			<div class="work-header__facts">
				{#if facts}{@render facts()}{/if}
			</div>
		</div>
	{/if}
	{#if track && look === 'concept'}
		<div class="work-header__strip">{@render track()}</div>
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

		&__action-icon {
			display: inline-flex;

			:global(svg) {
				width: 18px;
				height: 18px;
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

	// App look (inside `RecordDetailLayout cards`): a white card on the grey page. The status and the
	// record's actions share the first row, the title follows, then the client row, and the facts close the
	// card as a strip under a hairline. No icon tile and no tinted ground.
	:global(.record-detail--cards) .work-header {
		gap: 0;
		padding: 24px 28px 0;
		border-color: var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface);

		.work-header__type {
			display: none;
		}
		.work-header__top {
			flex-wrap: wrap;
			gap: 8px 10px;
		}
		.work-header__actions :global(.button) {
			white-space: nowrap;
		}
		.work-header__identity {
			padding-top: 18px;

			h1 {
				font-size: var(--typography--fontSize-largest);
				letter-spacing: -0.8px;
				line-height: 1.15;
			}
		}
		.work-header__body {
			display: flex;
			flex-direction: column;
			align-items: stretch;
			gap: 0;
		}
		.work-header__summary {
			padding-top: 14px;
		}
		.work-header__facts {
			margin-top: 20px;
			padding: 18px 0 22px;
			border-top: var(--border-base) solid var(--color-border);
		}
		.work-header__action-icon :global(svg) {
			display: block;
			width: 18px;
			height: 18px;
		}
	}

	// The App look's own parts. Only a header given `look="app"` carries them.
	.work-header__meta {
		display: inline-flex;
		min-width: 0;
		flex: 1 1 auto;
		flex-wrap: wrap;
		align-items: center;
		gap: 0 8px;
		margin: 0;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		font-weight: 500;
	}
	.work-header__meta-first {
		font-weight: 600;
		letter-spacing: 0.6px;
		text-transform: uppercase;
	}
	.work-header__meta-dot {
		width: 3px;
		height: 3px;
		border-radius: 999px;
		background: var(--color-icon--secondary);
	}
	.work-header__action-icon :global(svg) {
		display: block;
		width: 18px;
		height: 18px;
	}
	// A narrow column (a laptop, or a rail beside a long page) wraps the top row rather than squeezing it:
	// the identifiers drop under the status and the actions keep their full size.
	:global(.record-detail--cards) .work-header--app .work-header__top {
		flex-wrap: wrap;
		row-gap: 12px;
	}
	:global(.record-detail--cards) .work-header--app .work-header__actions {
		flex: 0 1 auto;
		flex-wrap: wrap;
		max-width: 100%;
		white-space: nowrap;
	}
	:global(.record-detail--cards) .work-header--app .work-header__top > :global(.status-badge) {
		flex: 0 0 auto;
	}
	:global(.record-detail--cards) .work-header__track {
		padding: 22px 0 20px;
	}
	:global(.record-detail--cards) .work-header__track + .work-header__facts {
		margin-top: 0;
	}
	:global(.record-detail--cards) .work-header--app .work-header__facts {
		margin-top: 0;
	}


	// Concept look (Job details, `tNdkX`). A white card with the status row and title on top, the client box
	// beside the facts column, and the lifecycle strip closing the card on a tinted ground.
	:global(.record-detail--cards) .work-header.work-header--concept {
		overflow: hidden;
		padding: 0;
		border-radius: var(--radius-large);

		.work-header__top {
			flex-wrap: nowrap;
			gap: var(--space-slim);
			padding: var(--space-large) var(--space-large) 0;
		}
		.work-header__type {
			display: inline-flex;
			width: 40px;
			height: 40px;
			border: 0;
			border-radius: var(--radius-tile-large);
			color: var(--color-job);
			background: var(--color-job--surface);
		}
		.work-header__meta {
			flex: 0 1 auto;
			font-size: var(--typography--fontSize-small);
			font-weight: 400;
		}
		.work-header__meta-first {
			font-weight: 400;
			letter-spacing: 0;
			text-transform: none;
		}
		// The main action closes the row, after History and More.
		.work-header__actions :global(.work-header__primary) {
			order: 1;
		}
		// The title's pencil is a quiet icon right after the heading, not a boxed button at the far end.
		.work-header__identity {
			justify-content: flex-start;
			padding: var(--space-base) var(--space-large) 0;

			:global(.button--quiet) {
				color: var(--color-icon--secondary);
			}
		}
		.work-header__body {
			display: grid;
			align-items: start;
			gap: var(--space-large);
			padding: var(--space-medium) var(--space-large) var(--space-large);
			grid-template-columns: minmax(0, 1fr) 300px;
		}
		.work-header__summary {
			padding-top: 0;
		}
		.work-header__facts {
			margin: 0;
			padding: var(--space-smaller) 0;
			border-top: 0;
		}
		.work-header__strip {
			padding: var(--space-slim) var(--space-large);
			border-top: var(--border-base) solid var(--color-border);
			background: var(--color-surface--background--subtle);
		}
	}
	:global(.job-detail) .work-header__type :global(svg) {
		width: 20px;
		height: 20px;
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
