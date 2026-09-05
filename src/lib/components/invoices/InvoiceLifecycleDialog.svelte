<script lang="ts">
	import ConfirmDialog from '$lib/components/ui/ConfirmDialog.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import Textarea from '$lib/components/ui/Textarea.svelte';
	import { INVOICE_VOID_REASON_OPTIONS, type InvoiceVoidReason } from '$lib/invoices/lifecycle';
	import type { InvoiceLifecycleAction, InvoiceWriteError } from '$lib/invoices/api';
	import banIcon from '@tabler/icons/outline/ban.svg?raw';
	import cashOffIcon from '@tabler/icons/outline/cash-off.svg?raw';
	import clipboardCheckIcon from '@tabler/icons/outline/clipboard-check.svg?raw';
	import undoIcon from '@tabler/icons/outline/arrow-back-up.svg?raw';

	// One of the five close/reopen transitions on an issued bill (Part 7b), built on the same ConfirmDialog +
	// Textarea shape the Quote lifecycle already uses. This dialog owns its fields, its retry fingerprint and
	// the error line; the page owns the tenant write and what follows (invalidate, toast). The database
	// re-checks every guard and hands back the sentence to show — including D2, where void refuses while
	// ordinary payments are still applied — so nothing here re-derives whether the move is allowed.
	type Mode = InvoiceLifecycleAction['action'];

	let {
		open,
		mode,
		invoiceNumber,
		onClose,
		onSave,
		onSaved
	}: {
		open: boolean;
		mode: Mode;
		invoiceNumber: number;
		onClose: () => void;
		onSave: (
			action: InvoiceLifecycleAction,
			idempotencyKey: string,
			requestHash: string
		) => Promise<void>;
		onSaved: () => void | Promise<void>;
	} = $props();

	// What each mode says and asks for. `pickVoidReason` adds the four-way reason picker; `reasonRequired`
	// makes the free-text field a required "why" the history keeps, otherwise it is an optional note.
	const COPY: Record<
		Mode,
		{
			icon: string;
			title: string;
			intro: string;
			confirmLabel: string;
			tone: 'default' | 'critical';
			destructive: boolean;
			pickVoidReason: boolean;
			reasonRequired: boolean;
			fieldLabel: string;
		}
	> = {
		void: {
			icon: banIcon,
			title: 'Void this invoice?',
			intro:
				'Voiding cancels the bill for good. It stays on record with its reason, any attached deposits go back to client credit, and it can never be sent or paid again.',
			confirmLabel: 'Void invoice',
			tone: 'critical',
			destructive: true,
			pickVoidReason: true,
			reasonRequired: false,
			fieldLabel: 'Note (optional)'
		},
		write_off: {
			icon: cashOffIcon,
			title: 'Write off the balance?',
			intro:
				'This marks the unpaid balance as bad debt: the bill and its payments stay exactly as they are, it just stops counting as money the client owes. You can undo it later.',
			confirmLabel: 'Write off balance',
			tone: 'default',
			destructive: true,
			pickVoidReason: false,
			reasonRequired: false,
			fieldLabel: 'Note (optional)'
		},
		restore_write_off: {
			icon: undoIcon,
			title: 'Undo the write-off?',
			intro: "This puts the bill's remaining balance back into what the client owes.",
			confirmLabel: 'Undo write-off',
			tone: 'default',
			destructive: false,
			pickVoidReason: false,
			reasonRequired: true,
			fieldLabel: 'Reason'
		},
		mark_received: {
			icon: clipboardCheckIcon,
			title: 'Mark this invoice as received?',
			intro:
				'This closes the bill as paid without recording any money — use it when payment was handled outside the app. The client account balance is unchanged.',
			confirmLabel: 'Mark as received',
			tone: 'default',
			destructive: false,
			pickVoidReason: false,
			reasonRequired: true,
			fieldLabel: 'Reason'
		},
		reopen: {
			icon: undoIcon,
			title: 'Reopen this invoice?',
			intro:
				'This undoes the by-hand closure and puts the bill back to awaiting payment or past due.',
			confirmLabel: 'Reopen invoice',
			tone: 'default',
			destructive: false,
			pickVoidReason: false,
			reasonRequired: true,
			fieldLabel: 'Reason'
		}
	};

	const copy = $derived(COPY[mode]);

	// A fresh instance every time the page opens the dialog (it is `{#if}`-gated), so plain initialisers are
	// the reset — the same shape CollectPaymentDialog relies on.
	let voidReason = $state('');
	let text = $state('');
	let saving = $state(false);
	let error = $state('');
	let idempotencyKey = crypto.randomUUID();
	let lastHash = '';

	const confirmDisabled = $derived(
		saving || (copy.pickVoidReason && !voidReason) || (copy.reasonRequired && !text.trim())
	);

	function fingerprint(value: unknown): string {
		const json = JSON.stringify(value);
		let hash = 0x811c9dc5;
		for (let index = 0; index < json.length; index++) {
			hash ^= json.charCodeAt(index);
			hash = Math.imul(hash, 0x01000193);
		}
		return `v1:${(hash >>> 0).toString(16)}`;
	}

	function buildAction(): InvoiceLifecycleAction {
		const note = text.trim() || null;
		switch (mode) {
			case 'void':
				return { action: 'void', reason: voidReason as InvoiceVoidReason, note };
			case 'write_off':
				return { action: 'write_off', note };
			case 'restore_write_off':
				return { action: 'restore_write_off', reason: text.trim() };
			case 'mark_received':
				return { action: 'mark_received', reason: text.trim() };
			case 'reopen':
				return { action: 'reopen', reason: text.trim() };
		}
	}

	async function confirm() {
		if (confirmDisabled) return;
		error = '';

		const action = buildAction();
		const hash = fingerprint(action);
		if (hash !== lastHash) {
			idempotencyKey = crypto.randomUUID();
			lastHash = hash;
		}

		saving = true;
		try {
			await onSave(action, idempotencyKey, hash);
			await onSaved();
			onClose();
		} catch (cause) {
			const failure = cause as InvoiceWriteError;
			// Guard refusals (D2 among them) arrive as a form-level field error carrying the database's own
			// sentence; fall back to the plain message otherwise.
			error = failure.fieldErrors?.form ?? failure.message ?? 'That change could not be saved.';
		} finally {
			saving = false;
		}
	}
</script>

<ConfirmDialog
	{open}
	title={copy.title}
	icon={copy.icon}
	tone={copy.tone}
	confirmLabel={copy.confirmLabel}
	destructive={copy.destructive}
	loading={saving}
	{confirmDisabled}
	onConfirm={() => void confirm()}
	{onClose}
>
	<div class="invoice-lifecycle">
		<p class="invoice-lifecycle__intro">Invoice #{invoiceNumber}. {copy.intro}</p>

		{#if copy.pickVoidReason}
			<Select
				id="invoice-void-reason"
				label="Reason"
				bind:value={voidReason}
				options={[{ value: '', label: 'Choose a reason…' }, ...INVOICE_VOID_REASON_OPTIONS]}
				disabled={saving}
			/>
		{/if}

		<Textarea
			id="invoice-lifecycle-text"
			label={copy.fieldLabel}
			rows={3}
			maxlength={2000}
			bind:value={text}
			disabled={saving}
		/>

		{#if error}<p class="invoice-lifecycle__error" role="alert">{error}</p>{/if}
	</div>
</ConfirmDialog>

<style lang="scss">
	.invoice-lifecycle {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);
	}

	.invoice-lifecycle__intro {
		margin: 0;
	}

	.invoice-lifecycle__error {
		margin: 0;
		color: var(--color-critical);
		font-size: var(--typography--fontSize-small);
	}
</style>
