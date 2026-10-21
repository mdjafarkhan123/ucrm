<script lang="ts">
	import MoneyFeatureCard from './MoneyFeatureCard.svelte';
	import lockIcon from '@tabler/icons/outline/lock.svg?raw';

	// Saved quote figures use the shared money summary. The server provides every amount and the page
	// owns permission checks; this adapter only formats its cost and profit breakdown.
	let {
		eyebrow = 'Estimated profit',
		costMinor,
		profitMinor,
		revenueMinor,
		marginBasisPoints,
		note,
		currencyCode = 'USD',
		locale = 'en-US'
	}: {
		eyebrow?: string;
		costMinor: number;
		profitMinor: number;
		/** What the work sells for before tax; the bar is cost and profit as shares of it. */
		revenueMinor: number;
		marginBasisPoints: number | null;
		/** The line under the figure. Defaults to a plain statement of the revenue it is measured on. */
		note?: string;
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

	const loss = $derived(profitMinor < 0);
	// A bar that cannot be drawn honestly (no revenue, or a loss) shows one full cost segment instead.
	const shares = $derived.by(() => {
		if (revenueMinor <= 0 || loss) return { cost: 100, profit: 0 };
		const cost = Math.min(100, Math.max(0, Math.round((costMinor / revenueMinor) * 100)));
		return { cost, profit: 100 - cost };
	});
	const marginText = $derived(
		marginBasisPoints === null ? null : `${Math.round(marginBasisPoints / 100)}% margin`
	);
	const breakdown = $derived([
		{
			label: 'Item cost',
			value: format(costMinor),
			share: costMinor,
			percent: `${shares.cost}%`,
			tone: 'items' as const
		},
		{
			label: loss ? 'Estimated loss' : 'Estimated profit',
			value: format(profitMinor),
			share: Math.max(0, profitMinor),
			percent: loss ? undefined : `${shares.profit}%`,
			tone: loss ? ('loss' as const) : ('profit' as const)
		}
	]);
	const noteText = $derived(
		note ?? `On ${format(revenueMinor)} of work, after discount, before tax`
	);
</script>

<MoneyFeatureCard
	{eyebrow}
	value={format(profitMinor)}
	note={noteText}
	{breakdown}
	badge="Team only"
	badgeIcon={lockIcon}
	pill={loss ? 'Losing money' : (marginText ?? undefined)}
	record
	summary
	{loss}
/>
