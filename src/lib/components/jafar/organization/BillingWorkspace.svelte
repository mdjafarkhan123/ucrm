<script lang="ts">
	import type {
		BillingCharge,
		BillingCommandInput,
		BillingDialogState,
		BillingFreeAccessGrant,
		BillingReceipt,
		BillingResponse,
		OrganizationBilling
	} from '$lib/components/jafar/organization/types';
	import type { OrganizationDetailPreview } from '$lib/jafar/organization-detail-preview';
	import { createMutation, createQuery, useQueryClient } from '@tanstack/svelte-query';
	import alertIcon from '@tabler/icons/outline/alert-triangle.svg?raw';
	import calendarIcon from '@tabler/icons/outline/calendar-check.svg?raw';
	import cashIcon from '@tabler/icons/outline/cash.svg?raw';
	import giftIcon from '@tabler/icons/outline/gift.svg?raw';
	import packageIcon from '@tabler/icons/outline/package.svg?raw';
	import receiptIcon from '@tabler/icons/outline/receipt.svg?raw';
	import walletIcon from '@tabler/icons/outline/wallet.svg?raw';
	import Badge from '$lib/components/ui/Badge.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import DropdownMenu from '$lib/components/ui/DropdownMenu.svelte';
	import TabPanel from '$lib/components/ui/TabPanel.svelte';
	import SectionBlock from '$lib/components/layout/SectionBlock.svelte';
	import DataTable, { type DataTableColumn } from '$lib/components/data-display/DataTable.svelte';
	import EmptyState from '$lib/components/data-display/EmptyState.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import KpiCard from '$lib/components/data-display/KpiCard.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import OwnerReconfirmDialog from '$lib/components/jafar/OwnerReconfirmDialog.svelte';
	import BillingActionDialog from './BillingActionDialog.svelte';
	import BillingPackageSection from './BillingPackageSection.svelte';
	import PackageChangeDialog from './PackageChangeDialog.svelte';
	import { organizationBillingQuery } from '$lib/jafar/organization-billing-queries';
	import {
		jafarOrganizationBillingKey,
		jafarOrganizationKey,
		jafarOrganizationsKey,
		jafarPackagesKey
	} from '$lib/jafar/query-keys';
	import { formatCalendarDate, formatDateTime, formatPeriod, formatUsd } from './format';

	let {
		organizationId,
		preview
	}: {
		organizationId: string | undefined;
		preview: OrganizationDetailPreview | null;
	} = $props();

	const queryClient = useQueryClient();
	const billingQuery = createQuery(() => ({
		...organizationBillingQuery(organizationId ?? ''),
		enabled: !preview && Boolean(organizationId)
	}));
	const billing = $derived(billingQuery.data?.billing ?? null);

	// Dialogs and the one mutation behind them ---------------------------------------------------------------
	type BillingMutationResponse = {
		billing?: OrganizationBilling;
		error?: string;
		field_errors?: Record<string, string>;
		step_up_required?: boolean;
		preview_stale?: boolean;
	};
	class BillingActionError extends Error {
		fieldErrors: Record<string, string>;
		stepUpRequired: boolean;
		previewStale: boolean;
		constructor(result: BillingMutationResponse) {
			super(result.error ?? 'The billing action could not be recorded.');
			this.fieldErrors = result.field_errors ?? {};
			this.stepUpRequired = result.step_up_required === true;
			this.previewStale = result.preview_stale === true;
		}
	}

	let dialog = $state<BillingDialogState | null>(null);
	// Each opening gets one idempotency key, so a retry after a dropped connection cannot record twice.
	let dialogKey = $state('');
	let dialogError = $state('');
	let dialogFieldErrors = $state<Record<string, string>>({});
	let feedback = $state('');
	let reconfirmOpen = $state(false);
	let pendingCommand = $state<(BillingCommandInput & { idempotency_key: string }) | null>(null);

	// The Change package dialog is separate from the ledger dialogs but shares their key and error state.
	let changeOpen = $state(false);

	function startOpening() {
		dialogKey = crypto.randomUUID();
		dialogError = '';
		dialogFieldErrors = {};
		feedback = '';
	}
	function openDialog(next: BillingDialogState) {
		startOpening();
		dialog = next;
	}
	function openChange() {
		startOpening();
		changeOpen = true;
	}
	function closeDialog() {
		dialog = null;
		changeOpen = false;
	}

	const successMessages: Record<BillingCommandInput['action'], string> = {
		add_charge: 'Charge added.',
		record_payment: 'Payment recorded.',
		apply_credit: 'Credit applied.',
		refund: 'Refund recorded.',
		void: 'Record cancelled. It stays in the history.',
		correct_payment: 'Payment corrected. The original stays in the history.',
		confirm_coverage: 'Dates confirmed as covered. The next charge has been added.',
		adjust_paid_through: 'Paid-through date corrected.',
		grant_free_access: 'Free access granted.',
		extend_free_access: 'Free access extended.',
		end_free_access: 'Free access ended. It stays in the Activity tab.',
		change_package: 'Package changed.',
		cancel_package_change: 'Scheduled change cancelled. It stays in the package history.',
		apply_change_credit: 'Change credit applied.'
	};

	const billingMutation = createMutation<
		BillingMutationResponse,
		BillingActionError,
		BillingCommandInput & { idempotency_key: string }
	>(() => ({
		mutationFn: async (command) => {
			const response = await fetch(`/api/jafar/organizations/${organizationId}/billing`, {
				method: 'POST',
				headers: { 'content-type': 'application/json' },
				body: JSON.stringify(command)
			});
			const result = (await response.json()) as BillingMutationResponse;
			if (!response.ok) throw new BillingActionError(result);
			return result;
		},
		onMutate: () => {
			dialogError = '';
			dialogFieldErrors = {};
		},
		onError: (error, command) => {
			if (error.stepUpRequired) {
				pendingCommand = command;
				reconfirmOpen = true;
				return;
			}
			dialogError = error.message;
			dialogFieldErrors = error.fieldErrors;
			// The figures Jafar confirmed moved on; the dialog's preview reloads with the new ones.
			if (error.previewStale)
				void queryClient.invalidateQueries({
					queryKey: [...jafarOrganizationKey(organizationId), 'package-change-preview']
				});
		},
		onSuccess: (result, command) => {
			if (result.billing)
				queryClient.setQueryData<BillingResponse>(jafarOrganizationBillingKey(organizationId), {
					billing: result.billing
				});
			pendingCommand = null;
			dialog = null;
			changeOpen = false;
			feedback =
				command.action === 'change_package' && command.timing === 'next_renewal'
					? `Change scheduled for ${formatCalendarDate(command.expected_effective_date)}.`
					: successMessages[command.action];
			if (command.action === 'change_package' || command.action === 'cancel_package_change')
				void queryClient.invalidateQueries({ queryKey: jafarPackagesKey });
			// Paid-through feeds the access check, the Access tab, the history, and the directory's flags.
			// The billing answer came back with the command, so only the rest is refetched.
			void queryClient.invalidateQueries({
				queryKey: jafarOrganizationsKey,
				predicate: (query) =>
					!(query.queryKey[2] === organizationId && query.queryKey[3] === 'billing')
			});
		}
	}));

	function submitCommand(command: BillingCommandInput) {
		billingMutation.mutate({ ...command, idempotency_key: dialogKey });
	}
	function confirmStepUp() {
		if (pendingCommand) billingMutation.mutate(pendingCommand);
	}

	// What the tables show -------------------------------------------------------------------------------------
	const chargeColumns: DataTableColumn[] = [
		{ key: 'period', label: 'Service period' },
		{ key: 'amount', label: 'Amount', align: 'end' },
		{ key: 'paid', label: 'Paid', align: 'end' },
		{ key: 'owed', label: 'Still owed', align: 'end' },
		{ key: 'status', label: 'Status' }
	];
	const receiptColumns: DataTableColumn[] = [
		{ key: 'received', label: 'Received' },
		{ key: 'amount', label: 'Amount', align: 'end' },
		{ key: 'method', label: 'Paid by' },
		{ key: 'reference', label: 'Reference' },
		{ key: 'unused', label: 'Unused credit', align: 'end' },
		{ key: 'status', label: 'Status' }
	];

	const freeAccessColumns: DataTableColumn[] = [
		{ key: 'dates', label: 'Free days' },
		{ key: 'status', label: 'Status' },
		{ key: 'reason', label: 'Reason' },
		{ key: 'granted', label: 'Granted' }
	];
	// One current and one later grant at most (P5a), so a new grant is possible only while one is missing.
	const canGrantFreeAccess = $derived(
		(billing?.free_access.length ?? 0) < 2 && Boolean(billing?.current_agreement)
	);
	function freeAccessMenu(grant: BillingFreeAccessGrant) {
		return [
			{
				label: grant.is_current ? 'End free access' : 'Cancel scheduled free access',
				destructive: true,
				onSelect: () => openDialog({ kind: 'end_free_access', grant })
			}
		];
	}

	const paymentCreditAvailable = $derived(
		(billing?.receipts ?? []).some(
			(receipt) => !receipt.voided_at && receipt.unapplied_usd_cents > 0
		)
	);
	const changeCreditAvailable = $derived(
		(billing?.credit_notes ?? []).some((note) => note.unapplied_usd_cents > 0)
	);
	const creditNoteColumns: DataTableColumn[] = [
		{ key: 'days', label: 'Unused days' },
		{ key: 'amount', label: 'Credit', align: 'end' },
		{ key: 'used', label: 'Used', align: 'end' },
		{ key: 'left', label: 'Left', align: 'end' },
		{ key: 'created', label: 'From the change on' }
	];
	function creditNoteLabel(creditNoteId: string) {
		const note = billing?.credit_notes.find((candidate) => candidate.id === creditNoteId);
		return note
			? `change credit for ${formatPeriod(note.unused_from, note.unused_through)}`
			: 'change credit';
	}
	const latestLiveChargeId = $derived(
		billing?.charges.find((charge) => charge.status !== 'cancelled')?.id ?? null
	);
	const replacedBy = $derived(
		new Map(
			(billing?.receipts ?? [])
				.filter((receipt) => receipt.replaces_receipt_id)
				.map((receipt) => [receipt.replaces_receipt_id as string, receipt])
		)
	);

	function chargeLabel(chargeId: string) {
		const charge = billing?.charges.find((candidate) => candidate.id === chargeId);
		return charge ? formatPeriod(charge.period_start, charge.period_end) : 'a charge';
	}
	function receiptLabel(receiptId: string) {
		const receipt = billing?.receipts.find((candidate) => candidate.id === receiptId);
		return receipt
			? `${formatUsd(receipt.amount_usd_cents)} received ${formatCalendarDate(receipt.received_on)}`
			: 'a payment';
	}

	function chargeStatus(charge: BillingCharge, today: string) {
		if (charge.status === 'cancelled') return { label: 'Cancelled', tone: 'inactive' } as const;
		if (charge.coverage_confirmed_at) return { label: 'Covered', tone: 'success' } as const;
		if (charge.status === 'paid')
			return { label: 'Paid · confirm dates', tone: 'informative' } as const;
		if (charge.status === 'partly_paid') return { label: 'Partly paid', tone: 'warning' } as const;
		if (charge.period_start > today) return { label: 'Not due yet', tone: 'inactive' } as const;
		return { label: 'Unpaid', tone: 'critical' } as const;
	}
	function receiptStatus(receipt: BillingReceipt) {
		if (receipt.voided_at)
			return replacedBy.has(receipt.id)
				? ({ label: 'Replaced', tone: 'inactive' } as const)
				: ({ label: 'Cancelled', tone: 'inactive' } as const);
		if (receipt.unapplied_usd_cents > 0)
			return { label: 'Has credit', tone: 'informative' } as const;
		if (receipt.refunded_usd_cents > 0 && receipt.applied_usd_cents === 0)
			return { label: 'Refunded', tone: 'inactive' } as const;
		return { label: 'Applied', tone: 'success' } as const;
	}

	function chargeMenu(charge: BillingCharge) {
		const items = [];
		if (charge.outstanding_usd_cents > 0 && paymentCreditAvailable)
			items.push({
				label: 'Use payment credit',
				onSelect: () => openDialog({ kind: 'apply_credit', chargeId: charge.id, receiptId: null })
			});
		if (charge.outstanding_usd_cents > 0 && changeCreditAvailable)
			items.push({
				label: 'Use change credit',
				onSelect: () =>
					openDialog({ kind: 'apply_change_credit', chargeId: charge.id, creditNoteId: null })
			});
		if (
			charge.id === latestLiveChargeId &&
			charge.applied_usd_cents === 0 &&
			!charge.coverage_confirmed_at
		)
			items.push({
				label: 'Cancel charge',
				destructive: true,
				onSelect: () =>
					openDialog({
						kind: 'void',
						recordKind: 'charge',
						recordId: charge.id,
						subject: `Charge for ${formatPeriod(charge.period_start, charge.period_end)} · ${formatUsd(charge.amount_usd_cents)}`
					})
			});
		return items;
	}
	function receiptMenu(receipt: BillingReceipt) {
		if (receipt.voided_at) return [];
		const items = [];
		if (receipt.unapplied_usd_cents > 0)
			items.push({
				label: 'Record refund',
				onSelect: () => openDialog({ kind: 'refund', receipt })
			});
		items.push({
			label: 'Correct payment',
			onSelect: () => openDialog({ kind: 'correct_payment', receipt })
		});
		items.push({
			label: 'Cancel payment',
			destructive: true,
			onSelect: () =>
				openDialog({
					kind: 'void',
					recordKind: 'receipt',
					recordId: receipt.id,
					subject: `Payment of ${formatUsd(receipt.amount_usd_cents)} received ${formatCalendarDate(receipt.received_on)}`
				})
		});
		return items;
	}

	const renewalBanner = $derived.by(() => {
		if (!billing?.renewal_flag || billing.free_access_today) return null;
		if (billing.renewal_flag === 'overdue')
			return {
				tone: 'critical',
				title: 'Payment overdue',
				detail: `Paid through ended ${formatCalendarDate(billing.paid_through_date)}. The grace week ends ${formatDateTime(billing.grace_ends_at)}.`
			} as const;
		return {
			tone: 'warning',
			title: billing.renewal_flag === 'due_tomorrow' ? 'Renewal due tomorrow' : 'Renewal due soon',
			detail: `Paid through ${formatCalendarDate(billing.paid_through_date)}. The next period starts ${formatCalendarDate(billing.next_renewal_date)}.`
		} as const;
	});
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<TabPanel value="billing">
	<div class="billing-workspace">
		{#if preview}
			<EmptyState
				title="Billing is not part of this preview"
				description="Development scenarios cannot show or change money records. Open a real organization to use Billing."
			/>
		{:else if billingQuery.isPending}
			<div class="billing-workspace__summary" aria-busy="true">
				{#each ['Package', 'Paid through', 'Due now', 'Credit'] as label (label)}
					<LoadingSkeleton variant="card" label={`Loading ${label.toLowerCase()}`} />
				{/each}
			</div>
			<LoadingSkeleton variant="card" label="Loading charges" />
			<LoadingSkeleton variant="card" label="Loading payments" />
		{:else if billingQuery.isError && !billing}
			<ErrorState
				title="Billing could not be loaded"
				description={billingQuery.error?.message ?? 'Try again.'}
				retry={() => billingQuery.refetch()}
			/>
		{:else if billing}
			<div class="billing-workspace__summary">
				<KpiCard
					label="Package"
					value={billing.current_agreement?.edition_name ?? 'No agreement'}
					note={billing.current_agreement
						? `${formatUsd(billing.current_agreement.agreed_price_usd_cents)} per ${billing.current_agreement.billing_interval} · edition ${billing.current_agreement.edition_number}`
						: 'Assign a package before billing'}
					icon={packageIcon}
					variant="compact"
				/>
				<KpiCard
					label="Paid through"
					value={billing.paid_through_date
						? formatCalendarDate(billing.paid_through_date)
						: 'Not yet'}
					note={billing.free_access_today
						? `Free access covers through ${formatCalendarDate(billing.covered_through)}`
						: billing.next_renewal_date
							? `Next period starts ${formatCalendarDate(billing.next_renewal_date)}`
							: 'Confirm the first covered dates'}
					icon={calendarIcon}
					tone={billing.free_access_today
						? 'informative'
						: billing.renewal_flag === 'overdue'
							? 'critical'
							: billing.renewal_flag
								? 'warning'
								: 'default'}
					variant="compact"
				/>
				<KpiCard
					label="Due now"
					value={formatUsd(billing.totals.due_now_usd_cents)}
					note={billing.totals.outstanding_usd_cents > billing.totals.due_now_usd_cents
						? `${formatUsd(billing.totals.outstanding_usd_cents)} including upcoming`
						: 'Nothing else upcoming'}
					icon={cashIcon}
					tone={billing.totals.due_now_usd_cents > 0 ? 'warning' : 'default'}
					variant="compact"
				/>
				<KpiCard
					label="Credit"
					value={formatUsd(billing.totals.credit_usd_cents)}
					note={`${formatUsd(billing.totals.received_usd_cents)} received · ${formatUsd(billing.totals.refunded_usd_cents)} refunded`}
					icon={walletIcon}
					tone={billing.totals.credit_usd_cents > 0 ? 'informative' : 'default'}
					variant="compact"
				/>
			</div>

			{#if renewalBanner}
				<div
					class="billing-workspace__banner billing-workspace__banner--{renewalBanner.tone}"
					role="status"
				>
					<span aria-hidden="true">{@html alertIcon}</span>
					<div>
						<strong>{renewalBanner.title}</strong>
						<p>{renewalBanner.detail}</p>
					</div>
				</div>
			{/if}

			{#if feedback}<p class="billing-workspace__feedback" role="status">{feedback}</p>{/if}

			<BillingPackageSection
				{billing}
				onChange={openChange}
				onCancelChange={(agreement) => openDialog({ kind: 'cancel_package_change', agreement })}
			/>

			<SectionBlock
				title="Free access"
				icon={giftIcon}
				hint="Covered days without payment, always with an end date. While free access covers today, the organization is never paused for payment."
			>
				{#snippet actions()}
					<Button
						size="small"
						variant="secondary"
						disabled={!canGrantFreeAccess}
						onclick={() => openDialog({ kind: 'grant_free_access' })}>Grant free access</Button
					>
				{/snippet}
				{#if billing.free_access.length === 0}
					<EmptyState
						title="No free access"
						description={billing.current_agreement
							? 'Grant free access to cover dates without payment, for a trial or a goodwill gesture.'
							: 'This organization has no package agreement, so there is nothing to cover.'}
					/>
				{:else}
					<DataTable
						caption="Free access"
						columns={freeAccessColumns}
						items={billing.free_access}
						rowId={(grant) => grant.grant_id}
					>
						{#snippet row(grant)}
							<td>
								<strong>{formatPeriod(grant.starts_at, grant.last_day)}</strong>
							</td>
							<td>
								<Badge status={grant.is_current ? 'success' : 'informative'} size="small"
									>{grant.is_current ? 'Running' : 'Scheduled'}</Badge
								>
							</td>
							<td class="billing-workspace__reason">{grant.reason}</td>
							<td class="billing-workspace__secondary">
								{formatDateTime(grant.granted_at)}{grant.granted_by ? ` · ${grant.granted_by}` : ''}
							</td>
						{/snippet}
						{#snippet rowActions(grant)}
							<div class="billing-workspace__row-actions">
								<Button
									size="small"
									variant="secondary"
									onclick={() => openDialog({ kind: 'extend_free_access', grant })}>Extend</Button
								>
								<DropdownMenu
									triggerLabel="More free access actions"
									items={freeAccessMenu(grant)}
								/>
							</div>
						{/snippet}
					</DataTable>
				{/if}
			</SectionBlock>

			<SectionBlock
				title="Charges"
				icon={receiptIcon}
				hint="What is owed for each service period. Paid-through moves only when you confirm a paid charge's dates."
			>
				{#snippet actions()}
					<Button
						size="small"
						variant="secondary"
						disabled={!billing.current_agreement}
						onclick={() => openDialog({ kind: 'add_charge' })}>Add charge</Button
					>
				{/snippet}
				{#if billing.charges.length === 0}
					<EmptyState
						title="No charges yet"
						description={billing.current_agreement
							? 'Add the first charge on the day service starts, then record the payment against it.'
							: 'This organization has no package agreement, so there is nothing to charge.'}
					/>
				{:else}
					<DataTable
						caption="Charges"
						columns={chargeColumns}
						items={billing.charges}
						rowId={(charge) => charge.id}
						isExpanded={(charge) =>
							charge.status === 'cancelled' ||
							billing.applications.some((line) => line.charge_id === charge.id)}
					>
						{#snippet row(charge)}
							{@const status = chargeStatus(charge, billing.today)}
							<td class:billing-workspace__muted={charge.status === 'cancelled'}>
								<strong>{formatPeriod(charge.period_start, charge.period_end)}</strong>
								{#if charge.kind === 'change'}
									<span class="billing-workspace__secondary"
										>Rest of period after a package change</span
									>
								{/if}
							</td>
							<td class="align-end billing-workspace__money"
								>{formatUsd(charge.amount_usd_cents)}</td
							>
							<td class="align-end billing-workspace__money"
								>{formatUsd(charge.applied_usd_cents)}</td
							>
							<td class="align-end billing-workspace__money">
								<strong>{formatUsd(charge.outstanding_usd_cents)}</strong>
							</td>
							<td><Badge status={status.tone} size="small">{status.label}</Badge></td>
						{/snippet}
						{#snippet rowActions(charge)}
							{@const menu = chargeMenu(charge)}
							<div class="billing-workspace__row-actions">
								{#if charge.status !== 'cancelled' && charge.outstanding_usd_cents > 0}
									<Button
										size="small"
										variant="secondary"
										onclick={() => openDialog({ kind: 'record_payment', chargeId: charge.id })}
										>Record payment</Button
									>
								{:else if charge.status === 'paid' && !charge.coverage_confirmed_at}
									<Button
										size="small"
										onclick={() => openDialog({ kind: 'confirm_coverage', charge })}
										>Confirm dates</Button
									>
								{/if}
								{#if menu.length}
									<DropdownMenu triggerLabel="More charge actions" items={menu} />
								{/if}
							</div>
						{/snippet}
						{#snippet rowDetail(charge)}
							<ul class="billing-workspace__trail">
								{#if charge.void_reason}
									<li class="billing-workspace__trail-void">
										Cancelled {formatDateTime(charge.voided_at)}: {charge.void_reason}
									</li>
								{/if}
								{#each billing.applications.filter((line) => line.charge_id === charge.id) as line (line.id)}
									<li class:billing-workspace__trail-void={line.voided_at}>
										<span>
											{formatUsd(line.amount_usd_cents)} from {line.receipt_id
												? receiptLabel(line.receipt_id)
												: creditNoteLabel(line.credit_note_id ?? '')}{line.voided_at
												? ` — removed: ${line.void_reason}`
												: ''}
										</span>
										{#if !line.voided_at && !charge.coverage_confirmed_at && line.receipt_id}
											<Button
												size="small"
												variant="tertiary"
												variation="subtle"
												onclick={() =>
													openDialog({
														kind: 'void',
														recordKind: 'application',
														recordId: line.id,
														subject: `${formatUsd(line.amount_usd_cents)} from ${receiptLabel(line.receipt_id ?? '')}, applied to ${formatPeriod(charge.period_start, charge.period_end)}`
													})}>Remove</Button
											>
										{/if}
									</li>
								{/each}
							</ul>
						{/snippet}
					</DataTable>
				{/if}
			</SectionBlock>

			<SectionBlock
				title="Payments"
				icon={cashIcon}
				hint="Money you confirmed arrived offsite. Money not applied to a charge stays as credit."
			>
				{#snippet actions()}
					<Button
						size="small"
						onclick={() => openDialog({ kind: 'record_payment', chargeId: null })}
						>Record payment</Button
					>
				{/snippet}
				{#if billing.receipts.length === 0}
					<EmptyState
						title="No payments recorded"
						description="When money arrives offsite, record it here and choose the charge it pays."
					/>
				{:else}
					<DataTable
						caption="Payments"
						columns={receiptColumns}
						items={billing.receipts}
						rowId={(receipt) => receipt.id}
						isExpanded={(receipt) =>
							Boolean(
								receipt.note ||
								receipt.voided_at ||
								receipt.replaces_receipt_id ||
								billing.refunds.some((refund) => refund.receipt_id === receipt.id)
							)}
					>
						{#snippet row(receipt)}
							{@const status = receiptStatus(receipt)}
							<td class:billing-workspace__muted={receipt.voided_at}>
								<strong>{formatCalendarDate(receipt.received_on)}</strong>
							</td>
							<td class="align-end billing-workspace__money"
								>{formatUsd(receipt.amount_usd_cents)}</td
							>
							<td>{receipt.method}</td>
							<td class="billing-workspace__reference">{receipt.private_reference}</td>
							<td class="align-end billing-workspace__money"
								>{formatUsd(receipt.unapplied_usd_cents)}</td
							>
							<td><Badge status={status.tone} size="small">{status.label}</Badge></td>
						{/snippet}
						{#snippet rowActions(receipt)}
							{@const menu = receiptMenu(receipt)}
							<div class="billing-workspace__row-actions">
								{#if !receipt.voided_at && receipt.unapplied_usd_cents > 0 && billing.totals.outstanding_usd_cents > 0}
									<Button
										size="small"
										variant="secondary"
										onclick={() =>
											openDialog({ kind: 'apply_credit', chargeId: null, receiptId: receipt.id })}
										>Use credit</Button
									>
								{/if}
								{#if menu.length}
									<DropdownMenu triggerLabel="More payment actions" items={menu} />
								{/if}
							</div>
						{/snippet}
						{#snippet rowDetail(receipt)}
							<ul class="billing-workspace__trail">
								{#if receipt.replaces_receipt_id}
									<li>Replaces {receiptLabel(receipt.replaces_receipt_id)}.</li>
								{/if}
								{#if receipt.voided_at}
									<li class="billing-workspace__trail-void">
										{replacedBy.has(receipt.id) ? 'Replaced' : 'Cancelled'}
										{formatDateTime(receipt.voided_at)}: {receipt.void_reason}
									</li>
								{/if}
								{#if receipt.note}<li>Note: {receipt.note}</li>{/if}
								{#each billing.refunds.filter((refund) => refund.receipt_id === receipt.id) as refund (refund.id)}
									<li class:billing-workspace__trail-void={refund.voided_at}>
										<span>
											Refunded {formatUsd(refund.amount_usd_cents)} on
											{formatCalendarDate(refund.refunded_on)} by {refund.method}: {refund.reason}{refund.voided_at
												? ` — refund cancelled: ${refund.void_reason}`
												: ''}
										</span>
										{#if !refund.voided_at}
											<Button
												size="small"
												variant="tertiary"
												variation="subtle"
												onclick={() =>
													openDialog({
														kind: 'void',
														recordKind: 'refund',
														recordId: refund.id,
														subject: `Refund of ${formatUsd(refund.amount_usd_cents)} on ${formatCalendarDate(refund.refunded_on)}`
													})}>Cancel refund</Button
											>
										{/if}
									</li>
								{/each}
							</ul>
						{/snippet}
					</DataTable>
				{/if}
			</SectionBlock>

			{#if billing.credit_notes.length}
				<SectionBlock
					title="Change credit"
					icon={walletIcon}
					hint="Unused paid days returned when the package changed. Credit, not money received: use it on a charge; it cannot be refunded."
				>
					<DataTable
						caption="Change credit"
						columns={creditNoteColumns}
						items={billing.credit_notes}
						rowId={(note) => note.id}
					>
						{#snippet row(note)}
							<td><strong>{formatPeriod(note.unused_from, note.unused_through)}</strong></td>
							<td class="align-end billing-workspace__money">{formatUsd(note.amount_usd_cents)}</td>
							<td class="align-end billing-workspace__money">{formatUsd(note.applied_usd_cents)}</td
							>
							<td class="align-end billing-workspace__money">
								<strong>{formatUsd(note.unapplied_usd_cents)}</strong>
							</td>
							<td class="billing-workspace__secondary">{formatDateTime(note.created_at)}</td>
						{/snippet}
						{#snippet rowActions(note)}
							<div class="billing-workspace__row-actions">
								{#if note.unapplied_usd_cents > 0 && billing.totals.outstanding_usd_cents > 0}
									<Button
										size="small"
										variant="secondary"
										onclick={() =>
											openDialog({
												kind: 'apply_change_credit',
												creditNoteId: note.id,
												chargeId: null
											})}>Use credit</Button
									>
								{/if}
							</div>
						{/snippet}
					</DataTable>
				</SectionBlock>
			{/if}

			<div class="billing-workspace__footer">
				<p>
					Dates follow the organization's time zone ({billing.commercial_timezone}), where today is
					{formatCalendarDate(billing.today)}.
				</p>
				<Button
					size="small"
					variant="tertiary"
					variation="subtle"
					onclick={() => openDialog({ kind: 'adjust_paid_through' })}
					>Correct paid-through date</Button
				>
			</div>
		{/if}
	</div>
</TabPanel>

{#if changeOpen && billing && organizationId}
	{#key dialogKey}
		<PackageChangeDialog
			{organizationId}
			{billing}
			pending={billingMutation.isPending}
			error={dialogError}
			fieldErrors={dialogFieldErrors}
			onSubmit={submitCommand}
			onClose={closeDialog}
		/>
	{/key}
{/if}

{#if dialog && billing}
	{#key dialogKey}
		<BillingActionDialog
			{dialog}
			{billing}
			pending={billingMutation.isPending}
			error={dialogError}
			fieldErrors={dialogFieldErrors}
			onSubmit={submitCommand}
			onClose={closeDialog}
		/>
	{/key}
{/if}

<OwnerReconfirmDialog
	bind:open={reconfirmOpen}
	title="Confirm it's you"
	description="Refunds, cancellations, payment corrections, paid-through changes, and free access changes need your password each time."
	confirmLabel="Continue"
	onConfirm={confirmStepUp}
/>

<style lang="scss">
	.billing-workspace {
		display: grid;
		gap: var(--space-large);
		min-width: 0;
	}
	.billing-workspace p {
		margin: 0;
	}
	.billing-workspace__summary {
		display: grid;
		grid-template-columns: repeat(4, minmax(0, 1fr));
		gap: var(--space-base);
	}
	.billing-workspace__summary :global(.skeleton--card) {
		height: 104px;
	}
	.billing-workspace__banner {
		display: flex;
		align-items: flex-start;
		gap: var(--space-small);
		padding: var(--space-slim) var(--space-base);
		border-radius: var(--radius-base);
		color: var(--banner-text);
		background: var(--banner-surface);
	}
	.billing-workspace__banner--warning {
		--banner-text: var(--color-warning--onSurface);
		--banner-surface: var(--color-warning--surface);
	}
	.billing-workspace__banner--critical {
		--banner-text: var(--color-critical--onSurface);
		--banner-surface: var(--color-critical--surface);
	}
	.billing-workspace__banner > span {
		display: inline-flex;
		flex: 0 0 auto;
	}
	.billing-workspace__banner :global(svg) {
		width: 20px;
		height: 20px;
	}
	.billing-workspace__banner strong {
		display: block;
		color: inherit;
	}
	.billing-workspace__banner p {
		margin-top: var(--space-smallest);
		color: inherit;
	}
	.billing-workspace__note,
	.billing-workspace__footer p {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		line-height: var(--typography--lineHeight-base);
	}
	.billing-workspace__feedback {
		padding: var(--space-slim) var(--space-base);
		border-radius: var(--radius-base);
		color: var(--color-success--onSurface);
		background: var(--color-success--surface);
	}
	.billing-workspace__money {
		font-variant-numeric: tabular-nums;
		white-space: nowrap;
	}
	.billing-workspace__reference {
		max-width: 180px;
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}
	.billing-workspace__reason {
		max-width: 320px;
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}
	.billing-workspace__secondary {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		white-space: nowrap;
	}
	.billing-workspace__muted strong {
		color: var(--color-text--secondary);
		text-decoration: line-through;
	}
	.billing-workspace__row-actions {
		display: flex;
		align-items: center;
		justify-content: flex-end;
		gap: var(--space-small);
	}
	.billing-workspace__trail {
		display: grid;
		gap: var(--space-smaller);
		margin: 0;
		padding: 0 0 0 var(--space-base);
		border-left: var(--border-thick, 2px) solid var(--color-border);
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		list-style: none;
	}
	.billing-workspace__trail li {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-small);
		min-height: 28px;
	}
	.billing-workspace__trail-void {
		color: var(--color-text--secondary);
		font-style: italic;
	}
	.billing-workspace__footer {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-small);
	}
	@media (max-width: 1100px) {
		.billing-workspace__summary {
			grid-template-columns: repeat(2, minmax(0, 1fr));
		}
	}
	@media (max-width: 639px) {
		.billing-workspace__summary {
			grid-template-columns: 1fr;
		}
	}
</style>
