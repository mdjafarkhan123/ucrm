<script lang="ts">
	import { useQueryClient } from '@tanstack/svelte-query';
	import Button from '$lib/components/ui/Button.svelte';
	import Textarea from '$lib/components/ui/Textarea.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import ConversationAttachments from '$lib/components/communications/ConversationAttachments.svelte';
	import SnippetPickerButton from '$lib/components/communications/SnippetPickerButton.svelte';
	import EmailTemplatePickerButton from '$lib/components/communications/EmailTemplatePickerButton.svelte';
	import ConfirmDialog from '$lib/components/ui/ConfirmDialog.svelte';
	import type { CommunicationEmailTemplateListItem } from '$lib/communications/email-templates';
	import {
		clientCommunicationHistoryKey,
		sendConversationReply,
		type OutboundAttachmentPayload,
		type PendingOutboundSend
	} from '$lib/communications/inbox';

	// One reply composer per open conversation -- the parent remounts this with {#key clientId} when the
	// selected conversation changes, so subject/body reset for free instead of needing an effect.
	//
	// `onPendingChange` hands the in-flight send up to the timeline, which draws it as a bubble the moment
	// Send is pressed. The composer still owns the attempt (the payload, the retry, the idempotency key);
	// the page only renders what it is told.
	let {
		clientId,
		defaultSubject,
		recipientLabel,
		onPendingChange
	}: {
		clientId: string;
		defaultSubject: string;
		recipientLabel: string;
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
			channel: 'email',
			subject: attempt.subject,
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
			const result = await sendConversationReply(
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
			toast.info('Email queued', 'Delivery is not enabled yet, so this reply has not been sent.');

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
		if (!subject.trim()) nextErrors.subject = 'Enter a subject.';
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
		attachmentsField?.reset();
		void deliver(attempt);
	}
</script>

<form class="conversation-composer" onsubmit={send}>
	<dl class="conversation-composer__meta">
		<div>
			<dt>To</dt>
			<dd>{recipientLabel}</dd>
		</div>
		<div>
			<dt>From</dt>
			<dd>Your eligible email identity</dd>
		</div>
	</dl>
	<Input
		id="conversation-composer-subject"
		label="Subject"
		required
		bind:value={subject}
		invalid={Boolean(fieldErrors.subject)}
		errorMessage={fieldErrors.subject}
		maxlength={998}
	/>
	<Textarea
		id="conversation-composer-body"
		label="Message"
		required
		bind:value={body}
		invalid={Boolean(fieldErrors.body)}
		errorMessage={fieldErrors.body}
		maxlength={20_000}
		rows={4}
	/>
	{#if formError}<p class="conversation-composer__error" role="alert">{formError}</p>{/if}
	<footer class="conversation-composer__footer">
		<EmailTemplatePickerButton disabled={sending} onApply={requestTemplate} />
		<SnippetPickerButton disabled={sending} onInsert={insertSnippet} />
		<ConversationAttachments
			bind:this={attachmentsField}
			disabled={sending}
			onUploadingChange={(value) => (uploading = value)}
		/>
		<Button variant="primary" type="submit" loading={sending} disabled={uploading}>Send</Button>
	</footer>
</form>

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
		display: flex;
		flex-direction: column;
		gap: var(--space-small);
		padding: var(--space-large);
		border-top: var(--border-base) solid var(--color-border);
		background: var(--color-surface);
	}
	.conversation-composer__meta {
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-large);
	}
	.conversation-composer__meta div {
		display: flex;
		align-items: baseline;
		gap: var(--space-smaller);
	}
	.conversation-composer__meta dt {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}
	.conversation-composer__meta dd {
		margin: 0;
		color: var(--color-text);
		font-size: var(--typography--fontSize-small);
		overflow-wrap: anywhere;
	}
	.conversation-composer__error {
		color: var(--color-critical);
		font-size: var(--typography--fontSize-small);
	}
	.conversation-composer__footer {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: var(--space-small);

		/* The paperclip and its chips sit left, matching GHL's toolbar row; Send pins to the end of the
		   row regardless of how many chips wrap in before it. */
		:global(.button) {
			margin-inline-start: auto;
		}
	}
</style>
