<script lang="ts">
	import type { Snippet } from 'svelte';
	import Avatar from '$lib/components/ui/Avatar.svelte';
	import emailIcon from '@tabler/icons/outline/mail.svg?raw';
	import messageIcon from '@tabler/icons/outline/message-circle.svg?raw';
	import messagesIcon from '@tabler/icons/outline/messages.svg?raw';
	import checkIcon from '@tabler/icons/outline/check.svg?raw';
	import checksIcon from '@tabler/icons/outline/checks.svg?raw';
	import clockIcon from '@tabler/icons/outline/clock.svg?raw';
	import alertIcon from '@tabler/icons/outline/alert-circle.svg?raw';

	// One message in a conversation, drawn as a chat bubble: the customer's on the left in white, the
	// team's on the right in brand green, with the channel and time (and, for ours, the delivery state)
	// underneath. Everything inside the bubble -- subject, text, attachments, notices -- is the page's own,
	// passed in, so each channel keeps its own content and this only owns the shape.
	let {
		id,
		outbound = false,
		channel,
		senderId = '',
		senderName = null,
		showSender = true,
		who = null,
		when,
		unread = false,
		pending = false,
		failed = false,
		status = null,
		statusTone = 'inactive',
		badges,
		actions,
		children
	}: {
		id: string;
		outbound?: boolean;
		channel: 'email' | 'sms' | 'website_chat';
		senderId?: string;
		senderName?: string | null;
		showSender?: boolean;
		/** Who sent it, for our own messages ("Jafar Khan", "Sent automatically"). */
		who?: string | null;
		when: string;
		unread?: boolean;
		pending?: boolean;
		failed?: boolean;
		status?: string | null;
		statusTone?: 'success' | 'warning' | 'critical' | 'inactive' | 'informative';
		badges?: Snippet;
		actions?: Snippet;
		children: Snippet;
	} = $props();

	const channelIcon = $derived(
		channel === 'sms' ? messageIcon : channel === 'website_chat' ? messagesIcon : emailIcon
	);
	const time = $derived(
		new Intl.DateTimeFormat(undefined, { hour: 'numeric', minute: '2-digit' }).format(
			new Date(when)
		)
	);
	const dateTime = $derived(
		new Intl.DateTimeFormat(undefined, {
			month: 'short',
			day: 'numeric',
			hour: 'numeric',
			minute: '2-digit'
		}).format(new Date(when))
	);
	const statusIcon = $derived(
		statusTone === 'success'
			? checksIcon
			: statusTone === 'critical'
				? alertIcon
				: statusTone === 'informative'
					? clockIcon
					: checkIcon
	);
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<article
	class="message"
	class:message--out={outbound}
	class:message--unread={unread}
	class:message--pending={pending}
	class:message--failed={failed}
	data-message-id={id}
	aria-busy={pending}
>
	{#if !outbound}
		<span class="message__avatar"><Avatar id={senderId || id} name={senderName} size="base" /></span
		>
	{/if}
	<div class="message__stack">
		{#if !outbound && showSender && senderName}
			<span class="message__sender">{senderName}</span>
		{/if}
		<div class="message__bubble message__bubble--{channel}">
			{#if badges}<div class="message__badges">{@render badges()}</div>{/if}
			{@render children()}
			{#if actions}<div class="message__actions">{@render actions()}</div>{/if}
		</div>
		<div class="message__meta message__meta--{channel}">
			<span class="message__channel" aria-hidden="true">{@html channelIcon}</span>
			{#if outbound && who}<span>{who} ·</span>{/if}
			<time datetime={when} title={dateTime}>{outbound ? time : dateTime}</time>
			{#if outbound && status}
				<span class="message__status message__status--{statusTone}">
					<span class="message__status-icon" aria-hidden="true">{@html statusIcon}</span>
					{status}
				</span>
			{/if}
		</div>
	</div>
</article>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.message {
		display: flex;
		align-items: flex-end;
		gap: var(--space-small);
		width: 100%;
	}

	.message--out {
		justify-content: flex-end;
	}

	/* The avatar sits level with the bubble, not with the time line under it. */
	.message__avatar {
		display: inline-flex;
		padding-bottom: 21px;

		:global(.avatar--base) {
			width: 30px;
			height: 30px;
			font-size: var(--typography--fontSize-overline);
			font-weight: 700;
		}
	}

	.message__stack {
		display: flex;
		min-width: 0;
		max-width: min(78%, 560px);
		flex-direction: column;
		align-items: flex-start;
		gap: var(--space-smaller);
	}

	.message--out .message__stack {
		align-items: flex-end;
	}

	.message__sender {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		font-weight: 600;
	}

	.message__bubble {
		position: relative;
		display: flex;
		max-width: 100%;
		flex-direction: column;
		gap: var(--space-small);
		padding: 10px 14px;
		border: var(--border-base) solid var(--color-border);
		border-radius: 18px 18px 18px 6px;
		--message-heading: var(--color-heading);
		--message-accent: var(--color-informative--onSurface);
		color: var(--color-text);
		background: var(--color-surface);
		font-size: var(--typography--fontSize-base);
		line-height: 1.5;
		overflow-wrap: anywhere;
	}

	.message--out .message__bubble {
		border-color: transparent;
		--message-heading: #fff;
		--message-accent: #fff;
		border-radius: 18px 18px 6px 18px;
		color: #fff;
		background: var(--color-base-green--700);
	}

	.message--unread .message__bubble {
		border-color: var(--color-informative);
	}

	/* Only a send still in flight reads as provisional -- muted, the way an unconfirmed message does in any
	   messenger. A failure takes the critical ring, because at that point it is something to act on. */
	.message--pending .message__bubble {
		opacity: 0.7;
	}

	.message--failed .message__bubble {
		box-shadow: 0 0 0 var(--border-thick) var(--color-critical);
	}

	.message__badges {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: var(--space-small);
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

	.message__meta {
		display: inline-flex;
		flex-wrap: wrap;
		align-items: center;
		gap: 5px;
		padding: 0 var(--space-smaller);
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		font-weight: 500;
	}

	.message__channel {
		display: inline-flex;

		:global(svg) {
			width: 12px;
			height: 12px;
		}
	}

	.message__meta--email .message__channel {
		color: var(--color-informative--onSurface);
	}

	.message__meta--sms .message__channel {
		color: var(--color-interactive);
	}

	.message__meta--website_chat .message__channel {
		color: var(--color-dataViz--categorical--2);
	}

	.message__status {
		display: inline-flex;
		align-items: center;
		gap: var(--space-smaller);
		font-weight: 600;
	}

	.message__status-icon {
		display: inline-flex;

		:global(svg) {
			width: 13px;
			height: 13px;
		}
	}

	.message__status--success {
		color: var(--color-interactive);
	}

	.message__status--critical {
		color: var(--color-critical);
	}

	.message__status--warning {
		color: var(--color-warning--onSurface);
	}

	@media (max-width: 700px) {
		.message__stack {
			max-width: 88%;
		}
	}
</style>
