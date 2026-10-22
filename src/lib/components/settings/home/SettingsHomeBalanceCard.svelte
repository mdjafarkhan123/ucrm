<script lang="ts">
	import Button from '$lib/components/ui/Button.svelte';
	import IconTile from '$lib/components/ui/IconTile.svelte';
	import StatusBadge from '$lib/components/ui/StatusBadge.svelte';
	import walletIcon from '@tabler/icons/outline/wallet.svg?raw';
	import plusIcon from '@tabler/icons/outline/plus.svg?raw';
	import type { SmsUsageHome } from '$lib/communications/sms-usage';

	// The texting and email balance (Pencil: Batch 63, Balance card): what can be spent now, what this
	// month has used, and the way to ask for a top-up, which happens on the balance page.
	let {
		usage,
		href
	}: {
		/** Undefined while it loads. */
		usage: SmsUsageHome | undefined;
		href: string;
	} = $props();

	const money = (minor: number) => `$${(Math.abs(minor) / 100).toFixed(2)}`;
	const state = $derived(
		usage
			? usage.availability.state === 'available'
				? { label: 'Enough', tone: 'success' as const }
				: usage.availability.state === 'zero_balance'
					? { label: 'Empty', tone: 'critical' as const }
					: { label: 'Paused', tone: 'warning' as const }
			: null
	);
	const used = $derived(
		usage
			? usage.usage_summary.retail_charge_minor + usage.email_usage_summary.retail_charge_minor
			: 0
	);
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<section class="home-balance" aria-labelledby="settings-balance-title">
	<div class="home-balance__head">
		<IconTile icon={walletIcon} tone="conversation" size={32} />
		<h2 id="settings-balance-title" class="home-balance__title">Texting & email balance</h2>
		{#if state}<StatusBadge status={state.tone}>{state.label}</StatusBadge>{/if}
	</div>
	<div class="home-balance__amount-row">
		<p class="home-balance__amount">{usage ? money(usage.balance.spendable_balance_minor) : '—'}</p>
		<Button {href} variant="secondary" size="small"
			><span aria-hidden="true">{@html plusIcon}</span>Request top-up</Button
		>
	</div>
	<p class="home-balance__usage">
		{#if usage}
			{money(used)} used this month{#if usage.balance.reserved_balance_minor > 0}
				· {money(usage.balance.reserved_balance_minor)} held for texts sending now{/if}
		{:else}
			Checking your balance…
		{/if}
	</p>
</section>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.home-balance {
		display: flex;
		flex-direction: column;
		gap: 10px;
		padding: 18px var(--space-medium);
		background: var(--color-surface);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-large);

		&__head {
			display: flex;
			align-items: center;
			gap: var(--space-slim);
		}
		&__title {
			flex: 1;
			color: var(--color-heading);
			font-size: var(--typography--fontSize-base);
			font-weight: 600;
		}
		&__amount-row {
			display: flex;
			align-items: center;
			justify-content: space-between;
			gap: var(--space-base);
		}
		&__amount {
			color: var(--color-heading);
			font-size: var(--typography--fontSize-stat);
			font-weight: 700;
			letter-spacing: -0.8px;
		}
		&__usage {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-base);
		}
	}
</style>
