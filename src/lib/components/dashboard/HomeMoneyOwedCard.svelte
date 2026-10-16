<script lang="ts">
	import { resolve } from '$app/paths';
	import arrowRightIcon from '@tabler/icons/outline/arrow-right.svg?raw';
	import coinsIcon from '@tabler/icons/outline/coins.svg?raw';
	import receiptIcon from '@tabler/icons/outline/receipt.svg?raw';
	import HomeCardState from '$lib/components/dashboard/HomeCardState.svelte';
	import Avatar from '$lib/components/ui/Avatar.svelte';
	import type { MoneyOwed } from '$lib/home/api';
	import { formatWhole } from '$lib/home/format';
	import type { InvoiceListItem } from '$lib/invoices/api';

	// Money owed: what clients owe today, how late it is, and the three clients furthest behind. Left out
	// entirely for anyone without invoice prices (the page decides), never shown as zero.
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
	<div class="home-owed__top">
		<header class="home-owed__header">
			<h2 id="{uid}-title">
				<span class="home-owed__icon" aria-hidden="true">{@html coinsIcon}</span>Money owed
			</h2>
			<a class="home-owed__link" href={resolve('/(app)/invoices')}
				>View all<span class="home-owed__arrow" aria-hidden="true">{@html arrowRightIcon}</span></a
			>
		</header>
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
			<div class="home-owed__figure">
				<p class="home-owed__value">{money(owed.outstanding_minor)}</p>
				<p class="home-owed__line">
					{owed.client_count}
					{owed.client_count === 1 ? 'client owes' : 'clients owe'} you
					{#if overdue > 0}· <strong>{money(overdue)} overdue</strong>{/if}
				</p>
			</div>
			<div class="home-owed__bar" role="img" aria-label="Money owed by how late it is">
				{#each buckets as bucket (bucket.key)}
					{#if bucket.minor > 0}
						<span
							class={['home-owed__segment', `home-owed__segment--${bucket.key}`]}
							style:flex-grow={bucket.minor}
						></span>
					{/if}
				{/each}
			</div>
			<dl class="home-owed__key">
				{#each buckets as bucket (bucket.key)}
					{#if bucket.key === 'current' || bucket.key !== 'late4' || bucket.minor > 0}
						<div>
							<dt>
								<span
									class={['home-owed__dot', `home-owed__segment--${bucket.key}`]}
									aria-hidden="true"
								></span>{bucket.label}
							</dt>
							<dd>{money(bucket.minor)}</dd>
						</div>
					{/if}
				{/each}
			</dl>
		{/if}
	</div>
	{#if owed && mostOverdue.length > 0}
		<div class="home-owed__clients">
			<h3>Most overdue</h3>
			<ul>
				{#each mostOverdue as { invoice, days } (invoice.id)}
					<li>
						<a href={resolve('/(app)/invoices/[id=uuid]', { id: invoice.id })}>
							<Avatar id={invoice.client?.id ?? invoice.id} name={clientName(invoice)} size="base" />
							<span class="home-owed__who">
								<strong>{clientName(invoice)}</strong>
								<span>Invoice #{invoice.invoice_number} · {days} {days === 1 ? 'day' : 'days'} late</span>
							</span>
							<span class="home-owed__amount">{money(invoice.remaining_minor ?? 0)}</span>
						</a>
					</li>
				{/each}
			</ul>
		</div>
	{/if}
</section>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.home-owed {
		min-width: 0;
		overflow: hidden;
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface);

		&__top {
			display: grid;
			gap: 14px;
			padding: 20px 20px 18px;
		}
		&__header {
			display: flex;
			align-items: center;
			justify-content: space-between;
			gap: var(--space-base);

			h2 {
				display: flex;
				align-items: center;
				gap: 10px;
				color: var(--color-text--secondary);
				font-size: 11px;
				font-weight: 700;
				letter-spacing: 0.8px;
				text-transform: uppercase;
			}
		}
		&__icon {
			display: inline-flex;
			align-items: center;
			justify-content: center;
			width: 28px;
			height: 28px;
			border-radius: 8px;
			color: var(--color-informative--onSurface);
			background: var(--color-informative--surface);

			:global(svg) {
				width: 15px;
				height: 15px;
			}
		}
		&__link {
			display: inline-flex;
			align-items: center;
			gap: 4px;
			border-radius: var(--radius-small);
			color: var(--color-interactive);
			font-size: 13px;
			font-weight: 600;
			text-decoration: none;

			&:hover {
				text-decoration: underline;
			}
			&:focus-visible {
				outline: 2px solid var(--color-focus);
				outline-offset: 2px;
			}
		}
		&__arrow {
			display: inline-flex;

			:global(svg) {
				width: 14px;
				height: 14px;
			}
		}

		&__figure {
			display: grid;
			gap: 4px;
		}
		&__value {
			color: var(--color-heading);
			font-size: 32px;
			font-weight: 800;
			letter-spacing: -1px;
			line-height: 1.15;
			font-variant-numeric: tabular-nums;
		}
		&__line {
			color: var(--color-text--secondary);
			font-size: 13px;
			font-weight: 500;

			strong {
				color: var(--color-critical);
				font-weight: 600;
			}
		}

		&__bar {
			display: flex;
			gap: 3px;
			height: 8px;
		}
		&__segment {
			flex-basis: 0;
			min-width: 6px;
			border-radius: 4px;

			&--current {
				background: var(--color-icon--secondary);
			}
			&--late1 {
				background: var(--color-warning);
			}
			&--late2 {
				background: var(--color-warning--onSurface);
			}
			&--late3 {
				background: var(--color-critical);
			}
			&--late4 {
				background: var(--color-critical--onSurface);
			}
		}

		&__key {
			display: grid;
			gap: 8px;
			margin: 0;

			div {
				display: flex;
				align-items: center;
				justify-content: space-between;
				gap: var(--space-base);
			}
			dt {
				display: flex;
				align-items: center;
				gap: 8px;
				color: var(--color-text--secondary);
				font-size: 13px;
				font-weight: 500;
			}
			dd {
				margin: 0;
				color: var(--color-heading);
				font-size: 13px;
				font-weight: 600;
				font-variant-numeric: tabular-nums;
			}
		}
		&__dot {
			width: 8px;
			height: 8px;
			flex: 0 0 auto;
			min-width: 0;
			border-radius: var(--radius-circle);
		}

		&__clients {
			display: grid;
			gap: 2px;
			padding: 14px 20px 8px;
			border-top: var(--border-base) solid var(--color-border);

			h3 {
				color: var(--color-text--secondary);
				font-size: 11px;
				font-weight: 700;
				letter-spacing: 0.8px;
				text-transform: uppercase;
			}
			ul {
				margin: 0;
				padding: 0;
				list-style: none;
			}
			a {
				display: flex;
				align-items: center;
				gap: 12px;
				padding: 10px 0;
				color: inherit;
				text-decoration: none;

				&:hover .home-owed__who strong {
					text-decoration: underline;
				}
				&:focus-visible {
					outline: 2px solid var(--color-focus);
					outline-offset: 2px;
				}
			}
		}
		&__who {
			display: grid;
			min-width: 0;
			flex: 1;
			gap: 2px;

			strong {
				overflow: hidden;
				color: var(--color-heading);
				font-size: 13px;
				font-weight: 600;
				text-overflow: ellipsis;
				white-space: nowrap;
			}
			span {
				overflow: hidden;
				color: var(--color-text--secondary);
				font-size: 12px;
				font-weight: 500;
				text-overflow: ellipsis;
				white-space: nowrap;
			}
		}
		&__amount {
			color: var(--color-heading);
			font-size: 13px;
			font-weight: 700;
			font-variant-numeric: tabular-nums;
		}
	}
</style>
