<script lang="ts">
	import { useQueryClient } from '@tanstack/svelte-query';
	import Button from '$lib/components/ui/Button.svelte';
	import SnippetPickerButton from '$lib/components/communications/SnippetPickerButton.svelte';
	import ComposerChannelMenu from '$lib/components/communications/ComposerChannelMenu.svelte';
	import {
		clientCommunicationHistoryKey,
		sendWebsiteChatStaffMessage,
		type PendingOutboundSend
	} from '$lib/communications/inbox';
	import sendIcon from '@tabler/icons/outline/send-2.svg?raw';
	import minusIcon from '@tabler/icons/outline/minus.svg?raw';

	// No subject, no attachments (WC6), Enter sends -- a chat message is a body, the same shape the
	// visitor's own send already has. The parent remounts this with {#key group.key} when the selected
	// conversation changes, so the draft resets for free instead of needing an effect.
	//
	// `onPendingChange` hands the in-flight send up to the timeline, which draws it as a bubble the moment
	// Send is pressed. This composer already held the attempt and its idempotency key; what changed is
	// where the attempt is shown -- on its own bubble rather than as an error line above the box.
	let {
		sessionId,
		clientId,
		channels,
		onChannelChange,
		expanded = $bindable(false),
		onPendingChange
	}: {
		sessionId: string;
		clientId: string | null;
		channels: Array<'email' | 'sms' | 'website_chat'>;
		onChannelChange: (channel: 'email' | 'sms' | 'website_chat') => void;
		expanded?: boolean;
		onPendingChange?: (pending: PendingOutboundSend | null) => void;
	} = $props();

	const queryClient = useQueryClient();

	// A held idempotency key survives a failed send so "Retry" replays the same attempt instead of
	// posting a second bubble -- the same contract the visitor's own widget retry already relies on.
	type Attempt = { id: string; body: string };

	let body = $state('');
	let sending = $state(false);
	let textareaEl = $state<HTMLTextAreaElement | null>(null);

	function publish(state: 'sending' | 'sent' | 'failed', attempt: Attempt, error = '') {
		onPendingChange?.({
			id: attempt.id,
			channel: 'website_chat',
			subject: null,
			body: attempt.body,
			created_at: new Date().toISOString(),
			state,
			status: null,
			error,
			retry: () => void deliver(attempt)
		});
	}

	async function deliver(attempt: Attempt) {
		sending = true;
		publish('sending', attempt);
		try {
			await sendWebsiteChatStaffMessage(sessionId, attempt.body, attempt.id);
			// The mark clears here, on acceptance, rather than after the re-read below -- the server has the
			// message, which is the fact the user is waiting on. Chat has no delivery status of its own, so an
			// accepted message simply reads as an ordinary sent bubble from this point.
			publish('sent', attempt);

			// The re-read still runs, now behind an already-confirmed bubble. Awaiting it before dropping the
			// bubble keeps the swap seamless: the real row is in the cache before the bubble goes.
			await Promise.all([
				queryClient.invalidateQueries({ queryKey: ['communications', 'inbox'] }),
				clientId
					? queryClient.invalidateQueries({ queryKey: clientCommunicationHistoryKey(clientId) })
					: Promise.resolve()
			]);
			onPendingChange?.(null);
		} catch (error) {
			publish('failed', attempt, (error as Error).message);
		} finally {
			sending = false;
		}
	}

	function submit() {
		if (sending) return;
		const text = body.trim();
		if (!text) return;
		body = '';
		textareaEl?.focus();
		void deliver({ id: crypto.randomUUID(), body: text });
	}

	function handleKeydown(event: KeyboardEvent) {
		if (event.key !== 'Enter' || event.shiftKey) return;
		event.preventDefault();
		submit();
	}

	// A real element ref is on hand here (unlike the wrapped Textarea in ConversationComposer), so this
	// inserts at the caret and restores focus there -- true "editable after insertion".
	function insertSnippet(text: string) {
		const el = textareaEl;
		if (!el) {
			body = body.trim().length > 0 ? `${body}\n${text}` : text;
			return;
		}
		const start = el.selectionStart ?? body.length;
		const end = el.selectionEnd ?? body.length;
		body = body.slice(0, start) + text + body.slice(end);
		const caret = start + text.length;
		requestAnimationFrame(() => {
			el.focus();
			el.setSelectionRange(caret, caret);
		});
	}

	function expand() {
		expanded = true;
		requestAnimationFrame(() => textareaEl?.focus());
	}
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<div class="website-chat-composer" class:website-chat-composer--expanded={expanded}>
	{#if !expanded}
		<div class="website-chat-composer__collapsed">
			<ComposerChannelMenu channel="website_chat" {channels} onSelect={onChannelChange} />
			<button
				type="button"
				class="website-chat-composer__collapsed-input"
				aria-expanded="false"
				aria-controls="website-chat-composer-expanded"
				onclick={expand}>Type a message</button
			>
			<button
				class="website-chat-composer__collapsed-send"
				type="button"
				aria-label="Send"
				disabled
			>
				{@html sendIcon}
			</button>
		</div>
	{:else}
		<form
			id="website-chat-composer-expanded"
			class="website-chat-composer__form"
			onsubmit={(event) => (event.preventDefault(), submit())}
		>
			<header class="website-chat-composer__header">
				<ComposerChannelMenu channel="website_chat" {channels} onSelect={onChannelChange} />
				<button
					type="button"
					class="website-chat-composer__collapse"
					aria-label="Minimize composer"
					title="Minimize composer"
					onclick={() => (expanded = false)}
				>
					{@html minusIcon}
				</button>
			</header>
			<div class="website-chat-composer__row">
				<label class="sr-only" for="website-chat-composer-body">Message</label>
				<textarea
					id="website-chat-composer-body"
					bind:this={textareaEl}
					bind:value={body}
					placeholder="Write a reply…"
					rows={3}
					maxlength={5000}
					onkeydown={handleKeydown}></textarea>
			</div>
			<footer class="website-chat-composer__footer">
				<SnippetPickerButton disabled={sending} onInsert={insertSnippet} />
				<Button variant="primary" type="submit" loading={sending}>Send</Button>
			</footer>
		</form>
	{/if}
</div>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.website-chat-composer {
		border-top: var(--border-base) solid var(--color-border);
		background: var(--color-surface);
	}

	.website-chat-composer--expanded {
		padding: var(--space-small);
	}

	.website-chat-composer__collapsed {
		display: flex;
		width: 100%;
		align-items: center;
		gap: var(--space-smaller);
		padding: var(--space-small);
		background: var(--color-surface);
	}

	.website-chat-composer__collapsed-input {
		min-width: 0;
		min-height: 34px;
		flex: 1;
		padding: 0 var(--space-small);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-small);
		color: var(--color-text--secondary);
		background: var(--color-surface);
		font: inherit;
		font-size: var(--typography--fontSize-base);
		text-align: left;
		cursor: text;
		transition: background-color var(--timing-quick);

		&:hover {
			background: var(--color-surface--hover);
		}
	}

	.website-chat-composer__collapsed-input:focus-visible,
	.website-chat-composer__collapse:focus-visible,
	.website-chat-composer__collapsed-send:focus-visible {
		outline: none;
		box-shadow: var(--shadow-focus);
	}

	.website-chat-composer__collapsed-send {
		display: inline-flex;
		width: 38px;
		height: 34px;
		flex: 0 0 auto;
		align-items: center;
		justify-content: center;
		padding: 0;
		border: 0;
		border-radius: var(--radius-small);
		color: var(--color-disabled);
		background: var(--color-disabled--secondary);
	}

	.website-chat-composer__collapsed-send :global(svg) {
		width: 18px;
		height: 18px;
	}

	.website-chat-composer__form {
		display: flex;
		flex-direction: column;
		border: var(--border-base) solid var(--color-border--interactive);
		border-radius: var(--radius-base);
		background: var(--color-surface);
		overflow: hidden;

		&:focus-within {
			border-color: var(--color-focus);
		}
	}

	.website-chat-composer__header {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-small);
		padding: var(--space-small);
		border-bottom: var(--border-base) solid var(--color-border);
		background: var(--color-surface--background--subtle);
	}

	.website-chat-composer__collapse {
		display: inline-flex;
		width: 32px;
		height: 32px;
		align-items: center;
		justify-content: center;
		padding: 0;
		border: 0;
		border-radius: var(--radius-base);
		color: var(--color-icon--secondary);
		background: transparent;
		cursor: pointer;
	}

	.website-chat-composer__collapse:hover {
		color: var(--color-heading);
		background: var(--color-surface--hover);
	}

	.website-chat-composer__collapse :global(svg) {
		width: 18px;
		height: 18px;
	}

	.website-chat-composer__row {
		display: flex;
		min-height: 116px;
		align-items: flex-end;
		padding: var(--space-small);
		border-bottom: var(--border-base) solid var(--color-border);
	}

	.website-chat-composer__row textarea {
		display: block;
		width: 100%;
		flex: 1;
		min-height: 100px;
		padding: 0;
		border: 0;
		outline: none;
		box-shadow: none;
		color: var(--color-heading);
		background: transparent;
		font: inherit;
		font-size: var(--typography--fontSize-base);
		line-height: var(--typography--lineHeight-base);
		resize: vertical;
	}

	.website-chat-composer__row textarea::placeholder {
		color: var(--color-text--secondary);
	}

	.website-chat-composer__footer {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-small);
		padding: var(--space-small);
	}

	.sr-only {
		position: absolute;
		width: 1px;
		height: 1px;
		overflow: hidden;
		clip: rect(0, 0, 0, 0);
		white-space: nowrap;
	}

	@media (max-width: 560px) {
		.website-chat-composer--expanded {
			padding: var(--space-smallest);
		}

		.website-chat-composer__collapsed {
			padding: var(--space-smaller);
		}
	}
</style>
