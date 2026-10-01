<script lang="ts">
	import { createQuery } from '@tanstack/svelte-query';
	import { resolve } from '$app/paths';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import Banner from '$lib/components/ui/Banner.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import SegmentedControl from '$lib/components/ui/SegmentedControl.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import Textarea from '$lib/components/ui/Textarea.svelte';
	import QuoteEmailPreview from './QuoteEmailPreview.svelte';
	import { fetchQuote, quoteDetailKey } from '$lib/quotes/api';
	import {
		QUOTE_EXTERNAL_SEND_CHANNELS,
		QUOTE_SEND_NOTE_MAX,
		type QuoteExternalSendChannel,
		type QuoteSendChoice
	} from '$lib/quotes/send';

	// The review window a Draft quote passes through on its way to Awaiting response, following Jobber's
	// own prompt: email it, say it was already sent some other way, look at it first, or cancel. Nothing is
	// claimed about the customer until one of the first two really happens — the caller owns that write and
	// throws back whatever refused it, which is shown here while the quote stays a Draft.
	let {
		open,
		quoteId,
		onSend,
		onClose
	}: {
		open: boolean;
		quoteId: string;
		/** Performs the send. `expectedRevision` is the draft this window showed. */
		onSend: (choice: QuoteSendChoice, expectedRevision: number) => Promise<void>;
		onClose: () => void;
	} = $props();

	const uid = $props.id();

	// The dialog is the reveal: it mounts only once a card has been dropped, so this is when the quote
	// loads. A copy the Quote page already cached shows at once and is re-read behind it.
	const quoteQuery = createQuery(() => ({
		queryKey: quoteDetailKey(quoteId),
		queryFn: () => fetchQuote(quoteId)
	}));
	const detail = $derived(quoteQuery.data);

	const recipient = $derived(detail?.quote.client?.email ?? null);
	const clientName = $derived(
		detail?.quote.client?.company_name?.trim() ||
			detail?.quote.client?.display_name ||
			detail?.version?.client_display_name ||
			'this customer'
	);
	const organizationName = $derived(detail?.version?.organization_name ?? 'your business');
	const total = $derived.by(() => {
		const totalMinor = detail?.version?.total_minor;
		if (totalMinor === undefined) return null;
		return new Intl.NumberFormat('en-US', {
			style: 'currency',
			currency: detail?.version?.currency_code ?? detail?.quote.currency_code ?? 'USD'
		}).format(totalMinor / 100);
	});
	// Somebody else may have sent or archived it between the board's last read and this drop.
	const stillDraft = $derived(
		detail?.quote.status === 'draft' && detail.version?.status === 'draft'
	);

	const emailBlockedReason = $derived.by(() => {
		if (!detail) return null;
		if (!detail.can_send_email) return 'You do not have permission to email customers.';
		if (!recipient) return 'This customer has no email address yet.';
		return null;
	});

	type Method = QuoteSendChoice['method'];
	// Null until the person picks, so the window opens on email whenever email is possible and on the
	// other choice when it is not, without an effect having to correct it afterwards.
	let pickedMethod = $state<Method | null>(null);
	const method = $derived<Method>(pickedMethod ?? (emailBlockedReason ? 'external' : 'email'));
	const methodOptions = $derived([
		{
			value: 'email',
			label: 'Email it now',
			disabled: Boolean(emailBlockedReason),
			title: emailBlockedReason ?? undefined
		},
		{ value: 'external', label: 'I already sent it' }
	]);

	const channelOptions = QUOTE_EXTERNAL_SEND_CHANNELS.map((channel) => ({
		value: channel.value,
		label: channel.label
	}));
	let channel = $state('');
	let note = $state('');

	let sending = $state(false);
	let formError = $state('');
	let fieldErrors = $state<Record<string, string>>({});

	const ready = $derived(
		Boolean(detail?.can_send && stillDraft && detail.version) &&
			!quoteQuery.isFetching &&
			(method === 'email' ? !emailBlockedReason : channel !== '')
	);

	async function send() {
		if (sending || !ready || !detail?.version) return;
		sending = true;
		formError = '';
		fieldErrors = {};
		try {
			await onSend(
				method === 'email'
					? { method: 'email' }
					: {
							method: 'external',
							channel: channel as QuoteExternalSendChannel,
							note: note.trim() || null
						},
				detail.version.revision
			);
		} catch (thrown) {
			const failure = thrown as Error & { fieldErrors?: Record<string, string> };
			fieldErrors = failure.fieldErrors ?? {};
			formError =
				fieldErrors.form ??
				fieldErrors.send ??
				(fieldErrors.note || fieldErrors.channel
					? ''
					: failure.message || 'The quote could not be sent. It is still a draft.');
		} finally {
			sending = false;
		}
	}

	function close() {
		if (sending) return;
		onClose();
	}
</script>

<Dialog
	{open}
	title={detail ? `Send quote #${detail.quote.quote_number}` : 'Send quote'}
	onClose={close}
>
	<div class="send-quote">
		{#if quoteQuery.isPending}
			<LoadingSkeleton variant="heading" label="Loading quote" />
			<LoadingSkeleton variant="card" label="Loading quote" />
		{:else if quoteQuery.isError || !detail}
			<Banner type="error">This quote could not be loaded. Close this and try again.</Banner>
		{:else}
			<div class="send-quote__summary">
				<div class="send-quote__summary-text">
					<p class="send-quote__client">{clientName}</p>
					{#if detail.quote.title}<p class="send-quote__title">{detail.quote.title}</p>{/if}
				</div>
				{#if total}<p class="send-quote__total">{total}</p>{/if}
			</div>

			{#if !detail.can_send}
				<Banner type="warning">You do not have permission to send quotes.</Banner>
			{:else if !stillDraft}
				<Banner type="notice">
					This quote is no longer a draft, so there is nothing to send from here.
				</Banner>
			{:else}
				<SegmentedControl
					label="How is this quote reaching the customer?"
					value={method}
					options={methodOptions}
					fullWidth
					disabled={sending}
					onchange={(next) => (pickedMethod = next as Method)}
				/>

				{#if method === 'email'}
					<QuoteEmailPreview {recipient} {organizationName} />
				{:else}
					{#if emailBlockedReason}
						<p class="send-quote__hint">
							{emailBlockedReason}
							{#if !recipient && detail.can_send_email}
								Add one on the customer to email this quote from here.
							{/if}
						</p>
					{/if}
					<div class="send-quote__field">
						<label class="send-quote__label" for="{uid}-channel">How did you send it?</label>
						<Select
							id="{uid}-channel"
							bind:value={channel}
							options={channelOptions}
							placeholder="Choose one"
							required
							disabled={sending}
						/>
						{#if fieldErrors.channel}
							<p class="send-quote__error" role="alert">{fieldErrors.channel}</p>
						{/if}
					</div>
					<Textarea
						id="{uid}-note"
						label="Note (optional)"
						rows={3}
						maxlength={QUOTE_SEND_NOTE_MAX}
						bind:value={note}
						disabled={sending}
						invalid={Boolean(fieldErrors.note)}
						errorMessage={fieldErrors.note}
					/>
					<p class="send-quote__hint">
						Nothing is sent to the customer. Your name, the time, and this choice are saved in the
						quote's history.
					</p>
				{/if}
			{/if}

			{#if formError}<p class="send-quote__error" role="alert">{formError}</p>{/if}
		{/if}

		<footer class="send-quote__actions">
			<Button
				variant="tertiary"
				variation="subtle"
				href={resolve('/(app)/quotes/[id=uuid]', { id: quoteId })}
				disabled={sending}
			>
				View quote
			</Button>
			<div class="send-quote__actions-main">
				<Button variant="secondary" variation="subtle" disabled={sending} onclick={close}>
					Cancel
				</Button>
				<Button variant="primary" disabled={!ready} loading={sending} onclick={() => void send()}>
					{method === 'email' ? 'Send email' : 'Mark as sent'}
				</Button>
			</div>
		</footer>
	</div>
</Dialog>

<style lang="scss">
	.send-quote {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);

		&__summary {
			display: flex;
			align-items: flex-start;
			justify-content: space-between;
			gap: var(--space-base);
			padding: var(--space-small) var(--space-base);
			border-radius: var(--radius-base);
			background: var(--color-surface--background);
		}

		&__summary-text {
			min-width: 0;
		}

		&__client {
			margin: 0;
			color: var(--color-heading);
			font-weight: 600;
			overflow-wrap: anywhere;
		}

		&__title {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			overflow-wrap: anywhere;
		}

		&__total {
			flex: none;
			margin: 0;
			color: var(--color-heading);
			font-weight: 700;
			font-variant-numeric: tabular-nums;
		}

		&__field {
			display: flex;
			flex-direction: column;
			gap: var(--space-smaller);
		}

		&__label {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			font-weight: 600;
		}

		&__hint {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			line-height: var(--typography--lineHeight-large);
		}

		&__error {
			margin: 0;
			color: var(--color-critical);
			font-size: var(--typography--fontSize-small);
		}

		&__actions {
			display: flex;
			flex-wrap: wrap;
			align-items: center;
			justify-content: space-between;
			gap: var(--space-small);
		}

		&__actions-main {
			display: flex;
			gap: var(--space-small);
			margin-left: auto;
		}
	}
</style>
