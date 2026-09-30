<script lang="ts">
	import { untrack } from 'svelte';
	import type { CalendarDate } from '@internationalized/date';
	import type {
		BillingCommandInput,
		BillingDialogState,
		OrganizationBilling
	} from '$lib/components/jafar/organization/types';
	import Button from '$lib/components/ui/Button.svelte';
	import CalendarPicker from '$lib/components/ui/CalendarPicker.svelte';
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import Textarea from '$lib/components/ui/Textarea.svelte';
	import { calendarDateFromString, calendarDateToString } from '$lib/components/ui/date-time';
	import {
		centsToInput,
		formatCalendarDate,
		formatDateTime,
		formatPeriod,
		formatUsd,
		parseUsdCents
	} from './format';

	// One dialog for every billing command. The Billing tab mounts it fresh for each opening, so the form
	// starts from what it was opened on and never carries values over from a previous action.
	let {
		dialog,
		billing,
		pending,
		error,
		fieldErrors,
		onSubmit,
		onClose
	}: {
		dialog: BillingDialogState;
		billing: OrganizationBilling;
		pending: boolean;
		error: string;
		fieldErrors: Record<string, string>;
		onSubmit: (command: BillingCommandInput) => void;
		onClose: () => void;
	} = $props();

	// The dialog is remounted for each opening, so reading the opening values once is intended.
	const initial = untrack(() => dialog);
	const opening = untrack(() => ({
		today: calendarDateFromString(billing.today),
		paidThrough: calendarDateFromString(billing.paid_through_date)
	}));
	const today = opening.today;

	const liveCharges = $derived(billing.charges.filter((charge) => charge.status !== 'cancelled'));
	const openCharges = $derived(
		liveCharges
			.filter((charge) => charge.outstanding_usd_cents > 0)
			.toSorted((a, b) => a.period_start.localeCompare(b.period_start))
	);
	const creditReceipts = $derived(
		billing.receipts.filter((receipt) => !receipt.voided_at && receipt.unapplied_usd_cents > 0)
	);
	const lastPeriodEnd = $derived(
		liveCharges.reduce<string | null>(
			(latest, charge) =>
				latest === null || charge.period_end > latest ? charge.period_end : latest,
			null
		)
	);
	const agreement = $derived(billing.current_agreement);

	const titles: Record<BillingDialogState['kind'], string> = {
		add_charge: 'Add charge',
		record_payment: 'Record payment',
		apply_credit: 'Use credit',
		refund: 'Record refund',
		void: 'Cancel record',
		correct_payment: 'Correct payment',
		confirm_coverage: 'Confirm dates covered',
		adjust_paid_through: 'Correct paid-through date',
		grant_free_access: 'Grant free access',
		extend_free_access: 'Extend free access',
		end_free_access: 'End free access',
		cancel_package_change: 'Cancel scheduled change',
		apply_change_credit: 'Use change credit'
	};

	let localError = $state('');
	let localFieldErrors = $state<Record<string, string>>({});
	const shownFieldErrors = $derived({ ...fieldErrors, ...localFieldErrors });

	// Shared fields ----------------------------------------------------------------------------------------
	const sourceReceipt =
		initial.kind === 'refund' || initial.kind === 'correct_payment' ? initial.receipt : null;
	let dateValue = $state<CalendarDate | undefined>(
		initial.kind === 'correct_payment'
			? calendarDateFromString(initial.receipt.received_on)
			: initial.kind === 'add_charge'
				? undefined
				: initial.kind === 'adjust_paid_through'
					? (opening.paidThrough ?? today)
					: today
	);
	let amount = $state(
		initial.kind === 'correct_payment' ? centsToInput(initial.receipt.amount_usd_cents) : ''
	);
	let method = $state(sourceReceipt?.method ?? '');
	let reference = $state(
		initial.kind === 'correct_payment' ? initial.receipt.private_reference : ''
	);
	let note = $state(initial.kind === 'correct_payment' ? (initial.receipt.note ?? '') : '');
	let reason = $state('');

	// Add charge -------------------------------------------------------------------------------------------
	const nextChargeStart = $derived(
		lastPeriodEnd
			? calendarDateFromString(lastPeriodEnd)?.add({ days: 1 })
			: (calendarDateFromString(agreement?.effective_from) ?? today)
	);
	let chargeStart = $state<CalendarDate | undefined>(undefined);
	const chosenChargeStart = $derived(chargeStart ?? nextChargeStart);

	// Record payment: which charges the money goes to --------------------------------------------------------
	const preferredChargeId = initial.kind === 'record_payment' ? initial.chargeId : null;
	let allocationEdited = $state(false);
	let allocationInputs = $state<Record<string, string>>({});
	// Until Jafar edits a line, the amount goes to the charge he opened this from, then to charges already
	// due, oldest first. Charges not yet due are only filled when he types into them.
	const suggestedAllocation = $derived.by(() => {
		let remaining = parseUsdCents(amount) ?? 0;
		const result: Record<string, string> = {};
		const ordered = [
			...openCharges.filter((charge) => charge.id === preferredChargeId),
			...openCharges.filter(
				(charge) => charge.id !== preferredChargeId && charge.period_start <= billing.today
			)
		];
		for (const charge of ordered) {
			const share = Math.min(remaining, charge.outstanding_usd_cents);
			if (share > 0) result[charge.id] = centsToInput(share);
			remaining -= share;
		}
		return result;
	});
	const allocation = $derived(allocationEdited ? allocationInputs : suggestedAllocation);
	const allocatedCents = $derived(
		Object.values(allocation).reduce((sum, value) => sum + (parseUsdCents(value) ?? 0), 0)
	);
	const leftAsCredit = $derived((parseUsdCents(amount) ?? 0) - allocatedCents);

	function editAllocation(chargeId: string, value: string) {
		if (!allocationEdited) {
			allocationInputs = { ...suggestedAllocation };
			allocationEdited = true;
		}
		allocationInputs[chargeId] = value;
	}

	// Use credit -------------------------------------------------------------------------------------------
	let creditReceiptId = $state(initial.kind === 'apply_credit' ? (initial.receiptId ?? '') : '');
	let creditChargeId = $state(initial.kind === 'apply_credit' ? (initial.chargeId ?? '') : '');
	const chosenCreditReceipt = $derived(
		creditReceipts.find((receipt) => receipt.id === (creditReceiptId || creditReceipts[0]?.id))
	);
	const chosenCreditCharge = $derived(
		openCharges.find((charge) => charge.id === (creditChargeId || openCharges[0]?.id))
	);
	const suggestedCredit = $derived(
		chosenCreditReceipt && chosenCreditCharge
			? Math.min(chosenCreditReceipt.unapplied_usd_cents, chosenCreditCharge.outstanding_usd_cents)
			: 0
	);
	let creditAmount = $state<string | null>(null);
	const creditAmountValue = $derived(
		creditAmount ?? (suggestedCredit ? centsToInput(suggestedCredit) : '')
	);

	// Use change credit (P8b): unused paid time a package change returned, moved onto a charge.
	const creditNotes = $derived(billing.credit_notes.filter((note) => note.unapplied_usd_cents > 0));
	let noteId = $state(initial.kind === 'apply_change_credit' ? (initial.creditNoteId ?? '') : '');
	let noteChargeId = $state(initial.kind === 'apply_change_credit' ? (initial.chargeId ?? '') : '');
	const chosenNote = $derived(
		creditNotes.find((note) => note.id === (noteId || creditNotes[0]?.id))
	);
	const chosenNoteCharge = $derived(
		openCharges.find((charge) => charge.id === (noteChargeId || openCharges[0]?.id))
	);
	let noteAmount = $state<string | null>(null);
	const noteAmountValue = $derived(
		noteAmount ??
			(chosenNote && chosenNoteCharge
				? centsToInput(
						Math.min(chosenNote.unapplied_usd_cents, chosenNoteCharge.outstanding_usd_cents)
					)
				: '')
	);

	// Free access ------------------------------------------------------------------------------------------
	// One current grant and one later grant, never overlapping (P5a). A new grant starts after the current one
	// ends; an extension of the current grant stops before the later one starts.
	const currentGrant = $derived(billing.free_access.find((grant) => grant.is_current) ?? null);
	const laterGrant = $derived(billing.free_access.find((grant) => !grant.is_current) ?? null);
	const earliestGrantStart = untrack(() => {
		const current = billing.free_access.find((grant) => grant.is_current);
		return current ? calendarDateFromString(current.last_day)?.add({ days: 1 }) : today;
	});
	let startsOn = $state<CalendarDate | undefined>(earliestGrantStart);
	let endsOn = $state<CalendarDate | undefined>(undefined);
	const extendedGrant = initial.kind === 'extend_free_access' ? initial.grant : null;
	const extendMinimum = extendedGrant
		? calendarDateFromString(extendedGrant.last_day)?.add({ days: 1 })
		: undefined;
	// The day before the later grant starts, when the grant being changed must stay clear of it.
	const lastDayBeforeLater = $derived(
		laterGrant && (initial.kind === 'grant_free_access' || extendedGrant?.is_current)
			? calendarDateFromString(laterGrant.starts_at)?.subtract({ days: 1 })
			: undefined
	);

	// Refund -----------------------------------------------------------------------------------------------
	let refundAmount = $state(
		initial.kind === 'refund' ? centsToInput(initial.receipt.unapplied_usd_cents) : ''
	);

	const voidCopy: Record<string, { consequence: string; button: string }> = {
		charge: {
			consequence:
				'The charge stays in the history marked cancelled and is no longer owed. Only the latest charge with no money on it can be cancelled.',
			button: 'Cancel charge'
		},
		receipt: {
			consequence:
				'The payment stays in the history marked cancelled. Any money it paid comes off those charges, so they are owed again. Dates already confirmed as covered do not change.',
			button: 'Cancel payment'
		},
		application: {
			consequence:
				'This amount comes off the charge, which is owed again, and goes back to the payment as credit.',
			button: 'Remove from charge'
		},
		refund: {
			consequence:
				'The refund stays in the history marked cancelled, and the money returns to the payment as credit.',
			button: 'Cancel refund'
		}
	};

	function requireAmount(value: string, key: string) {
		const cents = parseUsdCents(value);
		if (cents === null)
			localFieldErrors[key] = 'Enter an amount greater than zero, like 149 or 149.50.';
		return cents;
	}
	function requireText(value: string, key: string, message: string, minimum = 1) {
		const text = value.trim();
		if (text.length < minimum) localFieldErrors[key] = message;
		return text;
	}
	function requireDate(value: CalendarDate | undefined, key: string) {
		const text = calendarDateToString(value);
		if (!text) localFieldErrors[key] = 'Choose a date.';
		return text;
	}

	function buildCommand(): BillingCommandInput | null {
		localFieldErrors = {};
		localError = '';
		const reasonMessage = 'Enter a reason of at least 3 characters.';
		switch (initial.kind) {
			case 'add_charge':
				if (!chosenChargeStart) {
					localFieldErrors.period_start = 'Choose the date this service period starts.';
					return null;
				}
				return { action: 'add_charge', period_start: chosenChargeStart.toString() };
			case 'record_payment': {
				const received = requireDate(dateValue, 'received_on');
				const cents = requireAmount(amount, 'amount_usd_cents');
				const paidBy = requireText(method, 'method', 'Enter how the money was paid.');
				const ref = requireText(reference, 'private_reference', 'Enter the payment reference.');
				const applications = Object.entries(allocation)
					.map(([charge_id, value]) => ({ charge_id, amount_usd_cents: parseUsdCents(value) ?? 0 }))
					.filter((line) => line.amount_usd_cents > 0);
				for (const line of applications) {
					const charge = openCharges.find((candidate) => candidate.id === line.charge_id);
					if (charge && line.amount_usd_cents > charge.outstanding_usd_cents)
						localFieldErrors[`apply-${line.charge_id}`] =
							`Only ${formatUsd(charge.outstanding_usd_cents)} is owed on this charge.`;
				}
				if (cents !== null && allocatedCents > cents)
					localFieldErrors.applications = 'You are applying more than the payment amount.';
				if (Object.keys(localFieldErrors).length || cents === null) return null;
				return {
					action: 'record_payment',
					received_on: received,
					amount_usd_cents: cents,
					method: paidBy,
					private_reference: ref,
					note: note.trim() || null,
					applications
				};
			}
			case 'apply_credit': {
				const cents = requireAmount(creditAmountValue, 'amount_usd_cents');
				if (!chosenCreditReceipt || !chosenCreditCharge || cents === null) {
					if (!chosenCreditCharge) localFieldErrors.charge_id = 'Choose the charge to pay.';
					return null;
				}
				return {
					action: 'apply_credit',
					receipt_id: chosenCreditReceipt.id,
					charge_id: chosenCreditCharge.id,
					amount_usd_cents: cents
				};
			}
			case 'refund': {
				const refunded = requireDate(dateValue, 'refunded_on');
				const cents = requireAmount(refundAmount, 'amount_usd_cents');
				const paidBy = requireText(method, 'method', 'Enter how the money was returned.');
				const why = requireText(reason, 'reason', reasonMessage, 3);
				if (Object.keys(localFieldErrors).length || cents === null) return null;
				return {
					action: 'refund',
					receipt_id: initial.receipt.id,
					refunded_on: refunded,
					amount_usd_cents: cents,
					method: paidBy,
					private_reference: reference.trim() || null,
					reason: why
				};
			}
			case 'void': {
				const why = requireText(reason, 'reason', reasonMessage, 3);
				if (Object.keys(localFieldErrors).length) return null;
				return {
					action: 'void',
					record_kind: initial.recordKind,
					record_id: initial.recordId,
					reason: why
				};
			}
			case 'correct_payment': {
				const received = requireDate(dateValue, 'received_on');
				const cents = requireAmount(amount, 'amount_usd_cents');
				const paidBy = requireText(method, 'method', 'Enter how the money was paid.');
				const ref = requireText(reference, 'private_reference', 'Enter the payment reference.');
				const why = requireText(reason, 'reason', reasonMessage, 3);
				if (Object.keys(localFieldErrors).length || cents === null) return null;
				return {
					action: 'correct_payment',
					original_receipt_id: initial.receipt.id,
					received_on: received,
					amount_usd_cents: cents,
					method: paidBy,
					private_reference: ref,
					note: note.trim() || null,
					reason: why
				};
			}
			case 'confirm_coverage':
				return {
					action: 'confirm_coverage',
					charge_id: initial.charge.id,
					covered_from: initial.charge.period_start,
					covered_through: initial.charge.period_end
				};
			case 'adjust_paid_through': {
				const date = requireDate(dateValue, 'paid_through_date');
				const why = requireText(reason, 'reason', reasonMessage, 3);
				if (Object.keys(localFieldErrors).length) return null;
				return { action: 'adjust_paid_through', paid_through_date: date, reason: why };
			}
			case 'grant_free_access': {
				const starts = requireDate(startsOn, 'starts_on');
				const ends = requireDate(endsOn, 'ends_on');
				const why = requireText(reason, 'reason', reasonMessage, 3);
				if (starts && ends && ends < starts)
					localFieldErrors.ends_on = 'The last day must be on or after the first day.';
				if (Object.keys(localFieldErrors).length) return null;
				return { action: 'grant_free_access', starts_on: starts, ends_on: ends, reason: why };
			}
			case 'extend_free_access': {
				const ends = requireDate(endsOn, 'ends_on');
				const why = requireText(reason, 'reason', reasonMessage, 3);
				if (ends && ends <= initial.grant.last_day)
					localFieldErrors.ends_on = `Choose a day after ${formatCalendarDate(initial.grant.last_day)}.`;
				if (Object.keys(localFieldErrors).length) return null;
				return {
					action: 'extend_free_access',
					grant_id: initial.grant.grant_id,
					ends_on: ends,
					reason: why
				};
			}
			case 'end_free_access': {
				const why = requireText(reason, 'reason', reasonMessage, 3);
				if (Object.keys(localFieldErrors).length) return null;
				return { action: 'end_free_access', grant_id: initial.grant.grant_id, reason: why };
			}
			case 'cancel_package_change': {
				const why = requireText(reason, 'reason', reasonMessage, 3);
				if (Object.keys(localFieldErrors).length) return null;
				return {
					action: 'cancel_package_change',
					agreement_id: initial.agreement.id,
					reason: why
				};
			}
			case 'apply_change_credit': {
				const cents = requireAmount(noteAmountValue, 'amount_usd_cents');
				if (!chosenNote || !chosenNoteCharge || cents === null) {
					if (!chosenNoteCharge) localFieldErrors.charge_id = 'Choose the charge to pay.';
					return null;
				}
				return {
					action: 'apply_change_credit',
					credit_note_id: chosenNote.id,
					charge_id: chosenNoteCharge.id,
					amount_usd_cents: cents
				};
			}
		}
	}

	function submit(event: SubmitEvent) {
		event.preventDefault();
		const command = buildCommand();
		if (command) onSubmit(command);
		else if (!Object.keys(localFieldErrors).length) localError = 'Check the details and try again.';
	}

	const submitLabel = $derived(
		initial.kind === 'void'
			? voidCopy[initial.recordKind].button
			: initial.kind === 'confirm_coverage'
				? 'Confirm dates covered'
				: initial.kind === 'correct_payment'
					? 'Save correction'
					: titles[initial.kind]
	);
	const destructive =
		initial.kind === 'void' ||
		initial.kind === 'refund' ||
		initial.kind === 'end_free_access' ||
		initial.kind === 'cancel_package_change';
	const title =
		initial.kind === 'void' ? voidCopy[initial.recordKind].button : titles[initial.kind];
</script>

<Dialog open {title} size={initial.kind === 'record_payment' ? 'large' : 'default'} {onClose}>
	<form class="billing-dialog" onsubmit={submit} novalidate>
		{#if initial.kind === 'add_charge'}
			<p class="billing-dialog__lead">
				Adds what is owed for one {agreement?.billing_interval === 'year' ? 'year' : 'month'} of
				{agreement?.edition_name ?? 'the agreed package'}, at the agreed
				{agreement ? formatUsd(agreement.agreed_price_usd_cents) : 'price'}.
			</p>
			<CalendarPicker
				id="billing-charge-start"
				label="Service period starts"
				bind:value={() => chosenChargeStart, (value) => (chargeStart = value)}
				minValue={lastPeriodEnd ? nextChargeStart : undefined}
				invalid={Boolean(shownFieldErrors.period_start)}
				errorMessage={shownFieldErrors.period_start}
			/>
			<p class="billing-dialog__hint">
				{lastPeriodEnd
					? `The next period follows on from ${formatCalendarDate(lastPeriodEnd)}. Choose a later date only when service restarts after a break.`
					: 'This is the first charge. Choose the day service starts.'}
			</p>
		{:else if initial.kind === 'record_payment'}
			<p class="billing-dialog__lead">
				Record money you have confirmed arrived offsite. Recording it does not move the paid-through
				date — you confirm the covered dates separately once a charge is paid in full.
			</p>
			<div class="billing-dialog__grid">
				<CalendarPicker
					id="billing-received-on"
					label="Date received"
					bind:value={dateValue}
					maxValue={today}
					invalid={Boolean(shownFieldErrors.received_on)}
					errorMessage={shownFieldErrors.received_on}
				/>
				<Input
					id="billing-amount"
					label="Amount received (USD)"
					inputmode="decimal"
					placeholder="0.00"
					bind:value={amount}
					invalid={Boolean(shownFieldErrors.amount_usd_cents)}
					errorMessage={shownFieldErrors.amount_usd_cents}
				/>
				<Input
					id="billing-method"
					label="Paid by"
					placeholder="Bank transfer, Wise, PayPal…"
					bind:value={method}
					invalid={Boolean(shownFieldErrors.method)}
					errorMessage={shownFieldErrors.method}
				/>
				<Input
					id="billing-reference"
					label="Reference"
					placeholder="Transfer ID or receipt number"
					bind:value={reference}
					invalid={Boolean(shownFieldErrors.private_reference)}
					errorMessage={shownFieldErrors.private_reference}
				/>
			</div>
			<Textarea
				id="billing-note"
				label="Note (optional)"
				bind:value={note}
				rows={2}
				maxlength={1000}
			/>

			<fieldset class="billing-dialog__allocation">
				<legend>Apply to charges</legend>
				{#if openCharges.length === 0}
					<p class="billing-dialog__hint">
						Nothing is owed right now, so the whole payment is kept as credit.
					</p>
				{:else}
					<ul>
						{#each openCharges as charge (charge.id)}
							<li>
								<div>
									<strong>{formatPeriod(charge.period_start, charge.period_end)}</strong>
									<span
										>{formatUsd(charge.outstanding_usd_cents)} owed{charge.period_start >
										billing.today
											? ' · not due yet'
											: ''}</span
									>
								</div>
								<Input
									id={`billing-apply-${charge.id}`}
									label="Amount to apply"
									inputmode="decimal"
									aria-label={`Amount to apply to ${formatPeriod(charge.period_start, charge.period_end)}`}
									bind:value={
										() => allocation[charge.id] ?? '',
										(value) => editAllocation(charge.id, String(value ?? ''))
									}
									invalid={Boolean(shownFieldErrors[`apply-${charge.id}`])}
									errorMessage={shownFieldErrors[`apply-${charge.id}`]}
								/>
							</li>
						{/each}
					</ul>
				{/if}
				<p
					class="billing-dialog__remainder"
					class:billing-dialog__remainder--error={leftAsCredit < 0}
				>
					{leftAsCredit < 0
						? `Applying ${formatUsd(-leftAsCredit)} more than the payment.`
						: leftAsCredit > 0
							? `${formatUsd(leftAsCredit)} will be kept as credit until you use or refund it.`
							: 'The whole payment is applied.'}
				</p>
				{#if shownFieldErrors.applications}<p class="billing-dialog__error" role="alert">
						{shownFieldErrors.applications}
					</p>{/if}
			</fieldset>
		{:else if initial.kind === 'apply_credit'}
			<p class="billing-dialog__lead">
				Move money already received but not yet used onto a charge.
			</p>
			<Select
				id="billing-credit-receipt"
				label="Credit from"
				value={chosenCreditReceipt?.id ?? ''}
				options={creditReceipts.map((receipt) => ({
					value: receipt.id,
					label: `${formatCalendarDate(receipt.received_on)} · ${receipt.method} · ${formatUsd(receipt.unapplied_usd_cents)} unused`
				}))}
				onchange={(value) => {
					creditReceiptId = value;
					creditAmount = null;
				}}
			/>
			<Select
				id="billing-credit-charge"
				label="Pay towards"
				value={chosenCreditCharge?.id ?? ''}
				options={openCharges.map((charge) => ({
					value: charge.id,
					label: `${formatPeriod(charge.period_start, charge.period_end)} · ${formatUsd(charge.outstanding_usd_cents)} owed`
				}))}
				onchange={(value) => {
					creditChargeId = value;
					creditAmount = null;
				}}
			/>
			{#if shownFieldErrors.charge_id}<p class="billing-dialog__error" role="alert">
					{shownFieldErrors.charge_id}
				</p>{/if}
			<Input
				id="billing-credit-amount"
				label="Amount (USD)"
				inputmode="decimal"
				bind:value={() => creditAmountValue, (value) => (creditAmount = String(value ?? ''))}
				invalid={Boolean(shownFieldErrors.amount_usd_cents)}
				errorMessage={shownFieldErrors.amount_usd_cents}
			/>
		{:else if initial.kind === 'refund'}
			<p class="billing-dialog__lead">
				Record money you sent back offsite. Only the unused part of this payment —
				<strong>{formatUsd(initial.receipt.unapplied_usd_cents)}</strong> — can be refunded. To refund
				money already on a charge, remove it from that charge first.
			</p>
			<div class="billing-dialog__grid">
				<CalendarPicker
					id="billing-refunded-on"
					label="Date refunded"
					bind:value={dateValue}
					maxValue={today}
					invalid={Boolean(shownFieldErrors.refunded_on)}
					errorMessage={shownFieldErrors.refunded_on}
				/>
				<Input
					id="billing-refund-amount"
					label="Amount refunded (USD)"
					inputmode="decimal"
					bind:value={refundAmount}
					invalid={Boolean(shownFieldErrors.amount_usd_cents)}
					errorMessage={shownFieldErrors.amount_usd_cents}
				/>
				<Input
					id="billing-refund-method"
					label="Returned by"
					bind:value={method}
					invalid={Boolean(shownFieldErrors.method)}
					errorMessage={shownFieldErrors.method}
				/>
				<Input id="billing-refund-reference" label="Reference (optional)" bind:value={reference} />
			</div>
			<Textarea
				id="billing-reason"
				label="Reason"
				bind:value={reason}
				rows={3}
				maxlength={1000}
				invalid={Boolean(shownFieldErrors.reason)}
				errorMessage={shownFieldErrors.reason}
			/>
		{:else if initial.kind === 'void'}
			<p class="billing-dialog__lead">
				<strong>{initial.subject}</strong>
			</p>
			<p class="billing-dialog__hint">{voidCopy[initial.recordKind].consequence}</p>
			<Textarea
				id="billing-reason"
				label="Reason"
				bind:value={reason}
				rows={3}
				maxlength={1000}
				invalid={Boolean(shownFieldErrors.reason)}
				errorMessage={shownFieldErrors.reason}
			/>
		{:else if initial.kind === 'correct_payment'}
			<p class="billing-dialog__lead">
				Fix a payment recorded with the wrong details. The original stays in the history marked
				replaced, and the corrected payment goes onto the same charges as far as it reaches. Covered
				dates do not change.
			</p>
			<div class="billing-dialog__grid">
				<CalendarPicker
					id="billing-received-on"
					label="Date received"
					bind:value={dateValue}
					maxValue={today}
					invalid={Boolean(shownFieldErrors.received_on)}
					errorMessage={shownFieldErrors.received_on}
				/>
				<Input
					id="billing-amount"
					label="Amount received (USD)"
					inputmode="decimal"
					bind:value={amount}
					invalid={Boolean(shownFieldErrors.amount_usd_cents)}
					errorMessage={shownFieldErrors.amount_usd_cents}
				/>
				<Input
					id="billing-method"
					label="Paid by"
					bind:value={method}
					invalid={Boolean(shownFieldErrors.method)}
					errorMessage={shownFieldErrors.method}
				/>
				<Input
					id="billing-reference"
					label="Reference"
					bind:value={reference}
					invalid={Boolean(shownFieldErrors.private_reference)}
					errorMessage={shownFieldErrors.private_reference}
				/>
			</div>
			<Textarea
				id="billing-note"
				label="Note (optional)"
				bind:value={note}
				rows={2}
				maxlength={1000}
			/>
			<Textarea
				id="billing-reason"
				label="Why it needed correcting"
				bind:value={reason}
				rows={2}
				maxlength={1000}
				invalid={Boolean(shownFieldErrors.reason)}
				errorMessage={shownFieldErrors.reason}
			/>
		{:else if initial.kind === 'confirm_coverage'}
			<p class="billing-dialog__lead">
				This charge is paid in full. Confirm that the customer's access is covered for exactly these
				dates.
			</p>
			<dl class="billing-dialog__facts">
				<div>
					<dt>Covered from</dt>
					<dd>{formatCalendarDate(initial.charge.period_start)}</dd>
				</div>
				<div>
					<dt>Covered through</dt>
					<dd>{formatCalendarDate(initial.charge.period_end)}</dd>
				</div>
				<div>
					<dt>Paid</dt>
					<dd>{formatUsd(initial.charge.applied_usd_cents)}</dd>
				</div>
			</dl>
			<p class="billing-dialog__hint">
				Paid-through moves to {formatCalendarDate(initial.charge.period_end)}, and the charge for
				the next period is added so you can see the next renewal.
			</p>
		{:else if initial.kind === 'adjust_paid_through'}
			<p class="billing-dialog__lead">
				Set the paid-through date by hand. This changes access dates only — it records no money and
				changes no charge. Use it to fix a mistake, not to give free time.
			</p>
			<p class="billing-dialog__hint">
				Currently paid through {formatCalendarDate(billing.paid_through_date)}.
			</p>
			<CalendarPicker
				id="billing-paid-through"
				label="Paid through"
				bind:value={dateValue}
				invalid={Boolean(shownFieldErrors.paid_through_date)}
				errorMessage={shownFieldErrors.paid_through_date}
			/>
			<Textarea
				id="billing-reason"
				label="Reason"
				bind:value={reason}
				rows={3}
				maxlength={1000}
				invalid={Boolean(shownFieldErrors.reason)}
				errorMessage={shownFieldErrors.reason}
			/>
		{:else if initial.kind === 'grant_free_access'}
			<p class="billing-dialog__lead">
				Give covered days without payment. No money is recorded and no charge changes. While free
				access covers a day, the organization is never paused for payment, and a payment pause is
				lifted as soon as it starts.
			</p>
			{#if laterGrant}
				<p class="billing-dialog__hint">
					Free access is already scheduled from {formatCalendarDate(laterGrant.starts_at)}, so this
					grant starts today and ends before then.
				</p>
			{:else if currentGrant}
				<p class="billing-dialog__hint">
					Free access already runs through {formatCalendarDate(currentGrant.last_day)}, so this
					grant starts after that. To add days to it instead, extend it.
				</p>
			{/if}
			<div class="billing-dialog__grid">
				<CalendarPicker
					id="billing-free-starts"
					label="First free day"
					bind:value={startsOn}
					minValue={earliestGrantStart}
					maxValue={laterGrant ? today : undefined}
					invalid={Boolean(shownFieldErrors.starts_on)}
					errorMessage={shownFieldErrors.starts_on}
				/>
				<CalendarPicker
					id="billing-free-ends"
					label="Last free day"
					bind:value={endsOn}
					minValue={startsOn ?? earliestGrantStart}
					maxValue={lastDayBeforeLater}
					invalid={Boolean(shownFieldErrors.ends_on)}
					errorMessage={shownFieldErrors.ends_on}
				/>
			</div>
			<Textarea
				id="billing-reason"
				label="Reason"
				bind:value={reason}
				rows={3}
				maxlength={500}
				invalid={Boolean(shownFieldErrors.reason)}
				errorMessage={shownFieldErrors.reason}
			/>
		{:else if initial.kind === 'extend_free_access'}
			<p class="billing-dialog__lead">
				Free access {initial.grant.is_current ? 'runs' : 'is scheduled'} from
				{formatCalendarDate(initial.grant.starts_at)} through
				<strong>{formatCalendarDate(initial.grant.last_day)}</strong>. Choose the new last free day.
			</p>
			<CalendarPicker
				id="billing-free-ends"
				label="New last free day"
				bind:value={endsOn}
				minValue={extendMinimum}
				maxValue={lastDayBeforeLater}
				invalid={Boolean(shownFieldErrors.ends_on)}
				errorMessage={shownFieldErrors.ends_on}
			/>
			<Textarea
				id="billing-reason"
				label="Reason"
				bind:value={reason}
				rows={3}
				maxlength={500}
				invalid={Boolean(shownFieldErrors.reason)}
				errorMessage={shownFieldErrors.reason}
			/>
		{:else if initial.kind === 'end_free_access'}
			<p class="billing-dialog__lead">
				<strong>
					Free access {formatCalendarDate(initial.grant.starts_at)} – {formatCalendarDate(
						initial.grant.last_day
					)}
				</strong>
			</p>
			<p class="billing-dialog__hint">
				{initial.grant.is_current
					? 'Free access stops at the end of today. If nothing is paid beyond today, the seven-day grace week follows and access then pauses.'
					: 'This scheduled free access is cancelled and never starts.'} It stays in the history.
			</p>
			<Textarea
				id="billing-reason"
				label="Reason"
				bind:value={reason}
				rows={3}
				maxlength={500}
				invalid={Boolean(shownFieldErrors.reason)}
				errorMessage={shownFieldErrors.reason}
			/>
		{:else if initial.kind === 'cancel_package_change'}
			<p class="billing-dialog__lead">
				<strong>
					Move to {initial.agreement.edition_name} (edition {initial.agreement.edition_number}) on
					{formatDateTime(initial.agreement.effective_from)}
				</strong>
			</p>
			<p class="billing-dialog__hint">
				The customer stays on their current package and price. A waiting charge at the new price
				goes back to the current price. The cancelled change stays in the history.
			</p>
			<Textarea
				id="billing-reason"
				label="Reason"
				bind:value={reason}
				rows={3}
				maxlength={500}
				invalid={Boolean(shownFieldErrors.reason)}
				errorMessage={shownFieldErrors.reason}
			/>
		{:else if initial.kind === 'apply_change_credit'}
			<p class="billing-dialog__lead">
				Move credit from unused days of an earlier package onto a charge. It is credit, not money
				received, so it cannot be refunded.
			</p>
			<Select
				id="billing-note-credit"
				label="Credit from"
				value={chosenNote?.id ?? ''}
				options={creditNotes.map((note) => ({
					value: note.id,
					label: `Unused ${formatPeriod(note.unused_from, note.unused_through)} · ${formatUsd(note.unapplied_usd_cents)} left`
				}))}
				onchange={(value) => {
					noteId = value;
					noteAmount = null;
				}}
			/>
			<Select
				id="billing-note-charge"
				label="Pay towards"
				value={chosenNoteCharge?.id ?? ''}
				options={openCharges.map((charge) => ({
					value: charge.id,
					label: `${formatPeriod(charge.period_start, charge.period_end)} · ${formatUsd(charge.outstanding_usd_cents)} owed`
				}))}
				onchange={(value) => {
					noteChargeId = value;
					noteAmount = null;
				}}
			/>
			{#if shownFieldErrors.charge_id}<p class="billing-dialog__error" role="alert">
					{shownFieldErrors.charge_id}
				</p>{/if}
			<Input
				id="billing-note-amount"
				label="Amount (USD)"
				inputmode="decimal"
				bind:value={() => noteAmountValue, (value) => (noteAmount = String(value ?? ''))}
				invalid={Boolean(shownFieldErrors.amount_usd_cents)}
				errorMessage={shownFieldErrors.amount_usd_cents}
			/>
		{/if}

		{#if error || localError}<p class="billing-dialog__error" role="alert">
				{error || localError}
			</p>{/if}

		<div class="billing-dialog__actions">
			<Button type="button" variant="secondary" variation="subtle" onclick={onClose}>Close</Button>
			<Button type="submit" variation={destructive ? 'destructive' : 'work'} loading={pending}
				>{submitLabel}</Button
			>
		</div>
	</form>
</Dialog>

<style lang="scss">
	.billing-dialog {
		display: grid;
		gap: var(--space-base);
	}
	.billing-dialog p {
		margin: 0;
	}
	.billing-dialog__lead {
		color: var(--color-text);
		line-height: var(--typography--lineHeight-base);
	}
	.billing-dialog__hint {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		line-height: var(--typography--lineHeight-base);
	}
	.billing-dialog__grid {
		display: grid;
		grid-template-columns: repeat(2, minmax(0, 1fr));
		gap: var(--space-base);
	}
	.billing-dialog__allocation {
		display: grid;
		gap: var(--space-small);
		margin: 0;
		padding: var(--space-base);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface--background--subtle);
	}
	.billing-dialog__allocation legend {
		padding: 0 var(--space-small);
		color: var(--color-heading);
		font-weight: 700;
	}
	.billing-dialog__allocation ul {
		display: grid;
		gap: var(--space-small);
		margin: 0;
		padding: 0;
		list-style: none;
	}
	.billing-dialog__allocation li {
		display: grid;
		grid-template-columns: minmax(0, 1fr) 160px;
		align-items: center;
		gap: var(--space-base);
	}
	.billing-dialog__allocation li > div {
		display: grid;
		gap: var(--space-smallest);
	}
	.billing-dialog__allocation li span {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}
	.billing-dialog__remainder {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}
	.billing-dialog__remainder--error,
	.billing-dialog__error {
		color: var(--color-critical);
		font-size: var(--typography--fontSize-small);
	}
	.billing-dialog__facts {
		display: grid;
		grid-template-columns: repeat(3, minmax(0, 1fr));
		gap: var(--space-base);
		margin: 0;
		padding: var(--space-base);
		border-radius: var(--radius-base);
		background: var(--color-surface--background--subtle);
	}
	.billing-dialog__facts dt {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}
	.billing-dialog__facts dd {
		margin: var(--space-smallest) 0 0;
		color: var(--color-heading);
		font-weight: 700;
	}
	.billing-dialog__actions {
		display: flex;
		justify-content: flex-end;
		gap: var(--space-small);
		padding-top: var(--space-small);
	}
	@media (max-width: 639px) {
		.billing-dialog__grid,
		.billing-dialog__facts {
			grid-template-columns: 1fr;
		}
		.billing-dialog__allocation li {
			grid-template-columns: 1fr;
		}
	}
</style>
