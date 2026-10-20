<script lang="ts">
	import MessageSheet from '$lib/components/ui/MessageSheet.svelte';
	import letterCaseIcon from '@tabler/icons/outline/letter-case.svg?raw';
	import messagesIcon from '@tabler/icons/outline/messages.svg?raw';
	import coinIcon from '@tabler/icons/outline/coin.svg?raw';
	import Select from '$lib/components/ui/Select.svelte';
	import { AUTOMATION_SMS_VARIABLES } from '$lib/automation/email-variables';
	import {
		estimateAutomationSms,
		fetchAutomationSmsSenders,
		type AutomationSmsEstimate,
		type AutomationSmsSender
	} from '$lib/settings/automation-authoring';

	// Stage 7: the authoring card for one "Send a text message" step. Mirrors EmailActionEditor's shape (plain
	// text, allow-listed variables inserted at the caret) minus a subject line, plus the live segment/cost
	// impact line docs/automation-behavior-contract.md's SMS customer action requires ("sees the rendered
	// preview, ... segment estimate and estimated retail cost").
	let {
		idPrefix,
		body,
		senderId = '',
		errorMessage = '',
		variables = AUTOMATION_SMS_VARIABLES,
		showSender = true,
		required = true,
		onBodyChange,
		onSenderIdChange
	}: {
		idPrefix: string;
		body: string;
		senderId?: string;
		errorMessage?: string;
		// The insertable values; a website inquiry passes its smaller, quote-free list.
		variables?: ReadonlyArray<{ token: string; label: string }>;
		// The inquiry reply picks its number the usual way and has no per-step sender pin.
		showSender?: boolean;
		required?: boolean;
		onBodyChange: (value: string) => void;
		onSenderIdChange?: (value: string) => void;
	} = $props();

	// The live impact line. Debounced so every keystroke does not fire a request; a token guards against a
	// slower, stale response landing after a faster, newer one already applied (mirrors ConversationComposer's
	// identical estimate effect).
	let estimate = $state<AutomationSmsEstimate | null>(null);
	let estimating = $state(false);
	let estimateToken = 0;
	$effect(() => {
		const text = body.trim();
		if (!text) {
			estimate = null;
			estimating = false;
			return;
		}
		const token = ++estimateToken;
		estimating = true;
		const handle = setTimeout(async () => {
			try {
				const result = await estimateAutomationSms(text);
				if (token === estimateToken) estimate = result;
			} catch {
				if (token === estimateToken) estimate = null;
			} finally {
				if (token === estimateToken) estimating = false;
			}
		}, 400);
		return () => clearTimeout(handle);
	});

	function formatEstimateCost(ready: Extract<AutomationSmsEstimate, { ready: true }>) {
		return (ready.cost_minor / 100).toLocaleString(undefined, {
			style: 'currency',
			currency: ready.currency
		});
	}

	// The optional step-level sender pin. Loaded once per card, not per keystroke; a card with no eligible
	// numbers yet just shows the default option, and the send effect still re-checks eligibility live.
	let senders = $state<AutomationSmsSender[] | null>(null);
	let sendersError = $state(false);
	$effect(() => {
		if (!showSender) return;
		let cancelled = false;
		fetchAutomationSmsSenders()
			.then((result) => {
				if (!cancelled) senders = result;
			})
			.catch(() => {
				if (!cancelled) sendersError = true;
			});
		return () => {
			cancelled = true;
		};
	});

	const senderOptions = $derived([
		{ value: '', label: 'Use the usual number (recommended)' },
		...(senders ?? []).map((sender) => ({
			value: sender.id,
			label: sender.display_name
				? `${sender.display_name} — ${sender.phone_number}`
				: sender.phone_number
		}))
	]);
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<div class="sms-editor">
	<MessageSheet
		{idPrefix}
		{body}
		bodyMaxlength={1000}
		bodyRows={5}
		{required}
		{variables}
		{errorMessage}
		hint={'Values in {{ }} are swapped for the real details when it sends.'}
		{onBodyChange}
	/>

	<!-- The cost meter: characters · segments · estimated cost, or the one reason it cannot estimate. -->
	{#if estimate && !estimate.ready && !estimating}
		<p class="sms-editor__hint" aria-live="polite">{estimate.reason}</p>
	{:else}
		<div class="sms-editor__meter" aria-live="polite">
			<span class="sms-editor__fact">
				<span class="sms-editor__fact-tile" aria-hidden="true">{@html letterCaseIcon}</span>
				<strong>{body.length}</strong>
				<span>character{body.length === 1 ? '' : 's'}</span>
			</span>
			{#if estimating}
				<span class="sms-editor__fact sms-editor__fact--quiet">Estimating…</span>
			{:else if estimate?.ready}
				<span class="sms-editor__fact">
					<span class="sms-editor__fact-tile" aria-hidden="true">{@html messagesIcon}</span>
					<strong>{estimate.segment_count}</strong>
					<span>segment{estimate.segment_count === 1 ? '' : 's'}</span>
				</span>
				<span class="sms-editor__fact">
					<span class="sms-editor__fact-tile" aria-hidden="true">{@html coinIcon}</span>
					<strong>{formatEstimateCost(estimate)}</strong>
					<span>estimated from {estimate.sender_phone}</span>
				</span>
			{/if}
		</div>
	{/if}

	{#if showSender}
		<div class="sms-editor__sender">
			<Select
				id={`${idPrefix}-sender`}
				label="Send from"
				value={senderId}
				options={senderOptions}
				disabled={sendersError}
				onchange={(value) => onSenderIdChange?.(value)}
			/>
			<p class="sms-editor__hint" class:sms-editor__hint--warning={sendersError}>
				{sendersError
					? 'The organization’s SMS numbers could not be loaded — the usual number will be used.'
					: 'Left as the usual number, a text continues whichever number this customer’s texts have been using, or the organization default.'}
			</p>
		</div>
	{/if}

</div>

<style lang="scss">
	.sms-editor {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);

		&__hint {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__meter {
			display: flex;
			min-height: 44px;
			box-sizing: border-box;
			flex-wrap: wrap;
			align-items: center;
			gap: var(--space-small) var(--space-base);
			padding: var(--space-small) var(--space-slim);
			border-radius: var(--radius-base);
			background: var(--color-surface--background);
		}

		&__fact {
			display: inline-flex;
			align-items: center;
			gap: 6px;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			font-variant-numeric: tabular-nums;

			strong {
				color: var(--color-heading);
				font-size: var(--typography--fontSize-label);
				font-weight: 600;
			}

			&--quiet {
				font-size: var(--typography--fontSize-label);
			}
		}

		&__fact-tile {
			display: grid;
			width: 24px;
			height: 24px;
			place-items: center;
			border-radius: var(--radius-tile-small);
			color: var(--color-conversation);
			background: var(--color-surface);

			:global(svg) {
				width: 14px;
				height: 14px;
			}
		}

		&__sender {
			display: flex;
			flex-direction: column;
			gap: var(--space-smaller);
		}

		&__hint--warning {
			color: var(--color-warning--onSurface);
		}
	}
</style>
