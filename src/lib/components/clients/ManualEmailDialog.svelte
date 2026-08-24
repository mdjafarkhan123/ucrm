<script lang="ts">
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import Textarea from '$lib/components/ui/Textarea.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import type { ClientDetail } from '$lib/clients/api';

	type FieldErrors = Record<string, string>;

	let { open, client, onClose }: { open: boolean; client: ClientDetail; onClose: () => void } =
		$props();

	const toast = getToastManager();
	const emailMethods = $derived(client.contact_methods.filter((method) => method.kind === 'email'));
	const emailOptions = $derived(
		emailMethods.map((method) => ({ value: method.id, label: method.value }))
	);
	let contactMethodId = $state('');
	let subject = $state('');
	let body = $state('');
	let previewing = $state(false);
	let sending = $state(false);
	let previewOpen = $state(false);
	let formError = $state('');
	let fieldErrors = $state<FieldErrors>({});

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
	}

	function close() {
		reset();
		onClose();
	}

	async function showPreview() {
		if (!validate()) return;
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
					idempotency_key: crypto.randomUUID()
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
			toast.info('Email queued', 'Delivery is not enabled yet, so this email has not been sent.');
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
	{#if previewOpen}
		<div class="manual-email__preview">
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
	{:else if emailMethods.length === 0}
		<p class="manual-email__notice">
			This customer has no saved email address. Add one to send an operational email.
		</p>
		<footer class="manual-email__footer">
			<Button variant="secondary" onclick={close}>Close</Button>
		</footer>
	{:else}
		<form
			class="manual-email__form"
			onsubmit={(event) => {
				event.preventDefault();
				void showPreview();
			}}
		>
			<Select
				id="manual-email-recipient"
				ariaLabel="Recipient"
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
				<Button variant="secondary" onclick={close}>Cancel</Button>
				<Button variant="primary" type="submit" loading={previewing}>Preview email</Button>
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
		justify-content: flex-end;
		gap: var(--space-small);
		margin-top: var(--space-small);
	}
</style>
