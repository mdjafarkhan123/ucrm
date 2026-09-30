<script lang="ts">
	import type {
		BillingAgreement,
		BillingUpcomingAgreement,
		OrganizationBilling
	} from '$lib/components/jafar/organization/types';
	import packageIcon from '@tabler/icons/outline/package.svg?raw';
	import Badge from '$lib/components/ui/Badge.svelte';
	import Banner from '$lib/components/ui/Banner.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import SectionBlock from '$lib/components/layout/SectionBlock.svelte';
	import DataTable, { type DataTableColumn } from '$lib/components/data-display/DataTable.svelte';
	import EmptyState from '$lib/components/data-display/EmptyState.svelte';
	import { formatDateTime, formatUsd } from './format';

	// Package builder P8b: the customer's agreed package on the Billing tab — current terms, a scheduled
	// change with its cancel, and every earlier set of terms (plan § Assignment and changes: historical
	// customer terms stay visible).
	let {
		billing,
		onChange,
		onCancelChange
	}: {
		billing: OrganizationBilling;
		onChange: () => void;
		onCancelChange: (agreement: BillingUpcomingAgreement) => void;
	} = $props();

	const current = $derived(billing.current_agreement);
	const scheduled = $derived(billing.upcoming_agreements[0] ?? null);

	const columns: DataTableColumn[] = [
		{ key: 'package', label: 'Package' },
		{ key: 'price', label: 'Price', align: 'end' },
		{ key: 'from', label: 'From' },
		{ key: 'how', label: 'How' },
		{ key: 'status', label: 'Status' }
	];

	const sourceLabels: Record<string, string> = {
		activation: 'Activation',
		package_change: 'Package change',
		correction: 'Correction',
		test_reset: 'Test setup'
	};

	function perInterval(value: 'month' | 'year') {
		return value === 'month' ? 'a month' : 'a year';
	}
	function status(agreement: BillingAgreement) {
		if (agreement.cancelled_at) return { label: 'Cancelled', tone: 'inactive' } as const;
		if (agreement.id === current?.id) return { label: 'Current', tone: 'success' } as const;
		if (new Date(agreement.effective_from) > new Date())
			return { label: 'Scheduled', tone: 'informative' } as const;
		return { label: 'Earlier', tone: 'inactive' } as const;
	}
</script>

<SectionBlock
	title="Package"
	icon={packageIcon}
	hint="The edition, price, and billing this customer agreed to. A new package normally starts at the next renewal."
>
	{#snippet actions()}
		<Button size="small" variant="secondary" disabled={!current} onclick={onChange}
			>Change package</Button
		>
	{/snippet}

	{#if !current}
		<EmptyState
			title="No package yet"
			description="A package is agreed when the organization is activated."
		/>
	{:else}
		<div class="billing-package__current">
			<div>
				<strong>{current.edition_name}</strong>
				<span>
					Edition {current.edition_number} · {formatUsd(current.agreed_price_usd_cents)}
					{perInterval(current.billing_interval)} · since {formatDateTime(current.effective_from)}
				</span>
			</div>
		</div>

		{#if scheduled}
			<div class="billing-package__scheduled">
				<div>
					<Badge status="informative" size="small">Scheduled</Badge>
					<p>
						Moves to <strong>{scheduled.edition_name}</strong> (edition {scheduled.edition_number})
						at
						{formatUsd(scheduled.agreed_price_usd_cents)}
						{perInterval(scheduled.billing_interval)} on {formatDateTime(scheduled.effective_from)}.
					</p>
				</div>
				<Button
					size="small"
					variant="tertiary"
					variation="destructive"
					onclick={() => onCancelChange(scheduled)}>Cancel change</Button
				>
			</div>
			{#if scheduled.over_limits.length}
				<Banner type="warning">
					<div>
						<strong>Over the new package's limits again.</strong> Everything in use keeps working,
						but sort these out before {formatDateTime(scheduled.effective_from)}:
						<ul class="billing-package__list">
							{#each scheduled.over_limits as row (row.allowance_key)}
								<li>
									{row.label}: {row.in_use} in use, the new package allows {row.limit} — remove
									{row.in_use - row.limit}.
								</li>
							{/each}
						</ul>
					</div>
				</Banner>
			{/if}
		{/if}

		{#if billing.agreement_history.length > 1}
			<DataTable
				caption="Package history"
				{columns}
				items={billing.agreement_history}
				rowId={(agreement) => agreement.id}
				isExpanded={(agreement) => Boolean(agreement.reason || agreement.cancel_reason)}
			>
				{#snippet row(agreement)}
					{@const badge = status(agreement)}
					<td class:billing-package__muted={agreement.cancelled_at}>
						<strong>{agreement.edition_name}</strong>
						<span class="billing-package__secondary">edition {agreement.edition_number}</span>
					</td>
					<td class="align-end billing-package__money">
						{formatUsd(agreement.agreed_price_usd_cents)}
						{perInterval(agreement.billing_interval)}
					</td>
					<td class="billing-package__secondary">{formatDateTime(agreement.effective_from)}</td>
					<td>{sourceLabels[agreement.source] ?? agreement.source}</td>
					<td><Badge status={badge.tone} size="small">{badge.label}</Badge></td>
				{/snippet}
				{#snippet rowDetail(agreement)}
					<ul class="billing-package__trail">
						{#if agreement.reason}
							<li>
								{agreement.reason}{agreement.actor_owner_email
									? ` — ${agreement.actor_owner_email}`
									: ''}
							</li>
						{/if}
						{#if agreement.cancelled_at}
							<li class="billing-package__trail-void">
								Cancelled {formatDateTime(agreement.cancelled_at)}: {agreement.cancel_reason}
							</li>
						{/if}
					</ul>
				{/snippet}
			</DataTable>
		{/if}
	{/if}
</SectionBlock>

<style lang="scss">
	.billing-package__current,
	.billing-package__scheduled {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-small) var(--space-base);
	}
	.billing-package__current > div {
		display: grid;
		gap: var(--space-smallest);
	}
	.billing-package__current strong {
		color: var(--color-heading);
		font-size: var(--typography--fontSize-larger);
	}
	.billing-package__current span,
	.billing-package__secondary {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}
	.billing-package__secondary {
		display: block;
	}
	.billing-package__scheduled {
		padding: var(--space-slim) var(--space-base);
		border-radius: var(--radius-base);
		background: var(--color-informative--surface);
	}
	.billing-package__scheduled > div {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: var(--space-small);
	}
	.billing-package__scheduled p {
		margin: 0;
		color: var(--color-informative--onSurface);
	}
	.billing-package__list {
		margin: var(--space-smallest) 0 0;
		padding-left: var(--space-large);
	}
	.billing-package__money {
		font-variant-numeric: tabular-nums;
		white-space: nowrap;
	}
	.billing-package__muted strong {
		color: var(--color-text--secondary);
		text-decoration: line-through;
	}
	.billing-package__trail {
		display: grid;
		gap: var(--space-smaller);
		margin: 0;
		padding: 0 0 0 var(--space-base);
		border-left: var(--border-thick, 2px) solid var(--color-border);
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		list-style: none;
	}
	.billing-package__trail-void {
		font-style: italic;
	}
</style>
