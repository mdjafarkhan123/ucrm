<script module lang="ts">
	import type { JobBillingSummary, JobCosting } from '$lib/jobs/api';
	import type { InvoiceMoneyContext } from '$lib/invoices/api';

	export type RecordMoneyJob = {
		kind: 'job';
		/** Null without jobs.view_cost. */
		costing: JobCosting | null;
		/** Null without invoice money rights. */
		billing: JobBillingSummary | null;
		/** What the job sells for after discount, before tax; null without jobs.view_price. */
		revenueMinor: number | null;
		discounted: boolean;
	};

	export type RecordMoneyQuote = {
		kind: 'quote';
		/** After discount, before tax. */
		revenueMinor: number;
		/** Null without quotes.view_cost. */
		costMinor: number | null;
		profitMinor: number | null;
		totalMinor: number;
		taxMinor: number;
		taxName: string | null;
		depositMinor: number;
		discounted: boolean;
	};

	export type RecordMoneyInvoice = {
		kind: 'invoice';
		subtotalMinor: number;
		discountMinor: number;
		taxMinor: number;
		taxName: string | null;
		totalMinor: number;
		remainingMinor: number;
		paidMinor: number;
		/** False once the bill is voided, written off or replaced: nothing is left to collect on it. */
		collectable: boolean;
		dueText: string | null;
		context: InvoiceMoneyContext | null;
		clientBalanceMinor: number | null;
	};
</script>

<script lang="ts">
	import { createQuery } from '@tanstack/svelte-query';
	import type { Snippet } from 'svelte';
	import MoneyFeatureCard, {
		type MoneyBreakdownPart,
		type MoneyDetailRow
	} from '$lib/components/work/MoneyFeatureCard.svelte';
	import { fetchMoneyAccess, moneyAccessKey } from '$lib/records/money-access';
	import lockIcon from '@tabler/icons/outline/lock.svg?raw';
	import eyeOffIcon from '@tabler/icons/outline/eye-off.svg?raw';
	import calendarIcon from '@tabler/icons/outline/calendar-due.svg?raw';
	import receiptIcon from '@tabler/icons/outline/receipt.svg?raw';
	import alertIcon from '@tabler/icons/outline/alert-triangle.svg?raw';

	// The money summary card (design skill `cards.md` → Money summary card, Pencil `vIjf0`) at the top of a
	// saved job, quote or invoice's rail. The server sends every figure and applies every permission; this
	// adapter only chooses what the card leads with for each record and formats it. The New pages use
	// `DraftMoneyCard`, which previews the same card from the lines being edited.
	let {
		record,
		currencyCode = 'USD',
		locale = 'en-US',
		children
	}: {
		record: RecordMoneyJob | RecordMoneyQuote | RecordMoneyInvoice;
		currencyCode?: string;
		locale?: string;
		/** Extra content at the card's foot, such as the invoice's Add deposit button. */
		children?: Snippet;
	} = $props();

	// The business's target margin; the card's pill says when a profit falls below it.
	const accessQuery = createQuery(() => ({
		queryKey: moneyAccessKey,
		queryFn: fetchMoneyAccess,
		staleTime: 5 * 60_000
	}));
	const targetPercent = $derived(
		accessQuery.data?.target_margin_basis_points == null
			? null
			: Math.round(accessQuery.data.target_margin_basis_points / 100)
	);

	const exact = $derived(
		new Intl.NumberFormat(locale, { style: 'currency', currency: currencyCode })
	);
	const whole = $derived(
		new Intl.NumberFormat(locale, {
			style: 'currency',
			currency: currencyCode,
			maximumFractionDigits: 0
		})
	);
	const formatExact = (minor: number) => exact.format(minor / 100);
	const formatWhole = (minor: number) => whole.format(minor / 100);
	const percentOf = (part: number, of: number) =>
		of > 0 ? `${Math.round((part / of) * 100)}%` : undefined;

	type Pill = { text: string; tone: 'profit' | 'warning' | 'loss' };
	function marginPill(profitMinor: number, revenueMinor: number): Pill | null {
		if (revenueMinor <= 0) return null;
		if (profitMinor < 0) return { text: 'Losing money', tone: 'loss' };
		const margin = Math.round((profitMinor / revenueMinor) * 100);
		if (targetPercent !== null && margin < targetPercent)
			return { text: `${margin}% · target ${targetPercent}%`, tone: 'warning' };
		return { text: `${margin}% margin`, tone: 'profit' };
	}

	function profitNote(profitMinor: number, revenueMinor: number, discounted: boolean) {
		if (revenueMinor <= 0) return 'Nothing priced yet';
		if (profitMinor < 0)
			return `On ${formatWhole(revenueMinor)} of work — costs are ${formatWhole(-profitMinor)} more`;
		return `On ${formatWhole(revenueMinor)} of work${discounted ? ', after discount' : ''}, before tax`;
	}

	// Bar order is fixed by the design: item cost · expenses · labor · profit (or loss).
	function profitParts(
		costs: { label: string; minor: number; tone: 'items' | 'expenses' | 'labor' }[],
		profitMinor: number,
		revenueMinor: number,
		profitLabel: string
	): MoneyBreakdownPart[] {
		const parts: MoneyBreakdownPart[] = costs.map((cost) => ({
			label: cost.label,
			value: formatWhole(cost.minor),
			share: cost.minor,
			percent: percentOf(cost.minor, revenueMinor),
			tone: cost.tone
		}));
		parts.push(
			profitMinor < 0
				? {
						label: 'Loss',
						value: formatWhole(profitMinor),
						share: -profitMinor,
						percent: percentOf(profitMinor, revenueMinor),
						tone: 'loss'
					}
				: {
						label: profitLabel,
						value: formatWhole(profitMinor),
						share: profitMinor,
						percent: percentOf(profitMinor, revenueMinor),
						tone: 'profit'
					}
		);
		return parts;
	}

	const hidden: MoneyDetailRow = {
		label: 'Cost and profit show only to people allowed to see costs.',
		value: '',
		icon: eyeOffIcon
	};

	type Card = {
		eyebrow: string;
		value?: string;
		note?: string;
		breakdown?: MoneyBreakdownPart[];
		details?: MoneyDetailRow[];
		emptyBar?: boolean;
		badge?: string;
		badgeIcon?: string;
		pill?: Pill | null;
		paidPill?: string;
		footnote?: string;
	};

	function jobCard(job: RecordMoneyJob): Card | null {
		const { costing, billing } = job;
		const invoiced: MoneyDetailRow[] = [];
		if (billing && billing.invoice_count > 0) {
			invoiced.push({
				label: 'Invoiced',
				value:
					job.revenueMinor !== null
						? `${formatWhole(billing.invoiced_minor)} of ${formatWhole(job.revenueMinor)}`
						: formatWhole(billing.invoiced_minor),
				icon: receiptIcon
			});
			if (billing.owed_minor > 0)
				invoiced.push({ label: 'Still owed', value: formatExact(billing.owed_minor) });
		}

		if (!costing) {
			if (job.revenueMinor === null) return null;
			return {
				eyebrow: 'Job total',
				value: formatExact(job.revenueMinor),
				note: job.discounted
					? 'Job subtotal after discount, before tax'
					: 'Job subtotal, before discount and tax',
				details: [...invoiced, hidden]
			};
		}

		const open = !costing.job_closed;
		const hours = costing.labor_minutes / 60;
		const laborLabel =
			costing.labor_minutes > 0
				? `Labor · ${Number.isInteger(hours) ? hours : hours.toFixed(1)} h`
				: 'Labor';
		const costs = [
			{ label: 'Item cost', minor: costing.item_cost_minor, tone: 'items' as const },
			{ label: 'Expenses', minor: costing.expense_cost_minor, tone: 'expenses' as const },
			{ label: laborLabel, minor: costing.labor_cost_minor, tone: 'labor' as const }
		];
		const notes: string[] = [];
		if (costing.unrated_labor_count > 0)
			notes.push(
				`${costing.unrated_labor_count === 1 ? 'One time entry has' : `${costing.unrated_labor_count} time entries have`} no hourly cost set, so those hours are not in the labor figure.`
			);
		if (costing.labor_line_and_time)
			notes.push(
				'This job has a labor line item and tracked time. Both are counted here — remove one if it is double counting.'
			);

		if (costing.costing_basis !== 'one_off') {
			// A recurring agreement never ends, so it is measured over the last 30 days, with the dates named.
			const asLocalDate = (text: string) => {
				const [year, month, day] = text.split('-').map(Number);
				return new Date(year, month - 1, day);
			};
			const day = new Intl.DateTimeFormat(locale, { month: 'short', day: 'numeric' });
			const window = `${day.format(asLocalDate(costing.window_start))} – ${day.format(asLocalDate(costing.window_end))}`;
			const units =
				costing.unit_kind === 'visits'
					? costing.unit_count === 1
						? '1 completed visit'
						: `${costing.unit_count} completed visits`
					: costing.unit_count === 1
						? '1 billing period'
						: `${costing.unit_count} billing periods`;
			if (costing.revenue_minor === null || costing.profit_minor === null) {
				notes.unshift(
					'This job is billed manually, so these 30 days have no billing period to price. The costs are real; there is no revenue to set them against until the work is billed.'
				);
				return {
					eyebrow: 'Costs · last 30 days',
					value: formatWhole(costing.total_cost_minor),
					note: `${window} · ${units}`,
					breakdown: costs
						.filter((cost) => cost.minor > 0)
						.map((cost) => ({
							label: cost.label,
							value: formatWhole(cost.minor),
							share: cost.minor,
							tone: cost.tone
						})),
					emptyBar: costing.total_cost_minor === 0,
					details: invoiced,
					badge: 'Team only',
					badgeIcon: lockIcon,
					footnote: notes.join(' ')
				};
			}
			return {
				eyebrow: 'Profit · last 30 days',
				value: formatWhole(costing.profit_minor),
				note: `On ${formatWhole(costing.revenue_minor)} of work · ${window} · ${units}`,
				breakdown: profitParts(costs, costing.profit_minor, costing.revenue_minor, 'Profit'),
				emptyBar: costing.revenue_minor <= 0,
				details: invoiced,
				badge: 'Team only',
				badgeIcon: lockIcon,
				pill: marginPill(costing.profit_minor, costing.revenue_minor),
				footnote: notes.join(' ') || undefined
			};
		}

		const profitLabel = open ? 'Profit so far' : 'Final profit';
		const priced = costing.revenue_minor > 0;
		return {
			eyebrow: profitLabel,
			value: formatWhole(costing.profit_minor),
			note: profitNote(costing.profit_minor, costing.revenue_minor, job.discounted),
			breakdown: priced
				? profitParts(costs, costing.profit_minor, costing.revenue_minor, profitLabel)
				: [],
			emptyBar: !priced,
			details: invoiced,
			badge: 'Team only',
			badgeIcon: lockIcon,
			pill: marginPill(costing.profit_minor, costing.revenue_minor),
			footnote:
				[
					open && priced ? 'Labor and expenses come off the profit as your crew logs them.' : '',
					...notes
				]
					.filter(Boolean)
					.join(' ') || undefined
		};
	}

	function quoteCard(quote: RecordMoneyQuote): Card {
		const taxed = quote.taxMinor > 0;
		const details: MoneyDetailRow[] = [
			{
				label: taxed ? `Client pays, with ${quote.taxName ?? 'tax'}` : 'Client pays',
				value: formatExact(quote.totalMinor)
			}
		];
		if (quote.depositMinor > 0) {
			const share = percentOf(quote.depositMinor, quote.totalMinor);
			details.push({
				label: share ? `Deposit on approval · ${share}` : 'Deposit on approval',
				value: formatExact(quote.depositMinor)
			});
		}

		if (quote.costMinor === null || quote.profitMinor === null) {
			return {
				eyebrow: 'Quote total',
				value: formatExact(quote.revenueMinor),
				note: quote.discounted
					? 'Quote subtotal after discount, before tax'
					: 'Quote subtotal, before discount and tax',
				details: [...details, hidden]
			};
		}

		const priced = quote.revenueMinor > 0;
		return {
			eyebrow: 'Estimated profit',
			value: formatWhole(quote.profitMinor),
			note: profitNote(quote.profitMinor, quote.revenueMinor, quote.discounted),
			breakdown: priced
				? profitParts(
						[{ label: 'Cost', minor: quote.costMinor, tone: 'items' }],
						quote.profitMinor,
						quote.revenueMinor,
						'Estimated profit'
					)
				: [],
			emptyBar: !priced,
			details,
			badge: 'Team only',
			badgeIcon: lockIcon,
			pill: marginPill(quote.profitMinor, quote.revenueMinor)
		};
	}

	function invoiceCard(invoice: RecordMoneyInvoice): Card {
		const context = invoice.context;
		const depositMinor = context?.deposit_applied_minor ?? 0;
		const thisMinor = invoice.subtotalMinor - invoice.discountMinor;
		const paidPercent =
			invoice.totalMinor > 0 ? Math.round((invoice.paidMinor / invoice.totalMinor) * 100) : 0;

		const less =
			invoice.paidMinor <= 0
				? ''
				: depositMinor >= invoice.paidMinor
					? `, less the ${formatWhole(depositMinor)} deposit`
					: `, less ${formatWhole(invoice.paidMinor)} paid`;
		const note = `${formatWhole(invoice.totalMinor)} invoice${invoice.taxMinor > 0 ? `, with ${invoice.taxName ?? 'tax'}` : ''}${less}`;

		// The bar shows this bill's share of its job when it comes from exactly one job; any other bill shows
		// what has been paid of it.
		let breakdown: MoneyBreakdownPart[] = [];
		const jobRevenue = context?.job_revenue_minor ?? null;
		if (context && jobRevenue !== null && jobRevenue > 0 && thisMinor > 0) {
			const before = Math.max(0, context.billed_before_minor ?? 0);
			const rest = Math.max(0, jobRevenue - before - thisMinor);
			if (before > 0)
				breakdown.push({
					label: 'Billed before',
					value: formatWhole(before),
					share: before,
					percent: percentOf(before, jobRevenue),
					tone: 'neutral'
				});
			breakdown.push({
				label:
					rest > 0
						? 'This invoice'
						: before > 0
							? 'This invoice · final'
							: 'This invoice · whole job',
				value: formatWhole(thisMinor),
				share: thisMinor,
				percent: percentOf(thisMinor, jobRevenue),
				tone: 'success'
			});
			if (rest > 0)
				breakdown.push({
					label: 'Rest of the job',
					value: formatWhole(rest),
					share: rest,
					percent: percentOf(rest, jobRevenue),
					tone: 'muted'
				});
		} else if (invoice.totalMinor > 0 && invoice.collectable) {
			breakdown = [
				{
					label: 'Paid',
					value: formatExact(invoice.paidMinor),
					share: invoice.paidMinor,
					tone: 'success',
					percent: `${paidPercent}%`
				},
				{
					label: 'Balance',
					value: formatExact(invoice.remainingMinor),
					share: invoice.remainingMinor,
					tone: 'muted',
					percent: `${100 - paidPercent}%`
				}
			];
		}

		const details: MoneyDetailRow[] = [];
		if (depositMinor > 0)
			details.push({ label: 'Deposit applied', value: `−${formatExact(depositMinor)}` });
		// Only lines billed from a job line carry a cost; a bill with none has no profit to state.
		if (context?.cost_minor != null && context.cost_minor > 0 && thisMinor > 0) {
			const profit = thisMinor - context.cost_minor;
			details.push({
				label: 'Profit · team only',
				value: `${formatWhole(profit)} · ${Math.round((profit / thisMinor) * 100)}%`,
				icon: lockIcon,
				tone: profit < 0 ? 'loss' : 'profit'
			});
		}
		if (invoice.clientBalanceMinor !== null)
			details.push({
				label: 'Client account balance',
				value: formatExact(invoice.clientBalanceMinor)
			});

		return {
			eyebrow: 'Balance due',
			value: formatExact(invoice.remainingMinor),
			note,
			breakdown,
			details,
			badge: invoice.dueText ?? undefined,
			badgeIcon: invoice.dueText?.endsWith('overdue') ? alertIcon : calendarIcon,
			paidPill: paidPercent > 0 ? `${paidPercent}% paid` : undefined
		};
	}

	const card = $derived(
		record.kind === 'job'
			? jobCard(record)
			: record.kind === 'quote'
				? quoteCard(record)
				: invoiceCard(record)
	);
</script>

{#if card}
	<MoneyFeatureCard
		eyebrow={card.eyebrow}
		value={card.value}
		note={card.note}
		breakdown={card.breakdown}
		details={card.details}
		emptyBar={card.emptyBar}
		badge={card.badge}
		badgeIcon={card.badgeIcon}
		pill={card.pill?.text ?? card.paidPill}
		pillTone={card.pill?.tone}
		footnote={card.footnote}
		loss={card.pill?.tone === 'loss'}
		record
		summary
		{children}
	/>
{/if}
