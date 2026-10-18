<script lang="ts">
	import { resolve } from '$app/paths';
	import arrowRightIcon from '@tabler/icons/outline/arrow-right.svg?raw';
	import receiptIcon from '@tabler/icons/outline/receipt.svg?raw';
	import { initials } from '$lib/collaboration/format';
	import HomeCardState from '$lib/components/dashboard/HomeCardState.svelte';
	import CardHeader from '$lib/components/ui/CardHeader.svelte';
	import type { MoneyOwed } from '$lib/home/api';
	import { formatWhole } from '$lib/home/format';
	import type { InvoiceListItem } from '$lib/invoices/api';

	// Money owed: what clients owe today, how much of it is overdue, and the three clients furthest behind.
	// Left out entirely for anyone without invoice prices (the page decides), never shown as zero.
	let {
		owed,
		overdueInvoices = [],
		today,
		currency = 'USD',
		locale = 'en-US',
		loading = false,
		failed = false,
		onretry
	}: {
		owed: MoneyOwed | undefined;
		/** Past-due invoices, any order; the three furthest past due are picked here. */
		overdueInvoices?: InvoiceListItem[];
		/** The business's today, `YYYY-MM-DD`, from which days late are counted. */
		today: string;
		currency?: string;
		locale?: string;
		loading?: boolean;
		failed?: boolean;
		onretry?: () => void;
	} = $props();

	const money = (minor: number) => formatWhole(minor, currency, locale);
	const overdue = $derived(
		owed
			? owed.overdue_1_30_minor +
					owed.overdue_31_60_minor +
					owed.overdue_61_90_minor +
					owed.overdue_91_plus_minor
			: 0
	);
	const buckets = $derived(
		owed
			? [
					{ key: 'current', label: 'Not due yet', minor: owed.not_due_minor },
					{ key: 'late1', label: '1–30 days late', minor: owed.overdue_1_30_minor },
					{ key: 'late2', label: '31–60 days late', minor: owed.overdue_31_60_minor },
					{ key: 'late3', label: '61–90 days late', minor: owed.overdue_61_90_minor },
					{ key: 'late4', label: 'Over 90 days late', minor: owed.overdue_91_plus_minor }
				]
			: []
	);

	// The bar shows not-yet-due against overdue; how late the overdue part is stays in its spoken label.
	const barLabel = $derived(
		buckets
			.filter((bucket) => bucket.minor > 0)
			.map((bucket) => `${bucket.label} ${money(bucket.minor)}`)
			.join(', ')
	);

	function daysLate(dueDate: string) {
		return Math.round((Date.parse(today) - Date.parse(dueDate)) / 86_400_000);
	}
	const mostOverdue = $derived(
		overdueInvoices
			.filter((invoice) => (invoice.remaining_minor ?? 0) > 0)
			.map((invoice) => ({ invoice, days: daysLate(invoice.due_date) }))
			.sort((a, b) => b.days - a.days || a.invoice.invoice_number - b.invoice.invoice_number)
			.slice(0, 3)
	);

	function clientName(invoice: InvoiceListItem) {
		return invoice.client?.company_name ?? invoice.client?.display_name ?? 'Client';
	}

	const uid = $props.id();
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<section class="home-owed" aria-labelledby="{uid}-title" aria-busy={loading}>
	<CardHeader id="{uid}-title" title="Money owed" icon={receiptIcon} tone="invoice">
		{#snippet actions()}
			<a class="home-owed__link" href={resolve('/(app)/invoices')}
				>View all<span class="home-owed__arrow" aria-hidden="true">{@html arrowRightIcon}</span></a
			>
		{/snippet}
	</CardHeader>
	{#if loading}
		<HomeCardState state="loading" label="money owed" rows={4} />
	{:else if failed || !owed}
		<HomeCardState state="error" label="money owed" {onretry} />
	{:else if owed.open_invoice_count === 0}
		<HomeCardState
			state="empty"
			label="money owed"
			title="Nothing owed right now"
			description="Invoices waiting to be paid will show here, split by how late they are."
			icon={receiptIcon}
		/>
	{:else}
		<div class="home-owed__body">
			<div class="home-owed__figure">
				<p class="home-owed__value">{money(owed.outstanding_minor)}</p>
				<p class="home-owed__line">
					Owed by {owed.client_count}
					{owed.client_count === 1 ? 'client' : 'clients'} today
				</p>
			</div>
			<div class="home-owed__ageing">
				<div
					class="home-owed__bar"
					role="img"
					aria-label="Money owed by how late it is: {barLabel}"
				>
					{#if owed.not_due_minor > 0}
						<span
							class="home-owed__segment home-owed__segment--current"
							style:flex-grow={owed.not_due_minor}
						></span>
					{/if}
					{#if overdue > 0}
						<span class="home-owed__segment home-owed__segment--overdue" style:flex-grow={overdue}
						></span>
					{/if}
				</div>
				<dl class="home-owed__key">
					<div>
						<dt>
							<span class="home-owed__dot home-owed__segment--current" aria-hidden="true"></span>Not
							yet due
						</dt>
						<dd>{money(owed.not_due_minor)}</dd>
					</div>
					<div>
						<dt>
							<span class="home-owed__dot home-owed__segment--overdue" aria-hidden="true"
							></span>Overdue
						</dt>
						<dd>{money(overdue)}</dd>
					</div>
				</dl>
			</div>
			{#if mostOverdue.length > 0}
				<div class="home-owed__clients">
					<h3>Most overdue</h3>
					<ul>
						{#each mostOverdue as { invoice, days } (invoice.id)}
							<li>
								<a href={resolve('/(app)/invoices/[id=uuid]', { id: invoice.id })}>
									<span class="home-owed__initials" aria-hidden="true"
										>{initials(clientName(invoice))}</span
									>
									<span class="home-owed__who">
										<strong>{clientName(invoice)}</strong>
										<span
											><span class="home-owed__late">{days} {days === 1 ? 'day' : 'days'} late</span
											>
											· Invoice #{invoice.invoice_number}</span
										>
									</span>
									<span class="home-owed__amount">{money(invoice.remaining_minor ?? 0)}</span>
								</a>
							</li>
						{/each}
					</ul>
				</div>
			{/if}
		</div>
	{/if}
</section>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.home-owed {
		min-width: 0;
		overflow: hidden;
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-large);
		background: var(--color-surface);

		&__link {
			display: inline-flex;
			align-items: center;
			gap: var(--space-smaller);
			border-radius: var(--radius-small);
			color: var(--color-interactive);
			font-size: var(--typography--fontSize-label);
			font-weight: 600;
			text-decoration: none;

			&:hover {
				color: var(--color-interactive--hover);
			}
			&:focus-visible {
				outline: none;
				box-shadow: var(--shadow-focus);
			}
		}
		&__arrow {
			display: inline-flex;

			:global(svg) {
				width: 14px;
				height: 14px;
			}
		}

		&__body {
			display: grid;
			gap: var(--space-medium);
			padding: var(--space-medium);
		}

		&__figure {
			display: grid;
			gap: 2px;
		}
		&__value {
			color: var(--color-heading);
			font-size: var(--typography--fontSize-stat);
			font-weight: 700;
			letter-spacing: -0.8px;
			line-height: 1.2;
			font-variant-numeric: tabular-nums;
		}
		&__line {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-label);
		}

		&__ageing {
			display: grid;
			gap: var(--space-small);
		}
		&__bar {
			display: flex;
			gap: 3px;
			height: 10px;
			overflow: hidden;
			border-radius: var(--radius-circle);
		}
		&__segment {
			min-width: 6px;
			flex-basis: 0;

			&--current {
				background: var(--color-informative);
			}
			&--overdue {
				background: var(--color-critical);
			}
		}
		&__key {
			display: flex;
			flex-wrap: wrap;
			justify-content: space-between;
			gap: var(--space-small) var(--space-base);
			margin: 0;

			div {
				display: flex;
				align-items: center;
				gap: 6px;
				font-size: var(--typography--fontSize-label);
			}
			dt {
				display: inline-flex;
				align-items: center;
				gap: 6px;
				color: var(--color-text--secondary);
			}
			dd {
				margin: 0;
				color: var(--color-heading);
				font-weight: 600;
				font-variant-numeric: tabular-nums;
			}
		}
		&__dot {
			width: 8px;
			height: 8px;
			border-radius: var(--radius-circle);
		}

		&__clients {
			display: grid;
			gap: var(--space-small);
			padding-top: var(--space-medium);
			border-top: var(--border-base) solid var(--color-border);

			h3 {
				color: var(--color-text--secondary);
				font-size: var(--typography--fontSize-overline);
				font-weight: 600;
				letter-spacing: 0.6px;
				text-transform: uppercase;
			}
			ul {
				display: grid;
				margin: 0;
				padding: 0;
				list-style: none;
			}
			a {
				display: flex;
				align-items: center;
				gap: var(--space-slim);
				margin: 0 calc(-1 * var(--space-small));
				padding: var(--space-small);
				border-radius: var(--radius-base);
				color: inherit;
				text-decoration: none;

				&:hover {
					background: var(--color-surface--hover);
				}
				&:focus-visible {
					outline: none;
					box-shadow: var(--shadow-focus);
				}
			}
		}
		&__initials {
			display: inline-flex;
			flex: 0 0 auto;
			align-items: center;
			justify-content: center;
			width: 32px;
			height: 32px;
			border-radius: var(--radius-base);
			color: var(--color-client--onSurface);
			background: var(--color-client--surface);
			font-size: var(--typography--fontSize-small);
			font-weight: 700;
		}
		&__who {
			display: grid;
			min-width: 0;
			flex: 1;
			gap: 2px;

			strong {
				overflow: hidden;
				color: var(--color-heading);
				font-size: var(--typography--fontSize-base);
				font-weight: 600;
				text-overflow: ellipsis;
				white-space: nowrap;
			}
			> span {
				overflow: hidden;
				color: var(--color-text--secondary);
				font-size: var(--typography--fontSize-small);
				text-overflow: ellipsis;
				white-space: nowrap;
			}
		}
		&__late {
			color: var(--color-critical);
			font-weight: 500;
		}
		&__amount {
			flex: 0 0 auto;
			color: var(--color-heading);
			font-size: var(--typography--fontSize-base);
			font-weight: 600;
			font-variant-numeric: tabular-nums;
		}
	}
</style>
