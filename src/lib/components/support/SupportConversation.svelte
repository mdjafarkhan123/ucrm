<script lang="ts">
	import { tick, untrack, type Snippet } from 'svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import Lightbox, { type LightboxItem } from '$lib/components/ui/Lightbox.svelte';
	import ConversationAttachments from '$lib/components/communications/ConversationAttachments.svelte';
	import { dayLabel, exactTime, formatFileSize } from '$lib/collaboration/format';
	import { iconForMimeType } from '$lib/collaboration/file-icons';
	import {
		SUPPORT_MAX_ATTACHMENTS,
		SUPPORT_MESSAGE_MAX_LENGTH,
		isSupportPhoto,
		type SupportAttachment,
		type SupportAttachmentUpload,
		type SupportFileUrls,
		type SupportMessage,
		type SupportOutgoingMessage,
		type SupportSenderKind,
		type SupportUploadTicket
	} from '$lib/support/api';
	import sendIcon from '@tabler/icons/outline/arrow-up.svg?raw';
	import alertIcon from '@tabler/icons/outline/alert-circle.svg?raw';
	import downloadIcon from '@tabler/icons/outline/download.svg?raw';

	// One conversation between a contractor's team and Uplift: the messages and the box to write the next
	// one. The contractor's messenger and Jafar's Support Inbox both show it. `viewer` decides whose messages
	// sit on the right: Uplift's for Jafar; for a member, only their own (`viewerUserId`), since teammates
	// may write in the same conversation (D3). Grey system lines record who was added or removed.
	//
	// Files (D4b): the paperclip uploads each file as it is picked — the customer inbox's own control — and
	// Send carries them with the words, or on their own. Photos show in the conversation and open big; every
	// other file is a row that downloads.
	let {
		messages,
		viewer,
		viewerUserId = null,
		loading = false,
		failed = false,
		onRetry,
		hasEarlier = false,
		loadingEarlier = false,
		onLoadEarlier,
		onSend,
		presignAttachment,
		fileUrls,
		placeholder = 'Write a message…',
		blockedReason = '',
		conversationKey = '',
		empty,
		footnote
	}: {
		/** Oldest first. */
		messages: SupportMessage[];
		viewer: Extract<SupportSenderKind, 'member' | 'uplift'>;
		/** The signed-in member, so their own messages are told apart from a teammate's. */
		viewerUserId?: string | null;
		loading?: boolean;
		failed?: boolean;
		onRetry?: () => void;
		hasEarlier?: boolean;
		loadingEarlier?: boolean;
		onLoadEarlier?: () => void;
		/** Stores the message and resolves once it is saved. The same id on a retry never posts twice. */
		onSend: (input: SupportOutgoingMessage) => Promise<void>;
		/** Asks this side's route for somewhere to upload a picked file. */
		presignAttachment: (file: {
			fileName: string;
			mimeType: string;
			sizeBytes: number;
		}) => Promise<SupportUploadTicket>;
		/** Where this side reads a conversation's files from. */
		fileUrls: SupportFileUrls;
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
		attachments: SupportAttachmentUpload[];
		status: 'sending' | 'failed';
		error: string;
	};

	let draft = $state('');
	let outgoing = $state<Outgoing[]>([]);
	let timelineEl = $state<HTMLDivElement | null>(null);
	let inputEl = $state<HTMLTextAreaElement | null>(null);
	let attachmentsField = $state<ReturnType<typeof ConversationAttachments> | null>(null);
	let uploading = $state(false);
	let readyFiles = $state(0);

	// A different conversation starts clean.
	$effect(() => {
		void conversationKey;
		untrack(() => {
			draft = '';
			outgoing = [];
			attachmentsField?.reset();
		});
	});

	type Row =
		| { kind: 'day'; key: string; label: string }
		| { kind: 'system'; key: string; message: SupportMessage }
		| {
				kind: 'message';
				key: string;
				message: SupportMessage;
				mine: boolean;
				photos: SupportAttachment[];
				files: SupportAttachment[];
		  };

	function isMine(message: SupportMessage) {
		if (viewer === 'uplift') return message.sender_kind === 'uplift';
		return message.sender_kind === 'member' && message.sender_user_id === viewerUserId;
	}

	const rows = $derived.by(() => {
		const result: Row[] = [];
		let previousDay = '';
		for (const message of messages) {
			const day = dayLabel(message.created_at);
			if (day !== previousDay) {
				result.push({ kind: 'day', key: `day-${message.id}`, label: day });
				previousDay = day;
			}
			if (message.sender_kind === 'system') {
				result.push({ kind: 'system', key: message.id, message });
				continue;
			}
			const attachments = message.attachments ?? [];
			result.push({
				kind: 'message',
				key: message.id,
				message,
				mine: isMine(message),
				photos: attachments.filter((attachment) => isSupportPhoto(attachment.mime_type)),
				files: attachments.filter((attachment) => !isSupportPhoto(attachment.mime_type))
			});
		}
		return result;
	});

	// Every photo in the loaded conversation, oldest first, so the big view steps through them all.
	const photos = $derived(
		messages.flatMap((message) =>
			(message.attachments ?? []).filter((attachment) => isSupportPhoto(attachment.mime_type))
		)
	);
	const lightboxItems = $derived<LightboxItem[]>(
		photos.map((photo) => ({
			id: photo.id,
			src: fileUrls.view(photo, 'full'),
			thumbSrc: fileUrls.view(photo, 'thumb'),
			caption: photo.file_name
		}))
	);
	let lightboxOpen = $state(false);
	let lightboxIndex = $state(0);

	function openPhoto(photo: SupportAttachment) {
		const index = photos.findIndex((item) => item.id === photo.id);
		if (index < 0) return;
		lightboxIndex = index;
		lightboxOpen = true;
	}

	function downloadPhoto(item: LightboxItem) {
		const photo = photos.find((candidate) => candidate.id === item.id);
		// The route answers with a file to keep, so the page stays where it is.
		if (photo) window.location.assign(fileUrls.download(photo));
	}

	// The contractor sees the team name and the real person behind it; Jafar sees the team member's name.
	function senderLabel(message: SupportMessage) {
		if (isMine(message)) return 'You';
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
	const canSend = $derived(
		(trimmed.length > 0 || readyFiles > 0) && !tooLong && !blockedReason && !uploading
	);

	async function deliver(item: Outgoing) {
		try {
			await onSend({
				body: item.body,
				client_message_id: item.client_message_id,
				attachments: item.attachments
			});
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
			attachments: attachmentsField?.getAttachments() ?? [],
			status: 'sending',
			error: ''
		};
		outgoing = [...outgoing, item];
		draft = '';
		attachmentsField?.reset();
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

	// A screenshot or copied file pasted into the box attaches, as it does in every messenger. Pasted text
	// is left to the box.
	function handlePaste(event: ClipboardEvent) {
		const files = Array.from(event.clipboardData?.files ?? []);
		if (files.length === 0) return;
		event.preventDefault();
		attachmentsField?.add(files);
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
				{:else if row.kind === 'system'}
					<p class="support-conversation__system">
						{row.message.body}
						<time datetime={row.message.created_at} title={exactTime(row.message.created_at)}
							>{clockTime(row.message.created_at)}</time
						>
					</p>
				{:else}
					<div
						class="support-conversation__message"
						class:support-conversation__message--mine={row.mine}
					>
						{#if row.photos.length > 0}
							<div
								class="support-conversation__photos"
								class:support-conversation__photos--single={row.photos.length === 1}
							>
								{#each row.photos as photo (photo.id)}
									<button
										type="button"
										class="support-conversation__photo"
										aria-label={`Open ${photo.file_name}`}
										onclick={() => openPhoto(photo)}
									>
										<img src={fileUrls.view(photo, 'thumb')} alt={photo.file_name} loading="lazy" />
									</button>
								{/each}
							</div>
						{/if}
						{#if row.files.length > 0}
							<ul class="support-conversation__files">
								{#each row.files as file (file.id)}
									<li>
										<!-- eslint-disable svelte/no-navigation-without-resolve -- fileUrls already resolves the path; only the query is appended. -->
										<a
											class="support-conversation__file"
											href={fileUrls.download(file)}
											download={file.file_name}
											title={`Download ${file.file_name}`}
										>
											<span class="support-conversation__file-icon" aria-hidden="true"
												>{@html iconForMimeType(file.mime_type)}</span
											>
											<span class="support-conversation__file-text">
												<span class="support-conversation__file-name">{file.file_name}</span>
												<span class="support-conversation__file-size"
													>{formatFileSize(file.byte_size)}</span
												>
											</span>
											<span class="support-conversation__file-action" aria-hidden="true"
												>{@html downloadIcon}</span
											>
										</a>
										<!-- eslint-enable svelte/no-navigation-without-resolve -->
									</li>
								{/each}
							</ul>
						{/if}
						{#if row.message.body}
							<p class="support-conversation__bubble">{row.message.body}</p>
						{/if}
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
					{#if item.attachments.length > 0}
						<ul class="support-conversation__files support-conversation__files--pending">
							{#each item.attachments as file (file.object_key)}
								<li>
									<span class="support-conversation__file">
										<span class="support-conversation__file-icon" aria-hidden="true"
											>{@html iconForMimeType(file.mime_type)}</span
										>
										<span class="support-conversation__file-text">
											<span class="support-conversation__file-name">{file.file_name}</span>
										</span>
									</span>
								</li>
							{/each}
						</ul>
					{/if}
					{#if item.body}
						<p class="support-conversation__bubble support-conversation__bubble--pending">
							{item.body}
						</p>
					{/if}
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
				onkeydown={handleKeydown}
				onpaste={handlePaste}></textarea>
			<div class="support-conversation__tools">
				<div class="support-conversation__attach">
					<ConversationAttachments
						bind:this={attachmentsField}
						presign={presignAttachment}
						maxFiles={SUPPORT_MAX_ATTACHMENTS}
						triggerFirst
						disabled={failed || Boolean(blockedReason)}
						onUploadingChange={(value) => (uploading = value)}
						onReadyChange={(count) => (readyFiles = count)}
					/>
				</div>
				<button
					class="support-conversation__send"
					type="submit"
					disabled={!canSend}
					aria-label="Send message"
					title={uploading ? 'Wait for the files to finish uploading' : 'Send message'}
				>
					<span aria-hidden="true">{@html sendIcon}</span>
				</button>
			</div>
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

<Lightbox
	open={lightboxOpen}
	items={lightboxItems}
	bind:index={lightboxIndex}
	onClose={() => (lightboxOpen = false)}
	onDownload={downloadPhoto}
/>

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
			gap: var(--space-base);
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

		&__system {
			margin: 0;
			align-self: center;
			max-width: 90%;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			line-height: var(--typography--lineHeight-base);
			text-align: center;

			time {
				margin-left: var(--space-smaller);
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

		// Photos sit above the words as a small grid; one photo alone is shown larger.
		&__photos {
			display: grid;
			grid-template-columns: repeat(2, 112px);
			gap: var(--space-smaller);

			&--single {
				grid-template-columns: minmax(0, 220px);
			}
		}

		&__photo {
			display: block;
			aspect-ratio: 1;
			padding: 0;
			overflow: hidden;
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-large);
			background: var(--color-surface--background--subtle);
			cursor: zoom-in;
			transition: border-color var(--timing-quick) ease;

			img {
				display: block;
				width: 100%;
				height: 100%;
				object-fit: cover;
			}

			&:hover {
				border-color: var(--color-border--interactive);
			}

			&:focus-visible {
				outline: none;
				box-shadow: var(--shadow-focus);
			}
		}

		&__photos--single &__photo {
			aspect-ratio: 4 / 3;
		}

		&__files {
			display: flex;
			flex-direction: column;
			gap: var(--space-smaller);
			max-width: 100%;
			margin: 0;
			padding: 0;
			list-style: none;

			&--pending {
				opacity: 0.7;
			}
		}

		&__file {
			display: flex;
			align-items: center;
			gap: var(--space-small);
			min-width: 0;
			padding: var(--space-small) var(--space-slim);
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-large);
			color: var(--color-text);
			font-size: var(--typography--fontSize-base);
			text-decoration: none;
			background: var(--color-surface);
			transition:
				border-color var(--timing-quick) ease,
				background var(--timing-quick) ease;
		}

		a#{&}__file {
			&:hover {
				border-color: var(--color-border--interactive);
				background: var(--color-surface--hover);
			}

			&:focus-visible {
				outline: none;
				box-shadow: var(--shadow-focus);
			}
		}

		&__file-icon,
		&__file-action {
			display: inline-flex;
			flex: none;
			color: var(--color-icon);

			:global(svg) {
				width: 20px;
				height: 20px;
			}
		}

		&__file-action {
			color: var(--color-interactive);

			:global(svg) {
				width: 18px;
				height: 18px;
			}
		}

		&__file-text {
			display: flex;
			flex: 1;
			flex-direction: column;
			min-width: 0;
		}

		&__file-name {
			overflow: hidden;
			color: var(--color-heading);
			font-weight: 600;
			text-overflow: ellipsis;
			white-space: nowrap;
		}

		&__file-size {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
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

		// The box is two rows, as in Intercom's messenger: the words above, the paperclip, picked files and
		// Send below.
		&__field {
			display: flex;
			flex-direction: column;
			gap: var(--space-smaller);
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
				width: 100%;
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

		&__tools {
			display: flex;
			align-items: flex-end;
			gap: var(--space-small);
			// The paperclip lines up with the box's left edge rather than the text's.
			margin-left: calc(var(--space-small) * -1);
		}

		&__attach {
			display: flex;
			flex: 1;
			flex-wrap: wrap;
			align-items: center;
			gap: var(--space-smaller);
			min-width: 0;
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
