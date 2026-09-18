<script lang="ts">
	import { useQueryClient } from '@tanstack/svelte-query';
	import Button from '$lib/components/ui/Button.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import ComposerChannelMenu from '$lib/components/communications/ComposerChannelMenu.svelte';
	import ConversationAttachments from '$lib/components/communications/ConversationAttachments.svelte';
	import SnippetPickerButton from '$lib/components/communications/SnippetPickerButton.svelte';
	import EmailTemplatePickerButton from '$lib/components/communications/EmailTemplatePickerButton.svelte';
	import ConfirmDialog from '$lib/components/ui/ConfirmDialog.svelte';
	import type { CommunicationEmailTemplateListItem } from '$lib/communications/email-templates';
	import sendIcon from '@tabler/icons/outline/send-2.svg?raw';
	import minusIcon from '@tabler/icons/outline/minus.svg?raw';
	import {
		clientCommunicationHistoryKey,
		estimateSmsReply,
		sendConversationReply,
		sendConversationReplySms,
		type OutboundAttachmentPayload,
		type PendingOutboundSend,
		type SmsReplyEstimate
	} from '$lib/communications/inbox';

	// One reply composer per open conversation -- the parent remounts this with {#key `${group.key}:
	// ${activeChannel}`} whenever the conversation OR its channel changes, so subject/body/estimate reset
	// for free instead of needing an effect.
	//
	// `onPendingChange` hands the in-flight send up to the timeline, which draws it as a bubble the moment
	// Send is pressed. The composer still owns the attempt (the payload, the retry, the idempotency key);
	// the page only renders what it is told.
	let {
		clientId,
		channel,
		defaultSubject,
		recipientLabel,
		channels,
		onChannelChange,
		expanded = $bindable(false),
		onPendingChange
	}: {
		clientId: string;
		channel: 'email' | 'sms';
		defaultSubject: string;
		recipientLabel: string;
		channels: Array<'email' | 'sms' | 'website_chat'>;
		onChannelChange: (channel: 'email' | 'sms' | 'website_chat') => void;
		expanded?: boolean;
		onPendingChange?: (pending: PendingOutboundSend | null) => void;
	} = $props();

	const queryClient = useQueryClient();
	const toast = getToastManager();

	// Seeding once is the point: {#key clientId} remounts this component when the conversation changes,
	// so the initial value is always the right one.
	// svelte-ignore state_referenced_locally
	let subject = $state(defaultSubject);
	let body = $state('');
	let sending = $state(false);
	let uploading = $state(false);
	let formError = $state('');
	let fieldErrors = $state<Record<string, string>>({});
	let attachmentsField = $state<ConversationAttachments>();
	let pendingTemplate = $state<CommunicationEmailTemplateListItem | null>(null);
	let estimate = $state<SmsReplyEstimate | null>(null);
	let estimating = $state(false);
	// Resolved from the sender alone (Stage 6D-2), independent of the cost estimate above, so the attach
	// button's visibility doesn't wait on the user typing anything.
	let mmsEligible = $state(false);
	let bodyEl = $state<HTMLTextAreaElement | null>(null);

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
				const result = await estimateSmsReply(clientId, text);
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

	// No ref into the wrapped Textarea's own element, so this appends rather than inserting at a caret
	// position -- the text stays editable either way, which is the contract's actual requirement.
	function insertSnippet(text: string) {
		body = body.trim().length > 0 ? `${body}\n${text}` : text;
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
	// than minting a second one the endpoint would treat as a new message.
	type Attempt = {
		id: string;
		subject: string;
		body: string;
		attachments: OutboundAttachmentPayload[];
	};

	function publish(
		state: 'sending' | 'sent' | 'failed',
		attempt: Attempt,
		extra: Partial<PendingOutboundSend> = {}
	) {
		onPendingChange?.({
			id: attempt.id,
			channel,
			subject: channel === 'sms' ? null : attempt.subject,
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
			const result =
				channel === 'sms'
					? await sendConversationReplySms(clientId, attempt.body, attempt.attachments, attempt.id)
					: await sendConversationReply(
							clientId,
							attempt.subject,
							attempt.body,
							attempt.attachments,
							attempt.id
						);
			// The mark flips here, on acceptance, rather than after the re-read below. The server has taken
			// the message and told us what it did with it, which is the fact the user is waiting on -- making
			// them watch a full inbox re-read first added seconds of "Sending…" to a message already sent.
			publish('sent', attempt, { status: result.intent.status });
			toast.success(channel === 'sms' ? 'Text sent' : 'Email sent');

			// The re-read still has to happen, but it now runs behind an already-confirmed bubble. Awaiting it
			// before dropping the bubble is what keeps the swap seamless: the real row is in the cache before
			// the bubble goes, so nothing blinks.
			//
			// The client Communication tab (Part 5D) caches under its own key, which the inbox invalidation
			// does not prefix-match -- without the second call a reply sent here would leave that tab showing
			// a stale page until something else happened to invalidate it.
			await Promise.all([
				queryClient.invalidateQueries({ queryKey: ['communications', 'inbox'] }),
				queryClient.invalidateQueries({ queryKey: clientCommunicationHistoryKey(clientId) })
			]);
			onPendingChange?.(null);
		} catch (error) {
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
				onPendingChange?.(null);
			} else {
				publish('failed', attempt, { error: withFields.message });
			}
		} finally {
			sending = false;
		}
	}

	function send(event: SubmitEvent) {
		event.preventDefault();
		if (sending || uploading) return;
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
			attachments: attachmentsField?.getAttachments() ?? []
		};
		// Cleared up front, the way a messenger does: the message is now represented by its bubble in the
		// timeline, so leaving a copy in the box would read as if nothing had been sent.
		body = '';
		estimate = null;
		attachmentsField?.reset();
		void deliver(attempt);
	}

	function collapse() {
		expanded = false;
	}

	function expand() {
		expanded = true;
		requestAnimationFrame(() => bodyEl?.focus());
	}
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<div class="conversation-composer" class:conversation-composer--expanded={expanded}>
	{#if !expanded}
		<div class="conversation-composer__collapsed">
			<ComposerChannelMenu {channel} {channels} onSelect={onChannelChange} />
			<button
				type="button"
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
	{:else}
		<form id="conversation-composer-expanded" class="conversation-composer__form" onsubmit={send}>
			<header class="conversation-composer__header">
				<ComposerChannelMenu {channel} {channels} onSelect={onChannelChange} />
				<button
					type="button"
					class="conversation-composer__collapse"
					aria-label="Minimize composer"
					title="Minimize composer"
					onclick={collapse}
				>
					{@html minusIcon}
				</button>
			</header>
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
					/>
				</div>
				{#if fieldErrors.subject}<p class="conversation-composer__field-error" role="alert">
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
					placeholder="Type a message"
					maxlength={channel === 'sms' ? 1600 : 20_000}
					rows={5}
					aria-required="true"
					aria-invalid={Boolean(fieldErrors.body)}></textarea>
			</div>
			{#if fieldErrors.body}<p class="conversation-composer__field-error" role="alert">
					{fieldErrors.body}
				</p>{/if}
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
					{:else}
						<ConversationAttachments
							bind:this={attachmentsField}
							variant="sms"
							disabled={sending}
							onUploadingChange={(value) => (uploading = value)}
						/>
					{/if}
				</div>
				<Button variant="primary" type="submit" loading={sending} disabled={uploading}>Send</Button>
			</footer>
		</form>
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

	.conversation-composer__header {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-small);
		padding: var(--space-small);
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
