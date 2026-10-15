<script lang="ts">
	import ProfitFeatureCard, {
		type ProfitPart
	} from '$lib/components/work/ProfitFeatureCard.svelte';

	// The Classic quote page's featured card (classic.pen "Profit card"): the estimate the quote's own
	// version already carries — cost, estimated profit and margin — measured against the work after the
	// discount and before tax. It formats money and never adds it up beyond splitting the bar.
	let {
		subtotalMinor,
		discountMinor = 0,
		costMinor,
		profitMinor,
		marginBasisPoints = null,
		currencyCode = 'USD',
		locale = 'en-US'
	}: {
		subtotalMinor: number;
		discountMinor?: number;
		costMinor: number;
		profitMinor: number | null;
		marginBasisPoints?: number | null;
		currencyCode?: string;
		locale?: string;
	} = $props();

	const money = $derived(
		new Intl.NumberFormat(locale, {
			style: 'currency',
			currency: currencyCode,
			maximumFractionDigits: 0
		})
	);
	const format = (minor: number) => money.format(minor / 100);

	const workMinor = $derived(Math.max(0, subtotalMinor - discountMinor));
	const margin = $derived(
		marginBasisPoints === null ? null : `${Math.round(marginBasisPoints / 100)}% margin`
	);

	// When the cost runs past the work the bar is measured against the cost instead, so it still fills
	// exactly once and profit simply has no segment.
	const parts = $derived.by<ProfitPart[]>(() => {
		const profit = profitMinor ?? 0;
		const base = Math.max(workMinor, costMinor + Math.max(0, profit), 1);
		const percent = (minor: number) => (workMinor ? Math.round((minor / workMinor) * 100) : null);
		return [
			{
				key: 'cost',
				label: 'Cost',
				tone: 'amber',
				amount: format(costMinor),
				share: costMinor / base,
				percent: percent(costMinor)
			},
			{
				key: 'profit',
				label: 'Estimated profit',
				tone: 'green',
				amount: format(profit),
				share: Math.max(0, profit) / base,
				percent: percent(profit)
			}
		];
	});
</script>

<ProfitFeatureCard
	label="Quote profit"
	eyebrow="Estimated profit"
	value={profitMinor === null ? '—' : format(profitMinor)}
	loss={(profitMinor ?? 0) < 0}
	{margin}
	subline={`On ${format(workMinor)} of work, ${discountMinor > 0 ? 'after discount, ' : ''}before tax`}
	{parts}
/>
