<script lang="ts">
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import Badge from '$lib/components/ui/Badge.svelte';
	import type { InboundInboxMessage } from '$lib/communications/inbox';

	let {
		message,
		inReplyToSubject,
		onJumpToReplyTarget,
		onClose
	}: {
		message: InboundInboxMessage;
		/** The outbound message's subject, when it's on the currently loaded page. */
		inReplyToSubject?: string | null;
		onJumpToReplyTarget?: () => void;
		onClose: () => void;
	} = $props();

	function formatWhen(value: string) {
		return new Intl.DateTimeFormat(undefined, {
			dateStyle: 'medium',
			timeStyle: 'short'
		}).format(new Date(value));
	}

	function messageKindLabel(kind: string) {
		if (kind === 'auto_response') return 'Auto-response';
		if (kind === 'delivery_notice') return 'Delivery notice';
		if (kind === 'loop_detected') return 'Automation paused — loop detected';
		return 'Reply';
	}

	function reviewLabel(status: string, reason: string | null) {
		if (status === 'accepted') return 'Accepted into this conversation';
		if (reason === 'unknown_sender') return 'Pending review — unknown sender';
		if (reason === 'ambiguous_sender')
			return 'Pending review — sender matches more than one contact';
		if (reason === 'expired_alias') return 'Pending review — reply link expired';
		return 'Pending review';
	}
</script>

<Dialog open title="Message details" size="small" {onClose}>
	<dl class="message-details">
		<div>
			<dt>Type</dt>
			<dd>{messageKindLabel(message.message_kind)}</dd>
		</div>
		<div>
			<dt>Received</dt>
			<dd>{formatWhen(message.created_at)}</dd>
		</div>
		<div>
			<dt>From</dt>
			<dd>{message.sender_name ? `${message.sender_name} · ` : ''}{message.sender_email}</dd>
		</div>
		<div>
			<dt>Conversation</dt>
			<dd>
				<Badge status={message.review_status === 'accepted' ? 'success' : 'warning'} size="small">
					{reviewLabel(message.review_status, message.review_reason)}
				</Badge>
			</dd>
		</div>
		{#if message.in_reply_to_intent_id}
			<div>
				<dt>In reply to</dt>
				<dd>
					{#if inReplyToSubject}
						{#if onJumpToReplyTarget}
							<button type="button" class="message-details__link" onclick={onJumpToReplyTarget}>
								{inReplyToSubject}
							</button>
						{:else}
							{inReplyToSubject}
						{/if}
					{:else}
						An earlier message on this page
					{/if}
				</dd>
			</div>
		{/if}
		{#if message.automation_suppressed}
			<div>
				<dt>Automation</dt>
				<dd>Suppressed for this message</dd>
			</div>
		{/if}
		<div>
			<dt>Provider</dt>
			<dd>
				{message.provider}{message.provider_message_id ? ` · ${message.provider_message_id}` : ''}
			</dd>
		</div>
	</dl>
</Dialog>

<style lang="scss">
	.message-details {
		display: grid;
		gap: var(--space-base);
		padding: var(--space-small);

		div {
			display: grid;
			gap: var(--space-smallest);
		}

		dt {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		dd {
			margin: 0;
			color: var(--color-text);
			overflow-wrap: anywhere;
		}

		&__link {
			padding: 0;
			border: 0;
			color: var(--color-interactive--subtle);
			background: none;
			font: inherit;
			text-align: left;
			text-decoration: underline;
			cursor: pointer;
		}
	}
</style>
