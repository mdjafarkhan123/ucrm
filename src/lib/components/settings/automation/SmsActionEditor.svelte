<script lang="ts">
	import { tick } from 'svelte';
	import Textarea from '$lib/components/ui/Textarea.svelte';
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
		senderId,
		errorMessage = '',
		onBodyChange,
		onSenderIdChange
	}: {
		idPrefix: string;
		body: string;
		senderId: string;
		errorMessage?: string;
		onBodyChange: (value: string) => void;
		onSenderIdChange: (value: string) => void;
	} = $props();

	const bodyId = $derived(`${idPrefix}-body`);

	async function insertVariable(token: string) {
		const id = bodyId;
		const el = document.getElementById(id) as HTMLTextAreaElement | null;
		const placeholder = `{{${token}}}`;

		const start = el?.selectionStart ?? body.length;
		const end = el?.selectionEnd ?? body.length;
		const next = body.slice(0, start) + placeholder + body.slice(end);
		onBodyChange(next);

		await tick();
		const refreshed = document.getElementById(id) as HTMLTextAreaElement | null;
		if (refreshed) {
			const caret = start + placeholder.length;
			refreshed.focus();
			refreshed.setSelectionRange(caret, caret);
		}
	}

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

<div class="sms-editor">
	<Textarea
		id={bodyId}
		label="Message"
		required
		rows={5}
		maxlength={1000}
		value={body}
		oninput={(event: Event) => onBodyChange((event.currentTarget as HTMLTextAreaElement).value)}
	/>

	<div class="sms-editor__variables">
		<span class="sms-editor__variables-label">Insert a value</span>
		<div class="sms-editor__variable-list">
			{#each AUTOMATION_SMS_VARIABLES as variable (variable.token)}
				<button
					type="button"
					class="sms-editor__variable"
					onmousedown={(event) => event.preventDefault()}
					onclick={() => insertVariable(variable.token)}
				>
					{variable.label}
				</button>
			{/each}
		</div>
		<p class="sms-editor__hint">These get replaced with the real details when the text is sent.</p>
	</div>

	<p class="sms-editor__impact" aria-live="polite">
		{#if estimating}
			Estimating…
		{:else if estimate?.ready}
			{body.length} character{body.length === 1 ? '' : 's'} · {estimate.segment_count} segment{estimate.segment_count ===
			1
				? ''
				: 's'} · {formatEstimateCost(estimate)} estimated from {estimate.sender_phone}
		{:else if estimate && !estimate.ready}
			{estimate.reason}
		{:else}
			{body.length} character{body.length === 1 ? '' : 's'}
		{/if}
	</p>

	<div class="sms-editor__sender">
		<Select
			id={`${idPrefix}-sender`}
			label="Send from"
			value={senderId}
			options={senderOptions}
			disabled={sendersError}
			onchange={onSenderIdChange}
		/>
		<p class="sms-editor__hint">
			{sendersError
				? 'The organization’s SMS numbers could not be loaded — the usual number will be used.'
				: 'Left as the usual number, a text continues whichever number this customer’s texts have been using, or the organization default.'}
		</p>
	</div>

	{#if errorMessage}
		<p class="sms-editor__error" role="alert">{errorMessage}</p>
	{/if}
</div>

<style lang="scss">
	.sms-editor {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);

		&__variables {
			display: flex;
			flex-direction: column;
			gap: var(--space-small);
		}

		&__variables-label {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			font-weight: 600;
		}

		&__variable-list {
			display: flex;
			flex-wrap: wrap;
			gap: var(--space-small);
		}

		&__variable {
			display: inline-flex;
			align-items: center;
			min-height: 32px;
			padding: var(--space-smaller) var(--space-slim);
			border: var(--border-base) solid var(--color-border--interactive);
			border-radius: var(--radius-base);
			color: var(--color-interactive);
			background: var(--color-surface);
			font: inherit;
			font-weight: 600;
			cursor: pointer;
			transition: all var(--timing-base) ease-out;

			&:hover,
			&:focus-visible {
				border-color: var(--color-interactive--hover);
				color: var(--color-interactive--hover);
				background: var(--color-surface--hover);
			}
			&:focus-visible {
				outline: transparent;
				box-shadow: var(--shadow-focus);
			}
		}

		&__hint {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__impact {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			font-variant-numeric: tabular-nums;
		}

		&__sender {
			display: flex;
			flex-direction: column;
			gap: var(--space-smaller);
		}

		&__error {
			margin: 0;
			color: var(--color-critical);
			font-size: var(--typography--fontSize-small);
		}
	}
</style>
