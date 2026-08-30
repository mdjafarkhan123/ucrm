<script lang="ts">
	import { useQueryClient } from '@tanstack/svelte-query';
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import Textarea from '$lib/components/ui/Textarea.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import ConversationAttachments from '$lib/components/communications/ConversationAttachments.svelte';
	import { clientCommunicationHistoryKey } from '$lib/communications/inbox';
	import type { ClientDetail } from '$lib/clients/api';

	type FieldErrors = Record<string, string>;

	let { open, client, onClose }: { open: boolean; client: ClientDetail; onClose: () => void } =
		$props();

	const toast = getToastManager();
	const queryClient = useQueryClient();
	const emailMethods = $derived(client.contact_methods.filter((method) => method.kind === 'email'));
	const emailOptions = $derived(
		emailMethods.map((method) => ({ value: method.id, label: method.value }))
	);
	let contactMethodId = $state('');
	let subject = $state('');
	let body = $state('');
	let previewing = $state(false);
	let sending = $state(false);
	let uploading = $state(false);
	let previewOpen = $state(false);
	let formError = $state('');
	let fieldErrors = $state<FieldErrors>({});
	let attachmentsField = $state<ConversationAttachments>();

	const selectedRecipient = $derived(
		emailMethods.find((method) => method.id === contactMethodId)?.value ?? ''
	);

	function validate() {
		const next: FieldErrors = {};
		if (!contactMethodId) next.contact_method_id = 'Choose an email address for this customer.';
		if (!subject.trim()) next.subject = 'Enter a subject.';
		if (!body.trim()) next.body = 'Enter a message.';
		fieldErrors = next;
		return Object.keys(next).length === 0;
	}

	function reset() {
		contactMethodId =
			emailMethods.find((method) => method.is_primary)?.id ?? emailMethods[0]?.id ?? '';
		subject = '';
		body = '';
		previewOpen = false;
		formError = '';
		fieldErrors = {};
		attachmentsField?.reset();
	}

	function close() {
		reset();
		onClose();
	}

	async function showPreview() {
		if (!validate() || uploading) return;
		previewing = true;
		formError = '';
		try {
			// The selected address is a saved contact-method id, not an editable recipient. The final command
			// resolves it again under current authority before it can create an intent.
			await Promise.resolve();
			previewOpen = true;
		} finally {
			previewing = false;
		}
	}

	async function send() {
		if (!validate() || sending) return;
		sending = true;
		formError = '';
		try {
			const response = await fetch(`/api/clients/${client.id}/communications/email`, {
				method: 'POST',
				headers: { 'content-type': 'application/json' },
				body: JSON.stringify({
					contact_method_id: contactMethodId,
					subject,
					body,
					idempotency_key: crypto.randomUUID(),
					attachments: attachmentsField?.getAttachments() ?? []
				})
			});
			const result = (await response.json().catch(() => ({}))) as {
				error?: string;
				field_errors?: FieldErrors;
				intent?: { status: string };
			};
			if (!response.ok) {
				fieldErrors = result.field_errors ?? {};
				formError = result.error ?? 'The email could not be queued.';
				return;
			}
			// A queued email is a new message in that client's conversation, so the inbox is stale wherever
			// this dialog was opened from -- the client page as much as Conversations itself.
			queryClient.invalidateQueries({ queryKey: ['communications', 'inbox'] });
			// The client Communication tab (Part 5D) caches under its own key, which the inbox invalidation
			// above does not prefix-match.
			queryClient.invalidateQueries({ queryKey: clientCommunicationHistoryKey(client.id) });
			toast.success('Email sent');
			close();
		} catch {
			formError = 'The email could not be queued. Check your connection and try again.';
		} finally {
			sending = false;
		}
	}
</script>

<Dialog
	{open}
	title={previewOpen ? 'Preview email' : `Email ${client.display_name}`}
	size="default"
	onClose={close}
>
	{#if emailMethods.length === 0}
		<p class="manual-email__notice">
			This customer has no saved email address. Add one to send an operational email.
		</p>
		<footer class="manual-email__footer">
			<Button variant="secondary" onclick={close}>Close</Button>
		</footer>
	{:else}
		<!-- Both views stay mounted and toggle with `hidden` rather than `{#if}/{:else}`, so the attached
		     files inside ConversationAttachments survive switching to preview and back. -->
		<div class="manual-email__preview" hidden={!previewOpen}>
			<dl class="manual-email__details">
				<div>
					<dt>To</dt>
					<dd>{selectedRecipient}</dd>
				</div>
				<div>
					<dt>From</dt>
					<dd>Your eligible email identity</dd>
				</div>
				<div>
					<dt>Subject</dt>
					<dd>{subject}</dd>
				</div>
			</dl>
			<div class="manual-email__body">{body}</div>
			<p class="manual-email__notice">
				Sending checks the recipient and your sender identity again. Delivery is currently disabled,
				so queued email will not be sent.
			</p>
			{#if formError}<p class="manual-email__error" role="alert">{formError}</p>{/if}
			<footer class="manual-email__footer">
				<Button variant="secondary" onclick={() => (previewOpen = false)} disabled={sending}
					>Back</Button
				>
				<Button variant="primary" onclick={() => void send()} loading={sending}>Queue email</Button>
			</footer>
		</div>
		<form
			class="manual-email__form"
			hidden={previewOpen}
			onsubmit={(event) => {
				event.preventDefault();
				void showPreview();
			}}
		>
			<Select
				id="manual-email-recipient"
				ariaLabel="Recipient"
				placeholder="Select recipient email"
				options={emailOptions}
				bind:value={contactMethodId}
				onchange={() => (fieldErrors = { ...fieldErrors, contact_method_id: '' })}
			/>
			{#if fieldErrors.contact_method_id}<p class="manual-email__error" role="alert">
					{fieldErrors.contact_method_id}
				</p>{/if}
			<Input
				id="manual-email-subject"
				label="Subject"
				required
				bind:value={subject}
				invalid={Boolean(fieldErrors.subject)}
				errorMessage={fieldErrors.subject}
				maxlength={998}
			/>
			<Textarea
				id="manual-email-body"
				label="Message"
				required
				bind:value={body}
				invalid={Boolean(fieldErrors.body)}
				errorMessage={fieldErrors.body}
				maxlength={20_000}
				rows={8}
			/>
			{#if formError}<p class="manual-email__error" role="alert">{formError}</p>{/if}
			<footer class="manual-email__footer">
				<ConversationAttachments
					bind:this={attachmentsField}
					disabled={sending}
					onUploadingChange={(value) => (uploading = value)}
				/>
				<div class="manual-email__actions">
					<Button variant="secondary" onclick={close}>Cancel</Button>
					<Button variant="primary" type="submit" loading={previewing} disabled={uploading}
						>Preview email</Button
					>
				</div>
			</footer>
		</form>
	{/if}
</Dialog>

<style lang="scss">
	:global(.manual-email__form),
	:global(.manual-email__preview) {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);
	}
	/* The class-level `display: flex` above beats the `[hidden]` UA rule's specificity tie, so the
	   toggle needs its own override to actually hide the inactive view. */
	:global(.manual-email__form[hidden]),
	:global(.manual-email__preview[hidden]) {
		display: none;
	}
	:global(.manual-email__details) {
		display: flex;
		flex-direction: column;
		gap: var(--space-small);
	}
	:global(.manual-email__details div) {
		display: grid;
		grid-template-columns: 72px minmax(0, 1fr);
		gap: var(--space-small);
	}
	:global(.manual-email__details dt) {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}
	:global(.manual-email__details dd) {
		min-width: 0;
		color: var(--color-heading);
		font-weight: 600;
		overflow-wrap: anywhere;
	}
	:global(.manual-email__body) {
		min-height: 120px;
		padding: var(--space-base);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		color: var(--color-text);
		white-space: pre-wrap;
		overflow-wrap: anywhere;
	}
	:global(.manual-email__notice) {
		padding: var(--space-slim) var(--space-base);
		border-radius: var(--radius-base);
		color: var(--color-text--secondary);
		background: var(--color-surface--active);
		font-size: var(--typography--fontSize-small);
	}
	:global(.manual-email__error) {
		color: var(--color-critical);
		font-size: var(--typography--fontSize-small);
	}
	:global(.manual-email__footer) {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: var(--space-small);
		margin-top: var(--space-small);
	}
	/* The paperclip and its chips sit left, matching GHL's toolbar row; Cancel/Preview stay together at
	   the end of the row regardless of how many chips wrap in before them. */
	:global(.manual-email__actions) {
		display: flex;
		align-items: center;
		gap: var(--space-small);
		margin-inline-start: auto;
	}
</style>
