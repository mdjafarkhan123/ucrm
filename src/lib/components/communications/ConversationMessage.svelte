<script lang="ts" module>
	/** Where a bubble sits in a run of messages from the same side, so the run reads as one block. */
	export type MessageRun = 'single' | 'first' | 'middle' | 'last';
</script>

<script lang="ts">
	import type { Snippet } from 'svelte';
	import ChannelMark, { CHANNEL_LABELS } from './inbox/ChannelMark.svelte';
	import checkIcon from '@tabler/icons/outline/check.svg?raw';
	import checksIcon from '@tabler/icons/outline/checks.svg?raw';
	import clockIcon from '@tabler/icons/outline/clock.svg?raw';
	import calendarClockIcon from '@tabler/icons/outline/calendar-time.svg?raw';
	import alertIcon from '@tabler/icons/outline/alert-circle.svg?raw';

	// One message in a conversation, drawn the way a phone messaging app draws it (design skill inbox.md, Chat
	// card): the customer's in light grey on the left, the team's in brand green on the right, joined into runs,
	// with the channel, time and -- on ours -- the delivery ticks inside the bubble. An email is a white card
	// with its subject. Everything inside -- subject, text, attachments, notices -- is the page's own, passed in,
	// so each channel keeps its own content and this only owns the shape.
	let {
		id,
		outbound = false,
		channel,
		card = false,
		run = 'single',
		who = null,
		when,
		pending = false,
		failed = false,
		failureReason = null,
		retryLabel = 'Retry',
		onRetry,
		scheduledFor = null,
		status = null,
		statusTone = 'inactive',
		mark = null,
		badges,
		actions,
		footer,
		children
	}: {
		id: string;
		outbound?: boolean;
		channel: 'email' | 'sms' | 'messenger' | 'website_chat';
		/** An email: a white card bubble with its subject line, instead of a chat bubble. */
		card?: boolean;
		run?: MessageRun;
		/** Who sent it, for our own messages ("Jafar Khan", "Sent automatically"); shown on hover. */
		who?: string | null;
		when: string;
		pending?: boolean;
		/** The message did not reach the customer: the whole bubble turns red with the reason under it. */
		failed?: boolean;
		failureReason?: string | null;
		retryLabel?: string;
		onRetry?: () => void;
		/** A "Send later" message still waiting: its send time replaces the ticks. */
		scheduledFor?: string | null;
		status?: string | null;
		statusTone?: 'success' | 'warning' | 'critical' | 'inactive' | 'informative';
		/** Channels that report it (Messenger): the exact tick -- sent, delivered, or seen. */
		mark?: 'sent' | 'delivered' | 'seen' | null;
		badges?: Snippet;
		actions?: Snippet;
		/** A line under the bubble, e.g. "Scheduled by email · Cancel". */
		footer?: Snippet;
		children: Snippet;
	} = $props();

	const timeFormat = new Intl.DateTimeFormat(undefined, { hour: 'numeric', minute: '2-digit' });
	const dateTimeFormat = new Intl.DateTimeFormat(undefined, {
		month: 'short',
		day: 'numeric',
		hour: 'numeric',
		minute: '2-digit'
	});
	const time = $derived(timeFormat.format(new Date(when)));
	const scheduledTime = $derived(scheduledFor ? timeFormat.format(new Date(scheduledFor)) : '');

	// The ticks a messaging app uses: a clock while it is on its way, one tick once sent, two once delivered.
	// Seen is its own mark: two ticks in a filled circle.
	const tick = $derived(
		mark === 'sent'
			? checkIcon
			: mark === 'delivered' || mark === 'seen'
				? checksIcon
				: pending || statusTone === 'informative'
					? clockIcon
					: statusTone === 'success'
						? checksIcon
						: statusTone === 'inactive'
							? checkIcon
							: null
	);
	const hoverText = $derived(
		[outbound && who ? who : null, status, dateTimeFormat.format(new Date(when))]
			.filter(Boolean)
			.join(' · ')
	);
	// A late or delayed delivery is not a failure, but it is worth a word under the bubble.
	const warning = $derived(outbound && !failed && statusTone === 'warning' ? status : null);
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<article
	class="message message--{run}"
	class:message--out={outbound}
	class:message--card={card}
	class:message--pending={pending}
	class:message--failed={failed}
	class:message--scheduled={scheduledFor !== null}
	data-message-id={id}
	aria-busy={pending}
>
	<div class="message__bubble" title={hoverText}>
		{#if badges}<div class="message__badges">{@render badges()}</div>{/if}
		<div class="message__content">{@render children()}</div>
		<span class="message__meta">
			{#if scheduledFor}
				<span class="message__scheduled" aria-hidden="true">{@html calendarClockIcon}</span>
				<time datetime={scheduledFor}>{scheduledTime}</time>
				<span class="sr-only">Scheduled</span>
			{:else}
				<ChannelMark
					{channel}
					size={12}
					inverse={outbound && !card && !failed}
					label={CHANNEL_LABELS[channel]}
				/>
				<time datetime={when}>{time}</time>
				{#if outbound && !failed && tick}
					<span class="message__tick" class:message__tick--seen={mark === 'seen'} aria-hidden="true"
						>{@html tick}</span
					>
				{/if}
				{#if outbound && status}<span class="sr-only">{status}</span>{/if}
			{/if}
		</span>
		{#if actions}<div class="message__actions">{@render actions()}</div>{/if}
	</div>
	{#if failed}
		<p class="message__failure" role="status">
			<span aria-hidden="true">{@html alertIcon}</span>
			<span>{failureReason ?? status ?? 'Not sent'}</span>
			{#if onRetry}
				<button type="button" class="message__retry" onclick={onRetry}>{retryLabel}</button>
			{/if}
		</p>
	{:else if warning}
		<p class="message__warning">{warning}</p>
	{/if}
	{#if footer}<div class="message__footer">{@render footer()}</div>{/if}
</article>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.message {
		display: flex;
		width: 100%;
		flex-direction: column;
		align-items: flex-start;
		gap: 4px;

		// Runs: 3 apart inside, 5 between (the timeline's own gap is 3).
		&--single,
		&--first {
			margin-top: 2px;
		}
	}

	.message--out {
		align-items: flex-end;
	}

	.message__bubble {
		position: relative;
		display: flex;
		min-width: 0;
		max-width: min(78%, 560px);
		flex-wrap: wrap;
		align-items: flex-end;
		column-gap: 10px;
		padding: 8px 12px 7px 14px;
		border-radius: var(--radius-large);
		--message-heading: var(--color-heading);
		--message-accent: var(--color-informative--onSurface);
		color: var(--color-heading);
		background: var(--color-surface--active);
		font-size: var(--typography--fontSize-base);
		line-height: 1.5;
		overflow-wrap: anywhere;
	}

	// Corners that touch the next bubble in a run go small, so a run reads as one block.
	.message:not(.message--out) {
		&.message--first .message__bubble {
			border-bottom-left-radius: var(--radius-small);
		}
		&.message--middle .message__bubble {
			border-top-left-radius: var(--radius-small);
			border-bottom-left-radius: var(--radius-small);
		}
		&.message--last .message__bubble {
			border-top-left-radius: var(--radius-small);
		}
	}

	.message--out {
		&.message--first .message__bubble {
			border-bottom-right-radius: var(--radius-small);
		}
		&.message--middle .message__bubble {
			border-top-right-radius: var(--radius-small);
			border-bottom-right-radius: var(--radius-small);
		}
		&.message--last .message__bubble {
			border-top-right-radius: var(--radius-small);
		}

		.message__bubble {
			--message-heading: var(--color-surface);
			--message-accent: var(--color-surface);
			color: var(--color-surface);
			background: var(--color-interactive);
		}

		// Your last bubble in a run has a small tail at its bottom right, as in a messaging app.
		&.message--last .message__bubble,
		&.message--single .message__bubble {
			border-bottom-right-radius: var(--radius-small);

			&::after {
				position: absolute;
				right: -5px;
				bottom: 0;
				width: 10px;
				height: 10px;
				background: inherit;
				clip-path: polygon(0 0, 0 100%, 100% 100%);
				content: '';
			}
		}
	}

	.message__content {
		display: flex;
		min-width: 0;
		max-width: 100%;
		flex: 1 1 auto;
		flex-direction: column;
		gap: var(--space-small);
	}

	.message__badges {
		display: flex;
		width: 100%;
		flex-wrap: wrap;
		align-items: center;
		gap: var(--space-small);
		margin-bottom: var(--space-small);

		// The page always passes the snippet; when it renders nothing, the row takes no room.
		&:not(:has(*)) {
			display: none;
		}
	}

	// Channel, time and ticks sit inside the bubble at its bottom right; on a short message they share the
	// last line, on a long one they wrap under it.
	.message__meta {
		display: inline-flex;
		flex: 0 0 auto;
		align-items: center;
		gap: 4px;
		margin-left: auto;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-overline);
		font-weight: 500;
		line-height: 1.5;
		white-space: nowrap;
	}

	.message--out:not(.message--card) .message__meta {
		color: var(--color-surface);
	}

	.message__tick,
	.message__scheduled {
		display: inline-flex;

		:global(svg) {
			width: 14px;
			height: 14px;
		}
	}

	// An email: a white card with an edge, wide enough to read, whichever side it is on.
	.message--card .message__bubble {
		width: min(400px, 100%);
		border: var(--border-base) solid var(--color-border);
		--message-heading: var(--color-heading);
		--message-accent: var(--color-channel-email);
		color: var(--color-text);
		background: var(--color-surface);

		&::after {
			display: none;
		}
	}

	// Read by the customer: a filled circle in the bubble's text colour holding green ticks.
	.message__tick--seen {
		justify-content: center;
		width: 18px;
		height: 18px;
		border-radius: var(--radius-circle);
		color: var(--color-interactive);
		background: var(--color-surface);

		:global(svg) {
			width: 12px;
			height: 12px;
		}
	}

	.message--card.message--out .message__tick {
		color: var(--color-interactive);
	}

	// Waiting to go out later: a quiet bubble with an edge and its send time in the time colour.
	.message--scheduled .message__bubble {
		border: var(--border-base) solid var(--color-border);
		color: var(--color-heading);
		background: var(--color-surface--background--subtle);

		&::after {
			display: none;
		}

		.message__meta {
			color: var(--color-time);
			font-weight: 600;
		}
	}

	// Only a send still in flight reads as provisional, muted the way an unconfirmed message is in any messenger.
	.message--pending .message__bubble {
		opacity: 0.7;
	}

	// It did not reach the customer: the whole bubble turns red.
	.message--failed .message__bubble {
		border: var(--border-base) solid var(--color-critical--surface-edge);
		--message-heading: var(--color-critical--onSurface);
		--message-accent: var(--color-critical--onSurface);
		color: var(--color-critical--onSurface);
		background: var(--color-critical--surface);

		.message__meta {
			color: var(--color-critical--onSurface);
		}

		&::after {
			right: -6px;
			bottom: -1px;
			background: var(--color-critical--surface);
		}
	}

	.message__failure,
	.message__warning {
		display: inline-flex;
		align-items: center;
		gap: 4px;
		margin: 0;
		color: var(--color-critical);
		font-size: var(--typography--fontSize-overline);
		font-weight: 600;

		:global(svg) {
			width: 14px;
			height: 14px;
		}

		span:first-child {
			display: inline-flex;
		}
	}

	.message__warning {
		color: var(--color-warning--onSurface);
	}

	.message__retry {
		margin-left: 4px;
		padding: 0;
		border: 0;
		color: var(--color-interactive);
		background: none;
		font: inherit;
		font-weight: 700;
		cursor: pointer;

		&:hover {
			text-decoration: underline;
		}

		&:focus-visible {
			border-radius: var(--radius-small);
			outline: 0;
			box-shadow: var(--shadow-focus);
		}
	}

	.message__footer {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-overline);
		font-weight: 500;
	}

	/* Details, Forward, Resend and the like. They stay in the page for keyboard users and appear when the
	   message is hovered or has focus inside it. */
	.message__actions {
		position: absolute;
		top: -14px;
		right: 12px;
		display: flex;
		align-items: center;
		gap: 2px;
		padding: 3px;
		border: var(--border-base) solid var(--color-border);
		border-radius: 10px;
		color: var(--color-text);
		background: var(--color-surface);
		box-shadow: var(--shadow-base);
		opacity: 0;
		pointer-events: none;
		transition: opacity var(--timing-quick) ease-out;
	}

	.message--out .message__actions {
		right: auto;
		left: 12px;
	}

	.message__bubble:hover .message__actions,
	.message__bubble:focus-within .message__actions {
		opacity: 1;
		pointer-events: auto;
	}

	.sr-only {
		position: absolute;
		width: 1px;
		height: 1px;
		overflow: hidden;
		clip: rect(0, 0, 0, 0);
		white-space: nowrap;
	}

	@media (max-width: 700px) {
		.message__bubble {
			max-width: 88%;
		}
	}
</style>
