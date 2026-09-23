<script lang="ts">
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import Button from '$lib/components/ui/Button.svelte';
	import Popover from '$lib/components/ui/Popover.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import ComposerChannelMenu from '$lib/components/communications/ComposerChannelMenu.svelte';
	import ConversationAttachments from '$lib/components/communications/ConversationAttachments.svelte';
	import ConversationLibraryAttachments from '$lib/components/communications/ConversationLibraryAttachments.svelte';
	import SnippetPickerButton from '$lib/components/communications/SnippetPickerButton.svelte';
	import EmailTemplatePickerButton from '$lib/components/communications/EmailTemplatePickerButton.svelte';
	import ConfirmDialog from '$lib/components/ui/ConfirmDialog.svelte';
	import type { CommunicationEmailTemplateListItem } from '$lib/communications/email-templates';
	import { tick } from 'svelte';
	import { Dialog as DialogPrimitive } from 'bits-ui';
	import { browser } from '$app/environment';
	import sendIcon from '@tabler/icons/outline/send-2.svg?raw';
	import minusIcon from '@tabler/icons/outline/minus.svg?raw';
	import maximizeIcon from '@tabler/icons/outline/arrows-maximize.svg?raw';
	import minimizeIcon from '@tabler/icons/outline/arrows-minimize.svg?raw';
	import chevronDownIcon from '@tabler/icons/outline/chevron-down.svg?raw';
	import {
		clientCommunicationHistoryKey,
		conversationMessagingKey,
		estimateSmsReply,
		fetchConversationMessaging,
		sendConversationReply,
		sendConversationReplySms,
		sendWebsiteChatStaffMessage,
		type OutboundAttachmentPayload,
		type PendingOutboundSend,
		type SmsReplyEstimate
	} from '$lib/communications/inbox';
	import type { FileListItem } from '$lib/files/api';

	type LibraryFile = Pick<FileListItem, 'id' | 'display_name' | 'mime_type' | 'size_bytes'>;

	// One reply composer for every channel -- email, SMS, and website chat share the same collapsed pill,
	// expand/minimize header, and footer toolbar. Only the fields a channel actually needs (subject,
	// attachments, the SMS cost estimate) render inside it. The parent remounts this with
	// {#key `${group.key}:${activeChannel}`} whenever the conversation OR its channel changes, so every
	// field resets for free instead of needing an effect.
	//
	// `onPendingChange` hands the in-flight send up to the timeline, which draws it as a bubble the moment
	// Send is pressed. The composer still owns the attempt (the payload, the retry, the idempotency key);
	// the page only renders what it is told.
	let {
		clientId,
		channel,
		sessionId = null,
		defaultSubject = '',
		recipientLabel = '',
		channels,
		onChannelChange,
		expanded = $bindable(false),
		onPendingChange
	}: {
		clientId: string | null;
		channel: 'email' | 'sms' | 'website_chat';
		sessionId?: string | null;
		defaultSubject?: string;
		recipientLabel?: string;
		channels: Array<'email' | 'sms' | 'website_chat'>;
		onChannelChange: (channel: 'email' | 'sms' | 'website_chat') => void;
		expanded?: boolean;
		onPendingChange?: (pending: PendingOutboundSend | null) => void;
	} = $props();

	const queryClient = useQueryClient();
	const toast = getToastManager();

	// Seeding once is the point: {#key `${group.key}:${activeChannel}`} remounts this component when the
	// conversation or channel changes, so the initial value is always the right one.
	// svelte-ignore state_referenced_locally
	let subject = $state(defaultSubject);
	let body = $state('');
	let sending = $state(false);
	let uploading = $state(false);
	let formError = $state('');
	let fieldErrors = $state<Record<string, string>>({});
	let attachmentsField = $state<ConversationAttachments>();
	let libraryFiles = $state<LibraryFile[]>([]);
	let pendingTemplate = $state<CommunicationEmailTemplateListItem | null>(null);
	let estimate = $state<SmsReplyEstimate | null>(null);
	let estimating = $state(false);
	// Resolved from the sender alone (Stage 6D-2), independent of the cost estimate above, so the attach
	// button's visibility doesn't wait on the user typing anything.
	let mmsEligible = $state(false);
	let bodyEl = $state<HTMLTextAreaElement | null>(null);

	// Texts go to the customer's primary number. When staff have stopped texts to it, or the customer replied
	// STOP, say so here and hold the Send button -- the server refuses the send either way. Shares its cache
	// with the Contact tab, so it is usually already there.
	const messaging = createQuery(() => ({
		queryKey: conversationMessagingKey(clientId as string),
		queryFn: () => fetchConversationMessaging(clientId as string),
		enabled: channel === 'sms' && Boolean(clientId),
		staleTime: 30_000
	}));
	const smsStopped = $derived.by(() => {
		if (channel !== 'sms') return false;
		const phones = messaging.data?.phones ?? [];
		return (phones.find((phone) => phone.is_primary) ?? phones[0])?.state === 'opted_out';
	});

	// The composer's live impact line (blueprint: "live characters, estimated segments and estimated
	// retail cost"), plus MMS eligibility for the attach-photo button. Debounced so every keystroke does not
	// fire a request; a token guards against a slower, stale response landing after a faster, newer one
	// already applied. Still fires on an empty draft (just less often -- only on mount or after clearing the
	// box) so eligibility resolves before the user has typed anything.
	let estimateToken = 0;
	$effect(() => {
		if (channel !== 'sms') {
			estimate = null;
			estimating = false;
			mmsEligible = false;
			return;
		}
		const text = body.trim();
		const token = ++estimateToken;
		estimating = Boolean(text);
		const handle = setTimeout(async () => {
			try {
				const result = await estimateSmsReply(clientId as string, text);
				if (token !== estimateToken) return;
				mmsEligible = result.mms_eligible;
				estimate = text ? result : null;
			} catch {
				if (token === estimateToken) estimate = null;
			} finally {
				if (token === estimateToken) estimating = false;
			}
		}, 400);
		return () => clearTimeout(handle);
	});

	function formatEstimateCost(ready: Extract<SmsReplyEstimate, { ready: true }>) {
		return (ready.cost_minor / 100).toLocaleString(undefined, {
			style: 'currency',
			currency: ready.currency
		});
	}

	// Chat has a real element ref and inserts at the caret, restoring focus there. Email/SMS appends --
	// the text stays editable either way, which is the contract's actual requirement.
	function insertSnippet(text: string) {
		if (channel !== 'website_chat' || !bodyEl) {
			body = body.trim().length > 0 ? `${body}\n${text}` : text;
			return;
		}
		const el = bodyEl;
		const start = el.selectionStart ?? body.length;
		const end = el.selectionEnd ?? body.length;
		body = body.slice(0, start) + text + body.slice(end);
		const caret = start + text.length;
		requestAnimationFrame(() => {
			el.focus();
			el.setSelectionRange(caret, caret);
		});
	}

	// A template seeds the whole draft, so it replaces subject and body rather than appending. If the user
	// has already started writing, confirm first -- otherwise apply straight away.
	const draftHasContent = $derived(
		body.trim().length > 0 || subject.trim() !== defaultSubject.trim()
	);

	function requestTemplate(template: CommunicationEmailTemplateListItem) {
		if (draftHasContent) {
			pendingTemplate = template;
			return;
		}
		applyTemplate(template);
	}

	function applyTemplate(template: CommunicationEmailTemplateListItem) {
		subject = template.subject;
		body = template.body;
		fieldErrors = {};
		formError = '';
		pendingTemplate = null;
	}

	// One attempt = one payload + one idempotency key, held so Retry replays exactly the same send rather
	// than minting a second one the endpoint would treat as a new message. Chat attempts only ever use
	// `body`; `subject` and `attachments` stay empty for that channel.
	type Attempt = {
		id: string;
		subject: string;
		body: string;
		attachments: OutboundAttachmentPayload[];
		libraryFileIds: string[];
	};

	function publish(
		state: 'sending' | 'sent' | 'failed',
		attempt: Attempt,
		extra: Partial<PendingOutboundSend> = {}
	) {
		onPendingChange?.({
			id: attempt.id,
			channel,
			subject: channel === 'email' ? attempt.subject : null,
			body: attempt.body,
			created_at: new Date().toISOString(),
			state,
			status: null,
			error: '',
			retry: () => void deliver(attempt),
			...extra
		});
	}

	async function deliver(attempt: Attempt) {
		sending = true;
		publish('sending', attempt);
		try {
			if (channel === 'website_chat') {
				await sendWebsiteChatStaffMessage(sessionId as string, attempt.body, attempt.id);
				// The mark clears here, on acceptance, rather than after the re-read below -- the server has the
				// message, which is the fact the user is waiting on. Chat has no delivery status of its own, so an
				// accepted message simply reads as an ordinary sent bubble from this point.
				publish('sent', attempt);
			} else {
				const result =
					channel === 'sms'
						? await sendConversationReplySms(
								clientId as string,
								attempt.body,
								attempt.attachments,
								attempt.id,
								attempt.libraryFileIds
							)
						: await sendConversationReply(
								clientId as string,
								attempt.subject,
								attempt.body,
								attempt.attachments,
								attempt.id,
								null,
								attempt.libraryFileIds
							);
				// The mark flips here, on acceptance, rather than after the re-read below. The server has taken
				// the message and told us what it did with it, which is the fact the user is waiting on -- making
				// them watch a full inbox re-read first added seconds of "Sending…" to a message already sent.
				publish('sent', attempt, { status: result.intent.status });
				toast.success(channel === 'sms' ? 'Text sent' : 'Email sent');
			}

			// The re-read still has to happen, but it now runs behind an already-confirmed bubble. Awaiting it
			// before dropping the bubble is what keeps the swap seamless: the real row is in the cache before
			// the bubble goes, so nothing blinks.
			//
			// The client Communication tab (Part 5D) caches under its own key, which the inbox invalidation
			// does not prefix-match -- without the second call a reply sent here would leave that tab showing
			// a stale page until something else happened to invalidate it.
			await Promise.all([
				queryClient.invalidateQueries({ queryKey: ['communications', 'inbox'] }),
				clientId
					? queryClient.invalidateQueries({ queryKey: clientCommunicationHistoryKey(clientId) })
					: Promise.resolve()
			]);
			onPendingChange?.(null);
		} catch (error) {
			if (channel === 'website_chat') {
				publish('failed', attempt, { error: (error as Error).message });
			} else {
				const withFields = error as Error & { fieldErrors?: Record<string, string> };
				const rejectedFields = withFields.fieldErrors ?? {};
				// A validation rejection cannot succeed on replay, so there is nothing to retry: the draft goes
				// back into the composer where it can actually be corrected. Everything else -- offline, a
				// dropped connection, a server fault -- stays on the bubble as a retryable failure.
				if (Object.keys(rejectedFields).length > 0) {
					subject = attempt.subject;
					body = attempt.body;
					fieldErrors = rejectedFields;
					formError = withFields.message;
					attachmentsField?.reset();
					libraryFiles = [];
					onPendingChange?.(null);
				} else {
					publish('failed', attempt, { error: withFields.message });
				}
			}
		} finally {
			sending = false;
		}
	}

	function submit(event?: SubmitEvent) {
		event?.preventDefault();
		if (sending || uploading || smsStopped) return;

		if (channel === 'website_chat') {
			const text = body.trim();
			if (!text) return;
			body = '';
			bodyEl?.focus();
			void deliver({
				id: crypto.randomUUID(),
				subject: '',
				body: text,
				attachments: [],
				libraryFileIds: []
			});
			return;
		}

		const nextErrors: Record<string, string> = {};
		if (channel === 'email' && !subject.trim()) nextErrors.subject = 'Enter a subject.';
		if (!body.trim()) nextErrors.body = 'Enter a message.';
		fieldErrors = nextErrors;
		if (Object.keys(nextErrors).length > 0) return;

		formError = '';
		const attempt: Attempt = {
			id: crypto.randomUUID(),
			subject,
			body,
			attachments: attachmentsField?.getAttachments() ?? [],
			libraryFileIds: libraryFiles.map((file) => file.id)
		};
		// Cleared up front, the way a messenger does: the message is now represented by its bubble in the
		// timeline, so leaving a copy in the box would read as if nothing had been sent.
		body = '';
		estimate = null;
		attachmentsField?.reset();
		libraryFiles = [];
		void deliver(attempt);
	}

	// "Send Later": email only -- see the migration note on enqueue_conversation_reply_email for why SMS is
	// excluded (its consent/quiet-hours/balance gates are all checked once, at enqueue time). This bypasses
	// the deliver()/onPendingChange bubble entirely: that machinery means "this is going out right now, here
	// is a live mark for it," which is the wrong story for something that will not go out for hours.
	let sendLaterOpen = $state(false);
	let sendLaterAnchor = $state<HTMLButtonElement | null>(null);
	let scheduledAtInput = $state('');
	let scheduling = $state(false);

	// A minute of slack so the round trip through the datetime-local input (minute precision) never lands
	// exactly on "now" and trips the server's strictly-future check.
	function earliestScheduleValue() {
		const min = new Date(Date.now() + 60_000);
		min.setSeconds(0, 0);
		return new Date(min.getTime() - min.getTimezoneOffset() * 60_000).toISOString().slice(0, 16);
	}

	function openSendLater() {
		if (!scheduledAtInput) scheduledAtInput = earliestScheduleValue();
		sendLaterOpen = true;
	}

	async function scheduleSend() {
		const when = new Date(scheduledAtInput);
		if (!scheduledAtInput || Number.isNaN(when.getTime()) || when.getTime() <= Date.now()) {
			formError = 'Choose a send time in the future.';
			return;
		}
		const nextErrors: Record<string, string> = {};
		if (!subject.trim()) nextErrors.subject = 'Enter a subject.';
		if (!body.trim()) nextErrors.body = 'Enter a message.';
		fieldErrors = nextErrors;
		if (Object.keys(nextErrors).length > 0) return;

		scheduling = true;
		formError = '';
		try {
			await sendConversationReply(
				clientId as string,
				subject,
				body,
				attachmentsField?.getAttachments() ?? [],
				crypto.randomUUID(),
				when.toISOString(),
				libraryFiles.map((file) => file.id)
			);
			await Promise.all([
				queryClient.invalidateQueries({ queryKey: ['communications', 'inbox'] }),
				clientId
					? queryClient.invalidateQueries({ queryKey: clientCommunicationHistoryKey(clientId) })
					: Promise.resolve()
			]);
			toast.success('Email scheduled');
			body = '';
			attachmentsField?.reset();
			libraryFiles = [];
			scheduledAtInput = '';
			sendLaterOpen = false;
		} catch (error) {
			const withFields = error as Error & { fieldErrors?: Record<string, string> };
			if (withFields.fieldErrors && Object.keys(withFields.fieldErrors).length > 0) {
				fieldErrors = withFields.fieldErrors;
			}
			formError = withFields.message;
		} finally {
			scheduling = false;
		}
	}

	// Ctrl/Cmd+Enter sends on every channel, the way Gmail, Front and Help Scout do -- a modifier chord, so
	// it never fires by accident while typing. Chat also sends on plain Enter (Shift+Enter for a newline),
	// matching the visitor's own widget; email/SMS keep plain Enter as a newline. Enter that only confirms an
	// IME composition (Japanese, Chinese, Korean input) is not a send.
	const sendChord =
		browser && /Mac|iPhone|iPad/.test(navigator.platform) ? '\u2318 Enter' : 'Ctrl+Enter';

	function handleKeydown(event: KeyboardEvent) {
		if (event.key !== 'Enter' || event.isComposing) return;
		const chord = event.ctrlKey || event.metaKey;
		if (!chord && (channel !== 'website_chat' || event.shiftKey)) return;
		event.preventDefault();
		submit();
	}

	// Full-screen is a display mode of the already-expanded draft, not a separate composer -- the same
	// subject/body state keeps typing when it pops out or back in.
	let popped = $state(false);

	let collapsedInputEl = $state<HTMLButtonElement | null>(null);

	// The button that was just used is removed from the page when the composer changes shape, which would
	// drop keyboard focus to the top of the document -- so focus is handed to whatever now stands in its place.
	function collapse() {
		expanded = false;
		popped = false;
		void tick().then(() => collapsedInputEl?.focus());
	}

	function expand() {
		expanded = true;
		requestAnimationFrame(() => bodyEl?.focus());
	}

	function setPopped(next: boolean) {
		popped = next;
		// Entering full screen is focused by the dialog's own open handler below, once its content exists.
		if (!next) void tick().then(() => bodyEl?.focus());
	}
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
{#snippet sendButton()}
	<button
		type="submit"
		class="conversation-composer__send"
		aria-label="Send"
		title={channel === 'website_chat' ? 'Send' : `Send (${sendChord})`}
		aria-keyshortcuts={channel === 'website_chat' ? undefined : 'Control+Enter Meta+Enter'}
		aria-busy={sending}
		disabled={sending || uploading || smsStopped}
	>
		{#if sending}
			<span class="conversation-composer__send-spinner" aria-hidden="true"></span>
		{:else}
			{@html sendIcon}
		{/if}
	</button>
{/snippet}

{#snippet composerForm()}
	<form
		id="conversation-composer-expanded"
		class="conversation-composer__form"
		class:conversation-composer__form--popped={popped}
		onsubmit={submit}
	>
		<header class="conversation-composer__header">
			<button
				type="button"
				class="conversation-composer__collapse"
				aria-label="Minimize composer"
				title="Minimize composer"
				onclick={collapse}
			>
				{@html minusIcon}
			</button>
			<button
				type="button"
				class="conversation-composer__collapse"
				aria-label={popped ? 'Exit full screen' : 'Expand to full screen'}
				title={popped ? 'Exit full screen' : 'Expand to full screen'}
				onclick={() => setPopped(!popped)}
			>
				{@html popped ? minimizeIcon : maximizeIcon}
			</button>
		</header>
		{#if channel !== 'website_chat'}
			<dl class="conversation-composer__meta">
				<div>
					<dt>From</dt>
					<dd>
						{#if channel === 'sms'}
							{estimate?.ready ? estimate.sender_phone : 'Organization default SMS number'}
						{:else}
							Your eligible email identity
						{/if}
					</dd>
				</div>
				<div>
					<dt>To</dt>
					<dd>{recipientLabel}</dd>
				</div>
			</dl>
		{/if}
		{#if channel === 'email'}
			<div
				class="conversation-composer__subject"
				class:conversation-composer__subject--invalid={Boolean(fieldErrors.subject)}
			>
				<label for="conversation-composer-subject">Subject</label>
				<input
					id="conversation-composer-subject"
					bind:value={subject}
					maxlength={998}
					aria-required="true"
					aria-invalid={Boolean(fieldErrors.subject)}
					aria-describedby={fieldErrors.subject ? 'conversation-composer-subject-error' : undefined}
					onkeydown={handleKeydown}
				/>
			</div>
			{#if fieldErrors.subject}<p
					id="conversation-composer-subject-error"
					class="conversation-composer__field-error"
					role="alert"
				>
					{fieldErrors.subject}
				</p>{/if}
		{/if}
		<div
			class="conversation-composer__editor"
			class:conversation-composer__editor--invalid={Boolean(fieldErrors.body)}
		>
			<label class="sr-only" for="conversation-composer-body">Message</label>
			<textarea
				bind:this={bodyEl}
				id="conversation-composer-body"
				bind:value={body}
				placeholder={channel === 'website_chat' ? 'Write a reply…' : 'Type a message'}
				maxlength={channel === 'sms' ? 1600 : channel === 'website_chat' ? 5000 : 20_000}
				rows={channel === 'website_chat' ? 3 : 5}
				aria-required="true"
				aria-invalid={Boolean(fieldErrors.body)}
				aria-describedby={fieldErrors.body ? 'conversation-composer-body-error' : undefined}
				aria-keyshortcuts={channel === 'website_chat' ? 'Enter' : 'Control+Enter Meta+Enter'}
				onkeydown={handleKeydown}></textarea>
		</div>
		{#if fieldErrors.body}<p
				id="conversation-composer-body-error"
				class="conversation-composer__field-error"
				role="alert"
			>
				{fieldErrors.body}
			</p>{/if}
		{#if smsStopped}
			<p class="conversation-composer__error" role="alert">
				Texts to this customer are stopped. See Messaging in the Contact tab.
			</p>
		{/if}
		{#if channel === 'sms'}
			<p class="conversation-composer__impact">
				{#if estimating}
					Estimating…
				{:else if estimate?.ready}
					{body.length} character{body.length === 1 ? '' : 's'} · {estimate.segment_count} segment{estimate.segment_count ===
					1
						? ''
						: 's'} · {formatEstimateCost(estimate)} estimated
				{:else if estimate && !estimate.ready}
					{estimate.reason}
				{:else}
					{body.length} character{body.length === 1 ? '' : 's'}
				{/if}
			</p>
			<p class="conversation-composer__impact">
				{mmsEligible
					? 'A picture attaches as a real picture text. Other files send as a secure link in the text.'
					: 'A file attaches as a secure link in the text for this number.'}
			</p>
		{/if}
		{#if formError}<p class="conversation-composer__error" role="alert">{formError}</p>{/if}
		<footer class="conversation-composer__footer">
			<div class="conversation-composer__tools">
				<ComposerChannelMenu {channel} {channels} onSelect={onChannelChange} />
				{#if channel === 'email'}
					<EmailTemplatePickerButton disabled={sending} onApply={requestTemplate} />
				{/if}
				<SnippetPickerButton disabled={sending} onInsert={insertSnippet} />
				{#if channel === 'email'}
					<ConversationAttachments
						bind:this={attachmentsField}
						disabled={sending}
						onUploadingChange={(value) => (uploading = value)}
					/>
					<ConversationLibraryAttachments
						files={libraryFiles}
						onChange={(next) => (libraryFiles = next)}
						disabled={sending}
						{clientId}
						clientLabel="This client's files"
					/>
				{:else if channel === 'sms'}
					<ConversationAttachments
						bind:this={attachmentsField}
						variant="sms"
						disabled={sending}
						onUploadingChange={(value) => (uploading = value)}
					/>
					<ConversationLibraryAttachments
						files={libraryFiles}
						onChange={(next) => (libraryFiles = next)}
						variant="sms"
						disabled={sending}
						{clientId}
						clientLabel="This client's files"
					/>
				{/if}
			</div>
			{#if channel === 'email'}
				<div class="conversation-composer__send-group">
					{@render sendButton()}
					<button
						type="button"
						bind:this={sendLaterAnchor}
						class="conversation-composer__send-later-trigger"
						aria-label="More send options"
						title="More send options"
						disabled={sending || uploading}
						onclick={openSendLater}
					>
						{@html chevronDownIcon}
					</button>
				</div>
				<Popover
					open={sendLaterOpen}
					anchor={sendLaterAnchor}
					title="Send later"
					onClose={() => (sendLaterOpen = false)}
				>
					<div class="conversation-composer__send-later">
						<label for="conversation-composer-schedule">Send at</label>
						<input
							id="conversation-composer-schedule"
							type="datetime-local"
							bind:value={scheduledAtInput}
							min={earliestScheduleValue()}
						/>
						<Button type="button" variant="primary" loading={scheduling} onclick={scheduleSend}
							>Schedule send</Button
						>
					</div>
				</Popover>
			{:else}
				{@render sendButton()}
			{/if}
		</footer>
	</form>
{/snippet}

<div class="conversation-composer" class:conversation-composer--expanded={expanded && !popped}>
	{#if !expanded}
		<div class="conversation-composer__collapsed">
			<ComposerChannelMenu {channel} {channels} onSelect={onChannelChange} />
			<button
				type="button"
				bind:this={collapsedInputEl}
				class="conversation-composer__collapsed-input"
				aria-expanded="false"
				aria-controls="conversation-composer-expanded"
				onclick={expand}>Type a message</button
			>
			<button
				class="conversation-composer__collapsed-send"
				type="button"
				aria-label="Send"
				disabled
			>
				{@html sendIcon}
			</button>
		</div>
	{:else if popped}
		<DialogPrimitive.Root
			open
			onOpenChange={(next) => {
				if (!next) setPopped(false);
			}}
		>
			<DialogPrimitive.Portal>
				<DialogPrimitive.Overlay class="conversation-composer__popout-overlay" />
				<DialogPrimitive.Content
					class="conversation-composer__popout-content"
					onOpenAutoFocus={(event) => {
						event.preventDefault();
						bodyEl?.focus();
					}}
					onCloseAutoFocus={(event) => event.preventDefault()}
					aria-label={(channel === 'email'
						? 'Email'
						: channel === 'sms'
							? 'Text message'
							: 'Chat message') + ' composer, full screen'}
				>
					{@render composerForm()}
				</DialogPrimitive.Content>
			</DialogPrimitive.Portal>
		</DialogPrimitive.Root>
	{:else}
		{@render composerForm()}
	{/if}
</div>
<!-- eslint-enable svelte/no-at-html-tags -->

{#if pendingTemplate}
	{@const template = pendingTemplate}
	<ConfirmDialog
		open
		title="Replace your draft?"
		confirmLabel="Replace"
		cancelLabel="Keep editing"
		onConfirm={() => applyTemplate(template)}
		onClose={() => (pendingTemplate = null)}
	>
		Applying <strong>{template.name}</strong> replaces the subject and message you've started.
	</ConfirmDialog>
{/if}

<style lang="scss">
	.conversation-composer {
		border-top: var(--border-base) solid var(--color-border);
		background: var(--color-surface);
	}

	.conversation-composer--expanded {
		padding: var(--space-small);
	}

	.conversation-composer__collapsed {
		display: flex;
		width: 100%;
		align-items: center;
		gap: var(--space-smaller);
		padding: var(--space-small);
		background: var(--color-surface);
	}

	.conversation-composer__collapsed-input {
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

	.conversation-composer__collapsed-input:focus-visible,
	.conversation-composer__collapse:focus-visible,
	.conversation-composer__collapsed-send:focus-visible {
		outline: none;
		box-shadow: var(--shadow-focus);
	}

	.conversation-composer__collapsed-send {
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

	.conversation-composer__collapsed-send :global(svg) {
		width: 18px;
		height: 18px;
	}

	.conversation-composer__form {
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

	.conversation-composer__form--popped {
		flex: 1;
		min-width: 0;
		height: 100%;

		.conversation-composer__editor {
			flex: 1;
			min-height: 0;

			textarea {
				height: 100%;
				min-height: 100%;
				resize: none;
			}
		}
	}

	:global(.conversation-composer__popout-overlay) {
		position: fixed;
		inset: 0;
		z-index: var(--elevation-modal);
		background: var(--color-overlay);
	}

	:global(.conversation-composer__popout-content) {
		position: fixed;
		inset: var(--space-large);
		z-index: var(--elevation-modal);
		display: flex;
		outline: none;
	}

	.conversation-composer__header {
		display: flex;
		align-items: center;
		justify-content: flex-end;
		gap: var(--space-smallest);
		padding: var(--space-smaller) var(--space-small);
		border-bottom: var(--border-base) solid var(--color-border);
		background: var(--color-surface--background--subtle);
	}

	.conversation-composer__collapse {
		display: inline-flex;
		width: 32px;
		height: 32px;
		flex: 0 0 auto;
		align-items: center;
		justify-content: center;
		padding: 0;
		border: 0;
		border-radius: var(--radius-base);
		color: var(--color-icon--secondary);
		background: transparent;
		cursor: pointer;
	}

	.conversation-composer__collapse:hover {
		color: var(--color-heading);
		background: var(--color-surface--hover);
	}

	.conversation-composer__collapse :global(svg) {
		width: 18px;
		height: 18px;
	}

	.conversation-composer__meta {
		display: flex;
		flex-direction: column;
		margin: 0;
	}

	.conversation-composer__meta div {
		display: flex;
		min-height: 36px;
		align-items: center;
		gap: var(--space-small);
		padding: var(--space-smaller) var(--space-small);
		border-bottom: var(--border-base) solid var(--color-border);
	}

	.conversation-composer__meta dt {
		width: 44px;
		flex: 0 0 auto;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}

	.conversation-composer__meta dd {
		margin: 0;
		color: var(--color-text);
		font-size: var(--typography--fontSize-small);
		font-weight: 500;
		overflow-wrap: anywhere;
	}

	.conversation-composer__subject {
		display: flex;
		min-height: 38px;
		align-items: center;
		gap: var(--space-small);
		padding: var(--space-smaller) var(--space-small);
		border-bottom: var(--border-base) solid var(--color-border);

		label {
			width: 44px;
			flex: 0 0 auto;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		input {
			min-width: 0;
			flex: 1;
			padding: 0;
			border: 0;
			outline: none;
			box-shadow: none;
			color: var(--color-heading);
			background: transparent;
			font: inherit;
			font-size: var(--typography--fontSize-base);
		}
	}

	.conversation-composer__subject--invalid {
		border-color: var(--color-critical);
	}

	.conversation-composer__editor {
		min-height: 116px;
		padding: var(--space-small);
		border-bottom: var(--border-base) solid var(--color-border);

		textarea {
			display: block;
			width: 100%;
			min-height: 100px;
			padding: 0;
			border: 0;
			outline: none;
			box-shadow: none;
			color: var(--color-text);
			background: transparent;
			font: inherit;
			font-size: var(--typography--fontSize-base);
			line-height: var(--typography--lineHeight-base);
			resize: vertical;

			&::placeholder {
				color: var(--color-text--secondary);
			}
		}
	}

	.conversation-composer__editor--invalid {
		box-shadow: inset 0 0 0 var(--border-base) var(--color-critical);
	}

	.conversation-composer__impact {
		margin: 0;
		padding: 0 var(--space-small);
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}

	.conversation-composer__editor + .conversation-composer__impact {
		padding-top: var(--space-small);
	}

	.conversation-composer__impact + .conversation-composer__impact {
		padding-top: var(--space-smaller);
	}

	.conversation-composer__field-error,
	.conversation-composer__error {
		margin: 0;
		padding: var(--space-smaller) var(--space-small) 0;
		color: var(--color-critical);
		font-size: var(--typography--fontSize-small);
	}

	.conversation-composer__footer {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-small);
		padding: var(--space-small);
	}

	.conversation-composer__tools {
		display: flex;
		min-width: 0;
		flex: 1;
		flex-wrap: wrap;
		align-items: center;
		gap: var(--space-smaller);
	}

	/* The compact composer's paper-plane button, live: the same 38x34 size, so the button doesn't change
	   shape when the composer opens. */
	.conversation-composer__send {
		display: inline-flex;
		width: 38px;
		height: 34px;
		flex: 0 0 auto;
		align-items: center;
		justify-content: center;
		padding: 0;
		border: 0;
		border-radius: var(--radius-small);
		color: var(--color-surface);
		background: var(--color-interactive);
		cursor: pointer;
		transition: background var(--timing-base) ease-out;

		&:hover:not(:disabled) {
			background: var(--color-interactive--hover);
		}

		&:disabled {
			cursor: not-allowed;
			opacity: 0.6;
		}

		&:focus-visible {
			outline: none;
			box-shadow: var(--shadow-focus);
		}

		:global(svg) {
			width: 18px;
			height: 18px;
		}
	}

	.conversation-composer__send-spinner {
		width: 16px;
		height: 16px;
		border: 2px solid currentColor;
		border-right-color: transparent;
		border-radius: var(--radius-circle);
		animation: spinning var(--timing-loading) linear infinite;
	}

	/* The paper plane and the chevron read as one split button: the chevron sits flush against Send with a
	   hairline seam, and the two outer corners each owns are rounded to match. */
	.conversation-composer__send-group {
		display: flex;
		flex: 0 0 auto;
		align-items: stretch;

		.conversation-composer__send {
			border-radius: var(--radius-small) 0 0 var(--radius-small);
		}
	}

	.conversation-composer__send-later-trigger {
		display: inline-flex;
		width: 28px;
		flex: 0 0 auto;
		align-items: center;
		justify-content: center;
		padding: 0;
		border: 0;
		border-left: var(--border-base) solid var(--color-overlay);
		border-radius: 0 var(--radius-small) var(--radius-small) 0;
		color: var(--color-surface);
		background: var(--color-interactive);
		cursor: pointer;

		&:hover:not(:disabled) {
			background: var(--color-interactive--hover);
		}

		&:disabled {
			cursor: not-allowed;
			opacity: 0.6;
		}

		&:focus-visible {
			outline: none;
			box-shadow: var(--shadow-focus);
		}

		:global(svg) {
			width: 16px;
			height: 16px;
		}
	}

	.conversation-composer__send-later {
		display: flex;
		flex-direction: column;
		gap: var(--space-small);
		min-width: 220px;

		label {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			font-weight: 600;
		}

		input {
			padding: var(--space-smaller) var(--space-small);
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-small);
			color: var(--color-text);
			background: var(--color-surface);
			font: inherit;
			font-size: var(--typography--fontSize-base);
		}
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
		.conversation-composer--expanded {
			padding: var(--space-smallest);
		}

		.conversation-composer__collapsed {
			padding: var(--space-smaller);
		}

		.conversation-composer__meta div,
		.conversation-composer__subject,
		.conversation-composer__editor,
		.conversation-composer__footer {
			padding-inline: var(--space-small);
		}
	}
</style>
