<script lang="ts">
	import { resolve } from '$app/paths';
	import SectionBlock from '$lib/components/layout/SectionBlock.svelte';
	import Tabs from '$lib/components/ui/Tabs.svelte';
	import TabPanel from '$lib/components/ui/TabPanel.svelte';
	import type { InvoiceDocumentHistoryEntry, InvoicePaymentHistoryEntry } from '$lib/invoices/api';
	import { diffInvoiceDocument } from '$lib/invoices/document-history';
	import { INVOICE_PAYMENT_METHOD_LABELS } from '$lib/invoices/payment-methods';
	import cashIcon from '@tabler/icons/outline/cash.svg?raw';
	import depositIcon from '@tabler/icons/outline/pig-money.svg?raw';
	import undoIcon from '@tabler/icons/outline/arrow-back-up.svg?raw';

	// The invoice's own history in one card: the money that came in or went back out, and the edits made to
	// the document after it was issued. Everything here is read-only — the figures and the diffs are the
	// database's, this card only words them. It is drawn only for a reader who may see prices, because both
	// lists carry amounts.
	let {
		payments,
		edits,
		tab = $bindable('payments'),
		id,
		formatMoney,
		formatDay,
		formatDate,
		formatDateTime
	}: {
		payments: InvoicePaymentHistoryEntry[];
		edits: InvoiceDocumentHistoryEntry[];
		/** The open tab: `payments` or `edits`. Bound so the page's history button can open Edits. */
		tab?: string;
		/** Lets the page's history button scroll here. */
		id?: string;
		formatMoney: (amountMinor: number | null | undefined) => string;
		/** A `YYYY-MM-DD` calendar day. */
		formatDay: (value: string) => string;
		/** An instant, as a date. */
		formatDate: (iso: string) => string;
		/** An instant, as a date and time. */
		formatDateTime: (iso: string) => string;
	} = $props();

	// What actually stands on the bill: payments in, minus the ones taken back off.
	const netPaidMinor = $derived(
		payments.reduce(
			(sum, entry) => sum + (entry.entry_type === 'unapplied' ? -1 : 1) * entry.amount_minor,
			0
		)
	);

	const tabs = $derived([
		{
			value: 'payments',
			label: 'Payments',
			badge: payments.length > 0 ? formatMoney(netPaidMinor) : undefined,
			badgeTone: 'success' as const
		},
		{
			value: 'edits',
			label: 'Edits',
			badge: edits.length > 0 ? String(edits.length) : undefined
		}
	]);

	function entryLabel(entry: InvoicePaymentHistoryEntry) {
		const kind = entryKind(entry);
		const base =
			kind === 'removed'
				? 'Payment removed'
				: kind === 'deposit'
					? 'Deposit applied'
					: 'Payment received';
		return entry.method ? `${base} \u00b7 ${INVOICE_PAYMENT_METHOD_LABELS[entry.method]}` : base;
	}

	function entryKind(entry: InvoicePaymentHistoryEntry) {
		if (entry.entry_type === 'unapplied') return 'removed';
		return entry.source === 'deposit' ? 'deposit' : 'payment';
	}
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<SectionBlock
	tone="invoice"
	title="History"
	hint="Payments and changes on this invoice"
	level={2}
	{id}
	class="section-block--flush invoice-history"
>
	<Tabs {tabs} bind:value={tab} label="Invoice history" compact>
		<TabPanel value="payments">
			{#if payments.length > 0}
				<ul class="invoice-history__list">
					{#each payments as entry (entry.id)}
						{@const kind = entryKind(entry)}
						<li class="invoice-history__row">
							<span
								class={['invoice-history__badge', `invoice-history__badge--${kind}`]}
								aria-hidden="true"
							>
								{@html kind === 'deposit' ? depositIcon : kind === 'removed' ? undoIcon : cashIcon}
							</span>
							<div class="invoice-history__info">
								<!-- A recorded payment has a screen of its own; a reused quote deposit does
								     not, so only the payment rows are links. -->
								{#if entry.payment_event_id}
									<a
										class={[
											'invoice-history__label',
											'invoice-history__label--link',
											kind === 'payment' && 'invoice-history__label--in'
										]}
										href={resolve('/(app)/payments/[id=uuid]', { id: entry.payment_event_id })}
									>
										{entryLabel(entry)}
									</a>
								{:else}
									<span class="invoice-history__label">{entryLabel(entry)}</span>
								{/if}
								<span class="invoice-history__meta">
									{entry.payment_date
										? formatDay(entry.payment_date)
										: formatDate(entry.created_at)}
									{#if entry.reference}
										&middot; Ref {entry.reference}
									{/if}
								</span>
							</div>
							<span
								class={[
									'invoice-history__amount',
									entry.entry_type === 'unapplied' && 'invoice-history__amount--negative'
								]}
							>
								{entry.entry_type === 'unapplied' ? '−' : ''}{formatMoney(entry.amount_minor)}
							</span>
						</li>
					{/each}
				</ul>
			{:else}
				<p class="invoice-history__empty">
					No payments yet. Payments recorded against this invoice will show up here.
				</p>
			{/if}
		</TabPanel>

		<TabPanel value="edits">
			{#if edits.length > 0}
				<ul class="invoice-history__list">
					{#each edits as entry (entry.id)}
						{@const changes = diffInvoiceDocument(entry.before, entry.after, {
							formatMoney,
							formatDay
						})}
						<li class="invoice-history__edit">
							<div class="invoice-history__edit-head">
								<span class="invoice-history__label">
									{entry.actor_name ?? 'Someone'} edited the invoice
								</span>
								<span class="invoice-history__meta">
									{formatDateTime(entry.created_at)}
									{#if changes.length}
										&middot; {changes.length} change{changes.length === 1 ? '' : 's'}
									{/if}
								</span>
							</div>
							{#if changes.length}
								<ul class="invoice-history__changes">
									{#each changes as change (change.label)}
										<li>
											<span class="invoice-history__field">{change.label}</span>
											<span class="invoice-history__diff">
												{change.before} &rarr; {change.after}
											</span>
										</li>
									{/each}
								</ul>
							{/if}
						</li>
					{/each}
				</ul>
			{:else}
				<p class="invoice-history__empty">No edits since this invoice was issued.</p>
			{/if}
		</TabPanel>
	</Tabs>
</SectionBlock>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.invoice-history__list {
		display: flex;
		flex-direction: column;
		margin: 0;
		padding: 0;
		border-top: var(--border-base) solid var(--color-border);
		list-style: none;
	}

	.invoice-history__row {
		display: flex;
		align-items: center;
		gap: 14px;
		padding: 14px 24px;

		& + & {
			border-top: var(--border-base) solid var(--color-border);
		}
	}

	.invoice-history__badge {
		display: inline-grid;
		flex: 0 0 auto;
		width: 34px;
		height: 34px;
		place-items: center;
		border-radius: 999px;

		:global(svg) {
			display: block;
			width: 15px;
			height: 15px;
		}

		&--payment {
			color: var(--color-interactive);
			background: var(--color-success--surface);
		}
		&--deposit {
			color: var(--color-informative--onSurface);
			background: var(--color-informative--surface);
		}
		&--removed {
			color: var(--color-critical);
			background: var(--color-critical--surface);
		}
	}

	.invoice-history__info {
		display: grid;
		flex: 1 1 auto;
		min-width: 0;
		gap: 3px;
	}

	.invoice-history__label {
		color: var(--color-heading);
		font-size: var(--typography--fontSize-base);
		font-weight: 600;

		&--in {
			color: var(--color-interactive);
		}
		&--link {
			text-decoration: none;

			&:hover {
				text-decoration: underline;
			}
		}
	}

	.invoice-history__meta {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		font-weight: 500;
	}

	.invoice-history__amount {
		flex: 0 0 auto;
		color: var(--color-heading);
		font-size: var(--typography--fontSize-base);
		font-variant-numeric: tabular-nums;
		font-weight: 700;

		&--negative {
			color: var(--color-critical);
		}
	}

	.invoice-history__edit {
		display: flex;
		flex-direction: column;
		gap: var(--space-smaller);
		padding: 14px 24px;

		& + & {
			border-top: var(--border-base) solid var(--color-border);
		}
	}

	.invoice-history__edit-head {
		display: flex;
		flex-wrap: wrap;
		align-items: baseline;
		justify-content: space-between;
		gap: var(--space-base);
	}

	.invoice-history__changes {
		display: flex;
		flex-direction: column;
		gap: var(--space-smaller);
		margin: 0;
		padding: 0;
		list-style: none;

		li {
			display: flex;
			flex-wrap: wrap;
			gap: var(--space-smaller);
			font-size: var(--typography--fontSize-small);
		}
	}

	.invoice-history__field {
		flex-shrink: 0;
		min-width: 6rem;
		color: var(--color-text--secondary);
	}

	.invoice-history__diff {
		color: var(--color-text);
	}

	.invoice-history__empty {
		margin: 0;
		padding: 18px 24px 22px;
		font-size: var(--typography--fontSize-base);
		border-top: var(--border-base) solid var(--color-border);
		color: var(--color-text--secondary);
	}
</style>
