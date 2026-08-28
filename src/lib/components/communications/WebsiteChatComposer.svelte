<script lang="ts">
	import { useQueryClient } from '@tanstack/svelte-query';
	import Button from '$lib/components/ui/Button.svelte';
	import SnippetPickerButton from '$lib/components/communications/SnippetPickerButton.svelte';
	import {
		clientCommunicationHistoryKey,
		sendWebsiteChatStaffMessage,
		type PendingOutboundSend
	} from '$lib/communications/inbox';

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
		onPendingChange
	}: {
		sessionId: string;
		clientId: string | null;
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
</script>

<form class="website-chat-composer" onsubmit={(event) => (event.preventDefault(), submit())}>
	<div class="website-chat-composer__row">
		<label class="sr-only" for="website-chat-composer-body">Message</label>
		<textarea
			id="website-chat-composer-body"
			bind:this={textareaEl}
			bind:value={body}
			placeholder="Write a reply…"
			rows={2}
			maxlength={5000}
			onkeydown={handleKeydown}></textarea>
		<SnippetPickerButton disabled={sending} onInsert={insertSnippet} />
		<Button variant="primary" type="submit" loading={sending}>Send</Button>
	</div>
</form>

<style lang="scss">
	.website-chat-composer {
		display: flex;
		flex-direction: column;
		gap: var(--space-small);
		padding: var(--space-large);
		border-top: var(--border-base) solid var(--color-border);
		background: var(--color-surface);
	}
	.website-chat-composer__row {
		display: flex;
		align-items: flex-end;
		gap: var(--space-small);
	}
	.website-chat-composer__row textarea {
		flex: 1;
		min-height: 40px;
		padding: var(--space-small) var(--space-base);
		border: var(--border-base) solid var(--color-border--interactive);
		border-radius: var(--radius-base);
		color: var(--color-heading);
		background: var(--color-surface);
		font: inherit;
		resize: vertical;
	}
	.website-chat-composer__row textarea:focus {
		outline: none;
		box-shadow: var(--shadow-focus);
	}
	.sr-only {
		position: absolute;
		width: 1px;
		height: 1px;
		overflow: hidden;
		clip: rect(0, 0, 0, 0);
		white-space: nowrap;
	}
</style>
