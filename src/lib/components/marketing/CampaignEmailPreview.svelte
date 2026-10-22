<script lang="ts">
	import { tick } from 'svelte';
	import { createQuery, keepPreviousData } from '@tanstack/svelte-query';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import SegmentedControl from '$lib/components/ui/SegmentedControl.svelte';
	import EmailPreviewBone from './EmailPreviewBone.svelte';
	import { BLOCK_TYPE_ICONS } from './block-types';
	import { previewCampaignContent } from '$lib/marketing/api';
	import {
		marketingCampaignPreviewKey,
		MARKETING_BLOCK_TYPE_LABELS,
		type MarketingBlockType,
		type MarketingCampaignContent
	} from '$lib/marketing/campaign-content';
	import desktopIcon from '@tabler/icons/outline/device-desktop.svg?raw';
	import mobileIcon from '@tabler/icons/outline/device-mobile.svg?raw';
	import blocksIcon from '@tabler/icons/outline/list-details.svg?raw';

	// The Email step's live preview (design skill `layout.md` → New campaign · Email step): the toolbar, the
	// inbox line a customer sees, then the email exactly as the server renders it. It follows the text a moment
	// after typing stops and keeps the last render on screen while the next one comes in. The block being edited
	// is outlined and tagged on top of the email.
	let {
		content,
		title,
		editingBlock = null
	}: {
		content: MarketingCampaignContent;
		/** Names the email frame to a screen reader. */
		title: string;
		/** The open block, outlined in the email. */
		editingBlock?: { id: string; type: MarketingBlockType } | null;
	} = $props();

	let viewport = $state<'desktop' | 'mobile'>('desktop');
	// Only the chosen width's icon takes the Marketing colour (design `modals.md` → Email preview pop-up).
	const viewportOptions = $derived(
		[
			{ value: 'desktop', label: 'Desktop', icon: desktopIcon },
			{ value: 'mobile', label: 'Mobile', icon: mobileIcon }
		].map((option) => ({
			...option,
			iconColor: option.value === viewport ? 'var(--color-growth)' : 'var(--color-icon--secondary)'
		}))
	);

	// What the preview last asked for: the content settles 400ms after the last keystroke, so a sentence typed
	// at speed is one render, not one per letter.
	// svelte-ignore state_referenced_locally
	let settled = $state($state.snapshot(content));
	$effect(() => {
		const next = $state.snapshot(content);
		const timer = setTimeout(() => (settled = next), 400);
		return () => clearTimeout(timer);
	});

	const query = createQuery(() => ({
		queryKey: [...marketingCampaignPreviewKey(settled), 'editor'],
		queryFn: ({ signal }) => previewCampaignContent(settled, { markBlocks: true, signal }),
		placeholderData: keepPreviousData,
		refetchOnWindowFocus: false,
		gcTime: 30_000
	}));

	const rendered = $derived(query.data);
	const updating = $derived(query.isFetching && Boolean(rendered));
	const hasBlocks = $derived(content.blocks.length > 0);
	const senderInitial = $derived((rendered?.sender_name ?? '').trim().charAt(0).toUpperCase());
	const sentAt = new Date().toLocaleTimeString('en', { hour: 'numeric', minute: '2-digit' });

	// --- The email frame ----------------------------------------------------------------------------------
	// The frame has no scripts, so reading it from here is safe; it lets the frame be exactly as tall as the
	// email (the page scrolls, not the frame) and tells us where the open block sits to outline it.
	let frame = $state<HTMLIFrameElement>();
	let frameHeight = $state(420);
	let mark = $state<{ top: number; left: number; width: number; height: number } | null>(null);

	function measure() {
		const doc = frame?.contentDocument;
		if (!doc?.body) return;
		// The frame grows to the email's height, so it never needs a scrollbar; one showing for a moment while
		// it grows would narrow the email and shift the outline.
		doc.documentElement.style.overflow = 'hidden';
		frameHeight = Math.ceil(doc.body.getBoundingClientRect().height);
		const block = editingBlock ? doc.querySelector(`.ucrm-block-${editingBlock.id}`) : null;
		if (!block) {
			mark = null;
			return;
		}
		const box = block.getBoundingClientRect();
		// The block's own padding is the 8 around its words; pull the sides in so the outline sits close.
		const inset = Math.min(16, box.width / 4);
		// Placed against the paper, which can hold a note above the frame while there are no blocks.
		mark = {
			top: frame ? frame.offsetTop + box.top : box.top,
			left: frame ? frame.offsetLeft + box.left + inset : box.left + inset,
			width: box.width - inset * 2,
			height: box.height
		};
	}

	// Measure again whenever what the box depends on changes: the open block or the width.
	$effect(() => {
		void editingBlock?.id;
		void viewport;
		void rendered?.html;
		tick().then(() => requestAnimationFrame(measure));
	});

	const markTypeLabel = $derived(
		editingBlock ? MARKETING_BLOCK_TYPE_LABELS[editingBlock.type] : ''
	);
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<div class="email-preview">
	<div class="email-preview__bar">
		<SegmentedControl bind:value={viewport} ariaLabel="Preview width" options={viewportOptions} />
		{#if !query.isError}
			<span
				class={[
					'email-preview__status',
					!rendered && 'email-preview__status--loading',
					updating && 'email-preview__status--loading'
				]}
				role="status"
			>
				{#if !rendered}
					<span class="email-preview__spinner" aria-hidden="true"></span>Loading the preview…
				{:else if updating}
					<span class="email-preview__spinner" aria-hidden="true"></span>Updating…
				{:else}
					<span class="email-preview__dot" aria-hidden="true"></span>Updates as you type
				{/if}
			</span>
		{/if}
	</div>

	{#if query.isError}
		<div class="email-preview__problem">
			<ErrorState
				title="This could not be rendered"
				description="Something went wrong on our side. Try again."
				retry={() => query.refetch()}
			/>
		</div>
	{:else}
		<!-- The inbox line waits for the first render: before it, the email bone alone shows it is coming. -->
		{#if rendered}
			<div class="email-preview__inbox">
				<span class="email-preview__avatar" aria-hidden="true">{senderInitial}</span>
				<div class="email-preview__inbox-copy">
					<div class="email-preview__inbox-top">
						<b>{rendered.sender_name}</b>
						<span class="email-preview__time">{sentAt}</span>
					</div>
					<span class={['email-preview__subject', !rendered.subject && 'email-preview__quiet']}
						>{rendered.subject || 'Your subject line'}</span
					>
					<span class="email-preview__preview-text email-preview__quiet-text"
						>{rendered.preview_text || 'Your preview text'}</span
					>
				</div>
			</div>
		{/if}

		<div
			class={[
				'email-preview__paper',
				rendered && 'email-preview__paper--email',
				viewport === 'mobile' && 'email-preview__paper--mobile'
			]}
		>
			{#if !rendered}
				<EmailPreviewBone />
			{:else}
				{#if !hasBlocks}
					<div class="email-preview__empty">
						<span class="email-preview__empty-icon" aria-hidden="true">{@html blocksIcon}</span>
						<b>Your blocks show here</b>
						<span>The business name and the unsubscribe line are added for you.</span>
					</div>
				{/if}
				<iframe
					bind:this={frame}
					title={`${title} preview`}
					srcdoc={rendered.html}
					sandbox="allow-same-origin"
					style:height={`${frameHeight}px`}
					onload={measure}
				></iframe>
				{#if mark && editingBlock}
					<span
						class="email-preview__mark"
						style:top={`${mark.top}px`}
						style:left={`${mark.left}px`}
						style:width={`${mark.width}px`}
						style:height={`${mark.height}px`}
						aria-hidden="true"
					>
						<span class="email-preview__mark-tag">
							{@html BLOCK_TYPE_ICONS[editingBlock.type]}{markTypeLabel} · editing
						</span>
					</span>
				{/if}
			{/if}
		</div>
	{/if}
</div>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	// The pane is the soft page colour with the email centred on it.
	.email-preview {
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: var(--space-base);
		min-width: 0;
		padding: var(--space-medium) var(--space-large) var(--space-large);
		background: var(--color-surface--background--subtle);

		&__bar {
			display: flex;
			align-items: center;
			justify-content: space-between;
			gap: var(--space-small);
			width: 100%;
			max-width: 600px;
		}

		// Whether the preview is current: a green dot, or a spinner while it catches up.
		&__status {
			display: inline-flex;
			align-items: center;
			gap: 6px;
			height: 28px;
			padding: 0 12px;
			border: var(--border-base) solid var(--color-border);
			border-radius: 14px;
			color: var(--color-heading);
			background: var(--color-surface);
			font-size: var(--typography--fontSize-smaller);
			font-weight: 600;
			white-space: nowrap;
		}
		&__dot {
			width: 8px;
			height: 8px;
			border-radius: var(--radius-circle);
			background: var(--color-success);
		}
		&__spinner {
			width: 16px;
			height: 16px;
			border: 2px solid var(--color-border);
			border-top-color: var(--color-interactive);
			border-radius: var(--radius-circle);
			animation: email-preview-spin 0.8s linear infinite;
		}

		&__problem {
			box-sizing: border-box;
			display: grid;
			place-items: center;
			width: 100%;
			max-width: 600px;
			min-height: 320px;
			border: var(--border-base) solid var(--color-border);
			border-radius: 10px;
			background: var(--color-surface);
		}

		// The line a customer sees in their inbox before they open the email.
		&__inbox {
			box-sizing: border-box;
			display: flex;
			gap: var(--space-slim);
			width: 100%;
			max-width: 600px;
			padding: 12px 14px;
			border: var(--border-base) solid var(--color-border);
			border-radius: 10px;
			background: var(--color-surface);
		}
		&__avatar {
			display: grid;
			flex: none;
			place-items: center;
			width: 36px;
			height: 36px;
			border-radius: var(--radius-circle);
			color: var(--color-text--reverse);
			background: var(--color-interactive);
			font-size: var(--typography--fontSize-base);
			font-weight: 700;
		}
		&__inbox-copy {
			display: flex;
			flex: 1;
			min-width: 0;
			flex-direction: column;
			gap: 2px;
			font-size: var(--typography--fontSize-base);
		}
		&__inbox-top {
			display: flex;
			align-items: baseline;
			justify-content: space-between;
			gap: var(--space-small);

			b {
				overflow: hidden;
				color: var(--color-heading);
				font-weight: 700;
				text-overflow: ellipsis;
				white-space: nowrap;
			}
		}
		&__time {
			flex: none;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}
		&__subject {
			overflow: hidden;
			color: var(--color-heading);
			font-weight: 600;
			text-overflow: ellipsis;
			white-space: nowrap;
		}
		&__preview-text {
			overflow: hidden;
			text-overflow: ellipsis;
			white-space: nowrap;
		}
		&__quiet,
		&__quiet-text {
			color: var(--color-text--secondary);
		}
		&__quiet {
			font-weight: 500;
		}

		// The email on its white paper, 600 wide on Desktop and 375 on Mobile.
		&__paper {
			position: relative;
			box-sizing: border-box;
			width: 100%;
			max-width: 600px;
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-small);
			background: var(--color-surface);

			&--mobile {
				max-width: 375px;
			}

			// Once the email is in, the paper is the email's own white, in dark mode too.
			&--email {
				background: var(--color-white);
			}

			// The email keeps its own light colours in dark mode.
			iframe {
				display: block;
				width: 100%;
				border: 0;
				background: var(--color-white);
			}
		}

		// No blocks yet: a quiet box where they will go. It sits on the email's own white paper, so like the email
		// it keeps its light colours in dark mode (fixed base shades, not the theme's surface tokens).
		&__empty {
			display: flex;
			flex-direction: column;
			align-items: center;
			justify-content: center;
			gap: 4px;
			min-height: 260px;
			margin: var(--space-large) var(--space-large) 0;
			padding: var(--space-large) var(--space-base);
			border: var(--border-base) solid var(--color-base-grey--300);
			border-radius: var(--radius-base);
			background: var(--color-base-grey--100);
			text-align: center;

			b {
				color: var(--color-base-grey--1000);
				font-size: var(--typography--fontSize-base);
				font-weight: 600;
			}
			span:not(.email-preview__empty-icon) {
				color: var(--color-base-grey--700);
				font-size: var(--typography--fontSize-base);
			}
		}
		&__empty-icon {
			display: flex;
			margin-bottom: 4px;
			color: var(--color-base-purple--700);

			:global(svg) {
				width: 24px;
				height: 24px;
			}
		}

		// The open block's outline, over the email, with its tag at the top right.
		&__mark {
			position: absolute;
			box-sizing: border-box;
			border: 2px solid var(--color-growth);
			border-radius: 6px;
			pointer-events: none;
		}
		&__mark-tag {
			position: absolute;
			right: -2px;
			bottom: 100%;
			display: inline-flex;
			align-items: center;
			gap: 4px;
			height: 22px;
			margin-bottom: 0;
			padding: 0 8px;
			border-radius: 6px 6px 0 0;
			color: var(--color-text--reverse);
			background: var(--color-growth);
			font-size: var(--typography--fontSize-smaller);
			font-weight: 600;
			white-space: nowrap;

			:global(svg) {
				width: 12px;
				height: 12px;
			}
		}
	}

	@keyframes email-preview-spin {
		to {
			transform: rotate(360deg);
		}
	}
</style>
