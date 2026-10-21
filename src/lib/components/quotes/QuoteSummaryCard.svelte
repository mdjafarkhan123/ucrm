<script lang="ts">
	import MoneyFeatureCard from '$lib/components/work/MoneyFeatureCard.svelte';
	import lockIcon from '@tabler/icons/outline/lock.svg?raw';

	// What the quote comes to, read only. Every figure here is one the database worked out and sent back —
	// this card formats money, it never adds it up. Discount and Tax only appear once they are worth
	// something, so a quote with neither reads as Subtotal and Total, not as rows of zeros.
	//
	// Cost, estimated profit and margin are the business's own numbers. They arrive only for someone with
	// `quotes.view_cost`, and a card that was never given them cannot show them.
	let {
		subtotalMinor,
		discountMinor = 0,
		taxMinor = 0,
		totalMinor = null,
		discountLabel = null,
		taxLabel = null,
		costMinor = null,
		profitMinor = null,
		marginBasisPoints = null,
		currencyCode = 'USD',
		locale = 'en-US',
		title = 'Overview',
		draft = false
	}: {
		/** Null when this person may not see quote prices at all. */
		subtotalMinor: number | null;
		discountMinor?: number;
		taxMinor?: number;
		/** Falls back to the subtotal, which is what a quote with no discount or tax comes to. */
		totalMinor?: number | null;
		/** The customer-facing name of the discount, shown beside the amount taken off. */
		discountLabel?: string | null;
		taxLabel?: string | null;
		costMinor?: number | null;
		profitMinor?: number | null;
		marginBasisPoints?: number | null;
		currencyCode?: string;
		locale?: string;
		title?: string;
		draft?: boolean;
	} = $props();

	const money = $derived(
		new Intl.NumberFormat(locale, { style: 'currency', currency: currencyCode })
	);
	const total = $derived(totalMinor ?? subtotalMinor ?? 0);
	const showInternal = $derived(
		subtotalMinor !== null && (costMinor !== null || profitMinor !== null)
	);
	const marginText = $derived(
		marginBasisPoints === null ? '—' : `${(marginBasisPoints / 100).toFixed(1)}%`
	);
	const format = (minor: number) => money.format(minor / 100);
	const eyebrow = $derived(
		draft
			? 'Estimated profit'
			: showInternal
				? 'Estimated profit'
				: title === 'Overview'
					? 'Client pays'
					: title
	);
	const shownValue = $derived(
		subtotalMinor === null
			? '—'
			: profitMinor !== null
				? format(profitMinor)
				: draft
					? subtotalMinor === 0
						? format(0)
						: '—'
					: format(total)
	);
	const details = $derived(
		subtotalMinor === null
			? []
			: [
					...(draft ? [{ label: 'Quote subtotal', value: format(subtotalMinor ?? 0) }] : []),
					...(discountMinor > 0
						? [{ label: discountLabel || 'Discount', value: `−${format(discountMinor)}` }]
						: []),
					...(taxMinor > 0 ? [{ label: taxLabel || 'Tax', value: format(taxMinor) }] : []),
					...(showInternal && costMinor !== null
						? [{ label: 'Item cost', value: format(costMinor) }]
						: []),
					...(showInternal ? [{ label: 'Client pays', value: format(total) }] : [])
				]
	);
	const note = $derived(
		subtotalMinor === null
			? 'You do not have access to these prices.'
			: draft
				? subtotalMinor === 0
					? 'Save the quote to see your estimated profit.'
					: 'Profit and final totals are worked out when you save.'
				: showInternal
					? `On ${format((subtotalMinor ?? 0) - discountMinor)} of work, before tax`
					: 'Before discount and tax'
	);
</script>

<MoneyFeatureCard
	{eyebrow}
	value={shownValue}
	{note}
	{details}
	badge={draft || showInternal ? 'Team only' : undefined}
	badgeIcon={lockIcon}
	pill={showInternal ? `${marginText} margin` : undefined}
	loss={(profitMinor ?? 0) < 0}
	emptyBar={draft}
	record
	summary
/>
