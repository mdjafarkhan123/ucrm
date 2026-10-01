<script lang="ts">
	import { tick, untrack, type Snippet } from 'svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import { dayLabel, exactTime } from '$lib/collaboration/format';
	import {
		SUPPORT_MESSAGE_MAX_LENGTH,
		type SupportMessage,
		type SupportSenderKind
	} from '$lib/support/api';
	import sendIcon from '@tabler/icons/outline/arrow-up.svg?raw';
	import alertIcon from '@tabler/icons/outline/alert-circle.svg?raw';

	// One conversation between a contractor's team member and Uplift: the messages and the box to write the
	// next one. The contractor's messenger and Jafar's Support Inbox both show it — only `viewer` differs,
	// which decides whose messages sit on the right.
	let {
		messages,
		viewer,
		loading = false,
		failed = false,
		onRetry,
		hasEarlier = false,
		loadingEarlier = false,
		onLoadEarlier,
		onSend,
		placeholder = 'Write a message…',
		blockedReason = '',
		conversationKey = '',
		empty,
		footnote
	}: {
		/** Oldest first. */
		messages: SupportMessage[];
		viewer: Extract<SupportSenderKind, 'member' | 'uplift'>;
		loading?: boolean;
		failed?: boolean;
		onRetry?: () => void;
		hasEarlier?: boolean;
		loadingEarlier?: boolean;
		onLoadEarlier?: () => void;
		/** Stores the message and resolves once it is saved. The same id on a retry never posts twice. */
		onSend: (input: { body: string; client_message_id: string }) => Promise<void>;
		placeholder?: string;
		/** Why nothing can be sent right now. Shown in place of the composer's hint, and Send is off. */
		blockedReason?: string;
		/** Changes when a different conversation is shown, so drafts and unsent messages never cross over. */
		conversationKey?: string;
		empty?: Snippet;
		footnote?: Snippet;
	} = $props();

	const uid = $props.id();

	type Outgoing = {
		client_message_id: string;
		body: string;
		status: 'sending' | 'failed';
		error: string;
	};

	let draft = $state('');
	let outgoing = $state<Outgoing[]>([]);
	let timelineEl = $state<HTMLDivElement | null>(null);
	let inputEl = $state<HTMLTextAreaElement | null>(null);

	// A different conversation starts clean.
	$effect(() => {
		void conversationKey;
		untrack(() => {
			draft = '';
			outgoing = [];
		});
	});

	type Row =
		| { kind: 'day'; key: string; label: string }
		| { kind: 'message'; key: string; message: SupportMessage; mine: boolean };

	const rows = $derived.by(() => {
		const result: Row[] = [];
		let previousDay = '';
		for (const message of messages) {
			const day = dayLabel(message.created_at);
			if (day !== previousDay) {
				result.push({ kind: 'day', key: `day-${message.id}`, label: day });
				previousDay = day;
			}
			result.push({
				kind: 'message',
				key: message.id,
				message,
				mine: message.sender_kind === viewer
			});
		}
		return result;
	});

	// The contractor sees the team name and the real person behind it; Jafar sees the team member's name.
	function senderLabel(message: SupportMessage) {
		if (message.sender_kind === viewer) return 'You';
		if (message.sender_kind === 'uplift') return `Uplift Support · ${message.sender_name}`;
		return message.sender_name;
	}

	const timeFormat = new Intl.DateTimeFormat(undefined, { hour: 'numeric', minute: '2-digit' });
	function clockTime(value: string) {
		const date = new Date(value);
		return Number.isNaN(date.getTime()) ? '' : timeFormat.format(date);
	}

	// Follows the conversation to its newest message — when it first appears and whenever one arrives or is
	// sent — unless the person has scrolled up to read earlier ones.
	let pinnedToEnd = true;
	function trackScroll() {
		if (!timelineEl) return;
		pinnedToEnd = timelineEl.scrollHeight - timelineEl.scrollTop - timelineEl.clientHeight < 80;
	}
	const lastMessageId = $derived(messages.at(-1)?.id ?? '');
	$effect(() => {
		void lastMessageId;
		void outgoing.length;
		if (!timelineEl || !pinnedToEnd) return;
		void tick().then(() => {
			if (timelineEl) timelineEl.scrollTop = timelineEl.scrollHeight;
		});
	});

	// Loading earlier messages adds them above; the message the person was reading stays where it was.
	async function loadEarlier() {
		if (!timelineEl || !onLoadEarlier) return;
		const before = timelineEl.scrollHeight - timelineEl.scrollTop;
		pinnedToEnd = false;
		onLoadEarlier();
		await tick();
		const restore = () => {
			if (timelineEl) timelineEl.scrollTop = timelineEl.scrollHeight - before;
		};
		// The earlier page arrives after a fetch, so hold the position until the list has grown.
		const observer = new MutationObserver(() => {
			restore();
			observer.disconnect();
		});
		observer.observe(timelineEl, { childList: true, subtree: true });
		setTimeout(() => observer.disconnect(), 5000);
	}

	const trimmed = $derived(draft.trim());
	const tooLong = $derived(trimmed.length > SUPPORT_MESSAGE_MAX_LENGTH);
	const canSend = $derived(trimmed.length > 0 && !tooLong && !blockedReason);

	async function deliver(item: Outgoing) {
		try {
			await onSend({ body: item.body, client_message_id: item.client_message_id });
			outgoing = outgoing.filter((entry) => entry.client_message_id !== item.client_message_id);
		} catch (error) {
			outgoing = outgoing.map((entry) =>
				entry.client_message_id === item.client_message_id
					? {
							...entry,
							status: 'failed',
							error: error instanceof Error ? error.message : 'Your message could not be sent.'
						}
					: entry
			);
		}
	}

	function send() {
		if (!canSend) return;
		const item: Outgoing = {
			client_message_id: crypto.randomUUID(),
			body: trimmed,
			status: 'sending',
			error: ''
		};
		outgoing = [...outgoing, item];
		draft = '';
		pinnedToEnd = true;
		resizeInput();
		void deliver(item);
	}

	function retry(item: Outgoing) {
		outgoing = outgoing.map((entry) =>
			entry.client_message_id === item.client_message_id
				? { ...entry, status: 'sending', error: '' }
				: entry
		);
		void deliver(item);
	}

	function discard(item: Outgoing) {
		outgoing = outgoing.filter((entry) => entry.client_message_id !== item.client_message_id);
	}

	// Enter sends and Shift+Enter starts a new line, as every messenger does. While an input method is
	// composing a character, Enter belongs to it.
	function handleKeydown(event: KeyboardEvent) {
		if (event.key !== 'Enter' || event.shiftKey || event.isComposing) return;
		event.preventDefault();
		send();
	}

	// The box grows with what is typed, up to a few lines, then scrolls.
	function resizeInput() {
		void tick().then(() => {
			if (!inputEl) return;
			inputEl.style.height = 'auto';
			inputEl.style.height = `${Math.min(inputEl.scrollHeight, 132)}px`;
		});
	}

	export function focusComposer() {
		inputEl?.focus();
	}
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<div class="support-conversation">
	<div
		class="support-conversation__timeline"
		bind:this={timelineEl}
		onscroll={trackScroll}
		role="log"
		aria-label="Conversation"
		aria-live="polite"
		tabindex="-1"
	>
		{#if loading}
			<LoadingSkeleton variant="text" rows={4} label="Loading conversation" />
		{:else if failed}
			<ErrorState description="This conversation could not be loaded." retry={onRetry} />
		{:else}
			{#if hasEarlier}
				<div class="support-conversation__earlier">
					<Button
						variant="tertiary"
						size="small"
						loading={loadingEarlier}
						onclick={() => void loadEarlier()}>Show earlier messages</Button
					>
				</div>
			{/if}

			{#if rows.length === 0 && outgoing.length === 0}
				<div class="support-conversation__empty">{@render empty?.()}</div>
			{/if}

			{#each rows as row (row.key)}
				{#if row.kind === 'day'}
					<p class="support-conversation__day"><span>{row.label}</span></p>
				{:else}
					<div
						class="support-conversation__message"
						class:support-conversation__message--mine={row.mine}
					>
						<p class="support-conversation__bubble">{row.message.body}</p>
						<p class="support-conversation__meta">
							<span>{senderLabel(row.message)}</span>
							<time datetime={row.message.created_at} title={exactTime(row.message.created_at)}
								>{clockTime(row.message.created_at)}</time
							>
						</p>
					</div>
				{/if}
			{/each}

			{#each outgoing as item (item.client_message_id)}
				<div
					class="support-conversation__message support-conversation__message--mine"
					class:support-conversation__message--failed={item.status === 'failed'}
				>
					<p class="support-conversation__bubble support-conversation__bubble--pending">
						{item.body}
					</p>
					{#if item.status === 'sending'}
						<p class="support-conversation__meta"><span>Sending…</span></p>
					{:else}
						<p class="support-conversation__meta support-conversation__meta--failed" role="alert">
							<span class="support-conversation__meta-icon" aria-hidden="true"
								>{@html alertIcon}</span
							>
							<span>{item.error}</span>
							<button type="button" onclick={() => retry(item)}>Try again</button>
							<button type="button" onclick={() => discard(item)}>Delete</button>
						</p>
					{/if}
				</div>
			{/each}
		{/if}
	</div>

	<form
		class="support-conversation__composer"
		onsubmit={(event) => {
			event.preventDefault();
			send();
		}}
	>
		<div class="support-conversation__field" class:support-conversation__field--invalid={tooLong}>
			<label class="support-conversation__label" for={`${uid}-message`}>Message</label>
			<textarea
				id={`${uid}-message`}
				bind:this={inputEl}
				bind:value={draft}
				rows="1"
				{placeholder}
				disabled={failed}
				aria-invalid={tooLong}
				aria-describedby={`${uid}-hint`}
				aria-keyshortcuts="Enter"
				oninput={resizeInput}
				onkeydown={handleKeydown}></textarea>
			<button
				class="support-conversation__send"
				type="submit"
				disabled={!canSend}
				aria-label="Send message"
				title="Send message"
			>
				<span aria-hidden="true">{@html sendIcon}</span>
			</button>
		</div>
		<p
			id={`${uid}-hint`}
			class="support-conversation__hint"
			class:support-conversation__hint--warning={tooLong || Boolean(blockedReason)}
		>
			{#if tooLong}
				This message is {trimmed.length - SUPPORT_MESSAGE_MAX_LENGTH} characters too long.
			{:else if blockedReason}
				{blockedReason}
			{:else}
				{@render footnote?.()}
			{/if}
		</p>
	</form>
</div>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.support-conversation {
		display: flex;
		flex: 1;
		flex-direction: column;
		min-height: 0;
		background: var(--color-surface);

		&__timeline {
			display: flex;
			flex: 1;
			flex-direction: column;
			gap: var(--space-small);
			min-height: 0;
			padding: var(--space-base);
			overflow-y: auto;
			overscroll-behavior: contain;

			&:focus-visible {
				outline: none;
				box-shadow: inset 0 0 0 2px var(--color-focus);
			}
		}

		&__earlier {
			display: flex;
			justify-content: center;
		}

		&__empty {
			display: flex;
			flex: 1;
			flex-direction: column;
			justify-content: center;
		}

		&__day {
			display: flex;
			align-items: center;
			gap: var(--space-small);
			margin: var(--space-smaller) 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			font-weight: 600;

			&::before,
			&::after {
				flex: 1;
				height: var(--border-base);
				background: var(--color-border);
				content: '';
			}
		}

		&__message {
			display: flex;
			flex-direction: column;
			align-items: flex-start;
			gap: var(--space-smallest);
			max-width: 86%;

			&--mine {
				align-items: flex-end;
				align-self: flex-end;
			}
		}

		&__bubble {
			margin: 0;
			padding: var(--space-small) var(--space-slim);
			border-radius: var(--radius-large) var(--radius-large) var(--radius-large) var(--radius-small);
			color: var(--color-text);
			font-size: var(--typography--fontSize-base);
			line-height: var(--typography--lineHeight-base);
			background: var(--color-surface--background--subtle);
			box-shadow: inset 0 0 0 var(--border-base) var(--color-border);
			white-space: pre-wrap;
			overflow-wrap: anywhere;

			&--pending {
				opacity: 0.7;
			}
		}

		&__message--mine &__bubble {
			border-radius: var(--radius-large) var(--radius-large) var(--radius-small) var(--radius-large);
			background: var(--color-interactive--background);
			box-shadow: none;
		}

		&__message--failed &__bubble {
			box-shadow: inset 0 0 0 var(--border-base) var(--color-critical);
			opacity: 1;
		}

		&__meta {
			display: flex;
			flex-wrap: wrap;
			align-items: center;
			gap: var(--space-smaller);
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);

			time::before {
				margin-right: var(--space-smaller);
				content: '·';
			}

			&--failed {
				color: var(--color-critical);

				button {
					padding: 0;
					border: 0;
					color: var(--color-interactive);
					font: inherit;
					font-weight: 600;
					background: none;
					cursor: pointer;

					&:hover {
						color: var(--color-interactive--hover);
						text-decoration: underline;
					}

					&:focus-visible {
						border-radius: var(--radius-small);
						outline: none;
						box-shadow: var(--shadow-focus);
					}
				}
			}
		}

		&__meta-icon {
			display: inline-flex;

			:global(svg) {
				width: 14px;
				height: 14px;
			}
		}

		&__composer {
			display: flex;
			flex: none;
			flex-direction: column;
			gap: var(--space-smaller);
			padding: var(--space-small) var(--space-base) var(--space-slim);
			border-top: var(--border-base) solid var(--color-border);
		}

		// Read by screen readers only; the placeholder already tells sighted people what the box is for.
		&__label {
			position: absolute;
			width: 1px;
			height: 1px;
			padding: 0;
			margin: -1px;
			overflow: hidden;
			clip: rect(0, 0, 0, 0);
			white-space: nowrap;
			border: 0;
		}

		&__field {
			display: flex;
			align-items: flex-end;
			gap: var(--space-small);
			padding: var(--space-smaller) var(--space-smaller) var(--space-smaller) var(--space-slim);
			border: var(--border-base) solid var(--color-border--interactive);
			border-radius: var(--radius-large);
			background: var(--color-surface);
			transition: box-shadow var(--timing-quick) ease;

			&:focus-within {
				border-color: var(--color-focus);
				box-shadow: var(--shadow-focus);
			}

			&--invalid {
				border-color: var(--color-critical);
			}

			textarea {
				flex: 1;
				min-width: 0;
				max-height: 132px;
				padding: var(--space-smaller) 0;
				border: 0;
				color: var(--color-text);
				font: inherit;
				// 16px keeps iOS from zooming the page when the box is focused.
				font-size: max(16px, var(--typography--fontSize-base));
				line-height: var(--typography--lineHeight-base);
				background: transparent;
				outline: none;
				resize: none;

				// The field around it already shows the focus ring; the app-wide one would draw a second box inside.
				&:focus-visible {
					box-shadow: none;
				}

				// The app-wide placeholder offset makes room for a floating label; this box has none, and the offset
				// would push the hint below the one-line box.
				&::placeholder {
					padding-top: 0;
					color: var(--color-text--secondary);
				}

				&:disabled {
					cursor: not-allowed;
				}
			}
		}

		&__send {
			display: grid;
			flex: none;
			place-items: center;
			width: 32px;
			height: 32px;
			padding: 0;
			border: 0;
			border-radius: var(--radius-circle);
			color: var(--color-surface);
			background: var(--color-interactive);
			cursor: pointer;
			transition: background var(--timing-quick) ease;

			span {
				display: inline-flex;
			}

			:global(svg) {
				width: 18px;
				height: 18px;
			}

			&:hover:not(:disabled) {
				background: var(--color-interactive--hover);
			}

			&:focus-visible {
				outline: none;
				box-shadow: var(--shadow-focus);
			}

			&:disabled {
				color: var(--color-disabled);
				background: var(--color-disabled--secondary);
				cursor: not-allowed;
			}
		}

		&__hint {
			min-height: 1.6rem;
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);

			&--warning {
				color: var(--color-critical);
			}
		}
	}
</style>
