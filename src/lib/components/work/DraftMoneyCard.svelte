<script lang="ts">
	import { createQuery } from '@tanstack/svelte-query';
	import MoneyFeatureCard, {
		type MoneyBreakdownPart,
		type MoneyDetailRow
	} from '$lib/components/work/MoneyFeatureCard.svelte';
	import { fetchMoneyAccess, moneyAccessKey } from '$lib/records/money-access';
	import type { RequestPricingLineInput } from '$lib/quotes/api';
	import lockIcon from '@tabler/icons/outline/lock.svg?raw';
	import calendarIcon from '@tabler/icons/outline/calendar-due.svg?raw';
	import eyeOffIcon from '@tabler/icons/outline/eye-off.svg?raw';

	// The money summary card (design skill `cards.md` → Money summary card, Pencil `vIjf0`) on a New job,
	// quote or invoice, before anything is saved. Every line in the editor already carries its price and unit
	// cost, so this previews the same arithmetic the line editor shows; the database works out the real
	// figures, tax included, when the record saves. Cost and profit appear only for someone allowed to see
	// cost, and a margin below the business's target says so.
	let {
		kind,
		lines,
		subtotalMinor,
		discountMinor = 0,
		taxMinor = null,
		taxLabel = null,
		dueText = null,
		jobTotalMinor = null,
		currencyCode = 'USD',
		locale = 'en-US'
	}: {
		kind: 'job' | 'quote' | 'invoice';
		lines: RequestPricingLineInput[];
		/** The editor's running subtotal of required priced lines. */
		subtotalMinor: number;
		/** A discount chosen on the form, already worked out against the subtotal. */
		discountMinor?: number;
		/** The tax a chosen rate comes to, when the form knows it; null leaves the client total before tax. */
		taxMinor?: number | null;
		/** The tax's own name, e.g. "GST". */
		taxLabel?: string | null;
		/** Invoice: the due date chip, e.g. "Due in 14 days". */
		dueText?: string | null;
		/** Invoice billed from a job: the job's own total, so this bill's share of it can be drawn. */
		jobTotalMinor?: number | null;
		currencyCode?: string;
		locale?: string;
	} = $props();

	const accessQuery = createQuery(() => ({
		queryKey: moneyAccessKey,
		queryFn: fetchMoneyAccess,
		staleTime: 5 * 60_000
	}));
	const canSeeCost = $derived(accessQuery.data?.can_see_cost[kind] ?? false);
	const targetBasisPoints = $derived(accessQuery.data?.target_margin_basis_points ?? null);

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

	// Optional add-ons and text rows are not part of the price, so they carry no cost either.
	const costMinor = $derived(
		lines.reduce(
			(sum, line) =>
				(line.line_kind ?? 'priced') === 'priced' &&
				(line.selection_kind ?? 'required') === 'required'
					? sum + Math.round(line.quantity * line.unit_cost_minor)
					: sum,
			0
		)
	);
	const revenueMinor = $derived(Math.max(0, subtotalMinor - discountMinor));
	const profitMinor = $derived(revenueMinor - costMinor);
	const marginPercent = $derived(
		revenueMinor > 0 ? Math.round((profitMinor / revenueMinor) * 100) : 0
	);
	const targetPercent = $derived(
		targetBasisPoints === null ? null : Math.round(targetBasisPoints / 100)
	);
	const priced = $derived(revenueMinor > 0);
	const loss = $derived(priced && profitMinor < 0);

	const pill = $derived.by((): { text: string; tone: 'profit' | 'warning' | 'loss' } | null => {
		if (!priced) return null;
		if (loss) return { text: 'Losing money', tone: 'loss' };
		if (targetPercent !== null && marginPercent < targetPercent)
			return { text: `${marginPercent}% · target ${targetPercent}%`, tone: 'warning' };
		return { text: `${marginPercent}% margin`, tone: 'profit' };
	});

	const share = (part: number) =>
		revenueMinor > 0 ? `${Math.round((part / revenueMinor) * 100)}%` : undefined;

	const profitBreakdown = $derived.by((): MoneyBreakdownPart[] => {
		if (!priced) return [];
		const costLabel = kind === 'job' ? 'Item cost' : 'Cost';
		const profitLabel = kind === 'job' ? 'Projected profit' : 'Estimated profit';
		return [
			{
				label: costLabel,
				value: formatWhole(costMinor),
				share: costMinor,
				percent: share(costMinor),
				tone: 'items'
			},
			loss
				? {
						label: 'Loss',
						value: formatWhole(profitMinor),
						share: -profitMinor,
						percent: share(profitMinor),
						tone: 'loss'
					}
				: {
						label: profitLabel,
						value: formatWhole(profitMinor),
						share: profitMinor,
						percent: share(profitMinor),
						tone: 'profit'
					}
		];
	});

	const clientPaysLabel = $derived(
		taxMinor !== null && taxLabel ? `Client pays, with ${taxLabel}` : 'Client pays, before tax'
	);
	const clientPaysMinor = $derived(revenueMinor + (taxMinor ?? 0));

	// What the card leads with and what sits under the line, per record.
	const card = $derived.by(() => {
		if (kind === 'invoice') {
			const otherMinor = jobTotalMinor !== null ? Math.max(0, jobTotalMinor - subtotalMinor) : 0;
			const thisInvoice: MoneyBreakdownPart = {
				label: otherMinor > 0 ? 'This invoice' : 'This invoice · whole job',
				value: formatWhole(subtotalMinor),
				share: subtotalMinor,
				percent: `${Math.min(100, Math.round((subtotalMinor / Math.max(jobTotalMinor ?? 1, 1)) * 100))}%`,
				tone: 'success'
			};
			// Drawn only when the bill is part of one job; the rest of that job sits beside it in grey.
			const breakdown: MoneyBreakdownPart[] =
				jobTotalMinor !== null && jobTotalMinor > 0 && subtotalMinor > 0
					? otherMinor > 0
						? [
								{
									label: 'Rest of the job',
									value: formatWhole(otherMinor),
									share: otherMinor,
									percent: `${Math.round((otherMinor / jobTotalMinor) * 100)}%`,
									tone: 'neutral'
								},
								thisInvoice
							]
						: [thisInvoice]
					: [];
			const details: MoneyDetailRow[] =
				canSeeCost && priced
					? [
							{
								label: 'Profit · team only',
								value: `${formatWhole(profitMinor)} · ${marginPercent}%`,
								icon: lockIcon,
								tone: loss ? 'loss' : 'profit'
							}
						]
					: [];
			return {
				eyebrow: 'Balance due',
				value: formatExact(subtotalMinor),
				note:
					subtotalMinor > 0
						? 'Before tax; tax and deposits apply when you save'
						: 'Add a line to bill for',
				breakdown,
				details,
				emptyBar: breakdown.length === 0,
				badge: dueText ?? undefined,
				badgeIcon: calendarIcon,
				footnote: undefined as string | undefined
			};
		}

		const totalLabel = kind === 'job' ? 'Job total' : 'Quote total';
		if (!canSeeCost) {
			return {
				eyebrow: totalLabel,
				value: formatExact(revenueMinor),
				note:
					discountMinor > 0
						? `${kind === 'job' ? 'Job' : 'Quote'} subtotal after discount, before tax`
						: `${kind === 'job' ? 'Job' : 'Quote'} subtotal, before discount and tax`,
				breakdown: [] as MoneyBreakdownPart[],
				details: [
					{
						label: 'Cost and profit show only to people allowed to see costs.',
						value: '',
						icon: eyeOffIcon
					}
				] as MoneyDetailRow[],
				emptyBar: false,
				badge: undefined,
				badgeIcon: undefined,
				footnote: undefined as string | undefined
			};
		}

		const details: MoneyDetailRow[] =
			kind === 'job'
				? [{ label: 'Job total', value: formatExact(revenueMinor) }]
				: [{ label: clientPaysLabel, value: formatExact(clientPaysMinor) }];
		const note = !priced
			? 'Add a priced line to see your profit'
			: loss
				? `On ${formatWhole(revenueMinor)} of work — costs are ${formatWhole(-profitMinor)} more`
				: `On ${formatWhole(revenueMinor)} of work${discountMinor > 0 ? ', after discount' : ''}, before tax`;
		return {
			eyebrow: kind === 'job' ? 'Projected profit' : 'Estimated profit',
			value: formatWhole(profitMinor),
			note,
			breakdown: profitBreakdown,
			details,
			emptyBar: !priced,
			badge: 'Team only',
			badgeIcon: lockIcon,
			footnote:
				kind === 'job' && priced
					? 'Labour and expenses come off the profit as your crew logs them.'
					: undefined
		};
	});
</script>

<MoneyFeatureCard
	eyebrow={card.eyebrow}
	value={card.value}
	note={card.note}
	breakdown={card.breakdown}
	details={card.details}
	emptyBar={card.emptyBar}
	badge={card.badge}
	badgeIcon={card.badgeIcon}
	pill={kind !== 'invoice' && canSeeCost ? pill?.text : undefined}
	pillTone={pill?.tone}
	footnote={card.footnote}
	loss={kind !== 'invoice' && canSeeCost && loss}
	loading={accessQuery.isPending}
	record
	summary
/>
