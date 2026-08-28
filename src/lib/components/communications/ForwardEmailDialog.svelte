<script lang="ts">
	import { useQueryClient } from '@tanstack/svelte-query';
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import Textarea from '$lib/components/ui/Textarea.svelte';
	import Checkbox from '$lib/components/ui/Checkbox.svelte';
	import Badge from '$lib/components/ui/Badge.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import { formatFileSize } from '$lib/collaboration/format';
	import {
		clientCommunicationHistoryKey,
		forwardInboundMessage,
		type InboundInboxMessage
	} from '$lib/communications/inbox';

	type FieldErrors = Record<string, string>;

	// Forward one inbound email to external recipients (Part 5C-ii). The attachment checklist reuses the
	// message's own already-imported inbound attachments -- a forward never uploads new files, and per
	// docs/contractor-email-contract.md § Recipients, forwarding, and portal access, Conversations stays the
	// authoritative attachment surface, so this dialog only ever selects among what the source message
	// already has available.
	let {
		clientId,
		message,
		onClose
	}: { clientId: string; message: InboundInboxMessage; onClose: () => void } = $props();

	const toast = getToastManager();
	const queryClient = useQueryClient();

	// The parent mounts one instance of this dialog per open (`{#if forwardTarget}`, matching
	// MessageDetailsDialog), so seeding straight from `message` here always reflects the message being
	// forwarded -- no reset-on-open effect needed.
	// svelte-ignore state_referenced_locally
	let recipientsInput = $state('');
	// svelte-ignore state_referenced_locally
	let subject = $state(`Fwd: ${message.subject}`);
	// svelte-ignore state_referenced_locally
	let body = $state(message.text_content);
	let selectedAttachmentIds = $state<string[]>([]);
	let sending = $state(false);
	let formError = $state('');
	let fieldErrors = $state<FieldErrors>({});

	const availableAttachments = $derived(
		message.attachments.filter((attachment) => attachment.status === 'available')
	);

	function parseRecipients(value: string): string[] {
		return [
			...new Set(
				value
					.split(/[,;\n]/)
					.map((entry) => entry.trim().toLowerCase())
					.filter((entry) => entry.length > 0)
			)
		];
	}

	function close() {
		onClose();
	}

	function toggleAttachment(attachmentId: string, checked: boolean) {
		selectedAttachmentIds = checked
			? [...selectedAttachmentIds, attachmentId]
			: selectedAttachmentIds.filter((id) => id !== attachmentId);
	}

	function validate(recipients: string[]) {
		const next: FieldErrors = {};
		if (recipients.length === 0) next.recipients = 'Enter at least one recipient.';
		else if (recipients.length > 10) next.recipients = 'Choose at most 10 recipients.';
		else if (recipients.some((email) => !email.includes('@')))
			next.recipients = 'Enter a valid email address for every recipient.';
		if (!subject.trim()) next.subject = 'Enter a subject.';
		if (!body.trim()) next.body = 'Enter a message.';
		fieldErrors = next;
		return Object.keys(next).length === 0;
	}

	async function send() {
		const recipients = parseRecipients(recipientsInput);
		if (!validate(recipients) || sending) return;
		sending = true;
		formError = '';
		try {
			await forwardInboundMessage(
				clientId,
				message.id,
				recipients,
				subject,
				body,
				selectedAttachmentIds
			);
			queryClient.invalidateQueries({ queryKey: ['communications', 'inbox'] });
			queryClient.invalidateQueries({ queryKey: clientCommunicationHistoryKey(clientId) });
			toast.info(
				'Forward queued',
				'Delivery is not enabled yet, so this forward has not been sent.'
			);
			close();
		} catch (error) {
			const withFields = error as Error & { fieldErrors?: FieldErrors };
			fieldErrors = withFields.fieldErrors ?? {};
			formError = withFields.message;
		} finally {
			sending = false;
		}
	}
</script>

<Dialog open title={`Forward: ${message.subject}`} size="default" onClose={close}>
	<form
		class="forward-email__form"
		onsubmit={(event) => {
			event.preventDefault();
			void send();
		}}
	>
		<Input
			id="forward-email-recipients"
			label="To"
			placeholder="colleague@example.com, another@example.com"
			required
			bind:value={recipientsInput}
			invalid={Boolean(fieldErrors.recipients)}
			errorMessage={fieldErrors.recipients ?? 'Separate multiple addresses with a comma.'}
		/>
		<Input
			id="forward-email-subject"
			label="Subject"
			required
			bind:value={subject}
			invalid={Boolean(fieldErrors.subject)}
			errorMessage={fieldErrors.subject}
			maxlength={998}
		/>
		<Textarea
			id="forward-email-body"
			label="Message"
			required
			bind:value={body}
			invalid={Boolean(fieldErrors.body)}
			errorMessage={fieldErrors.body}
			maxlength={20_000}
			rows={10}
		/>
		{#if availableAttachments.length > 0}
			<fieldset class="forward-email__attachments">
				<legend>Attachments</legend>
				{#each availableAttachments as attachment (attachment.id)}
					<Checkbox
						id={`forward-attachment-${attachment.id}`}
						label={attachment.file_name}
						description={formatFileSize(attachment.byte_size)}
						checked={selectedAttachmentIds.includes(attachment.id)}
						onchange={(checked) => toggleAttachment(attachment.id, checked)}
					/>
				{/each}
			</fieldset>
		{/if}
		{#if message.attachment_count > availableAttachments.length}
			<p class="forward-email__notice">
				<Badge status="warning" size="small">Some attachments are not available to forward</Badge>
			</p>
		{/if}
		{#if formError}<p class="forward-email__error" role="alert">{formError}</p>{/if}
		<footer class="forward-email__footer">
			<Button variant="secondary" onclick={close}>Cancel</Button>
			<Button variant="primary" type="submit" loading={sending}>Forward</Button>
		</footer>
	</form>
</Dialog>

<style lang="scss">
	.forward-email__form {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);
	}
	.forward-email__attachments {
		display: flex;
		flex-direction: column;
		gap: var(--space-small);
		margin: 0;
		padding: 0;
		border: 0;

		legend {
			padding: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			font-weight: 600;
		}
	}
	.forward-email__notice {
		margin: 0;
	}
	.forward-email__error {
		color: var(--color-critical);
		font-size: var(--typography--fontSize-small);
	}
	.forward-email__footer {
		display: flex;
		justify-content: flex-end;
		gap: var(--space-small);
		margin-top: var(--space-small);
	}
</style>
