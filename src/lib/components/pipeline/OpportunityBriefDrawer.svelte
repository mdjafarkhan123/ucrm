<script lang="ts">
	import { createQuery } from '@tanstack/svelte-query';
	import { resolve } from '$app/paths';
	import SidePanel from '$lib/components/layout/SidePanel.svelte';
	import ClientSummaryCard from '$lib/components/work/ClientSummaryCard.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import StageAgeChip from './StageAgeChip.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Avatar from '$lib/components/ui/Avatar.svelte';
	import { stageAge } from '$lib/pipeline/freshness';
	import { followUp, formatMoney, type BoardFormatting } from '$lib/pipeline/money';
	import type { OpportunityCard } from '$lib/pipeline/api';
	import { BOARD_STAGE_LABELS, isBoardStage } from '$lib/pipeline/stages';
	import { clientDetailKey, fetchClient } from '$lib/clients/api';
	import requestIcon from '@tabler/icons/outline/file-description.svg?raw';

	// The thin brief: enough to recognise the card and get to the record behind it, without leaving the
	// board. Tasks, notes, the summary, and the quote actions arrive in their own parts — none of them
	// have data yet, and an empty section that promises them would only be furniture.
	let {
		opportunity,
		formatting,
		onClose
	}: {
		opportunity: OpportunityCard | null;
		formatting: BoardFormatting | null;
		onClose: () => void;
	} = $props();

	const age = $derived(opportunity ? stageAge(opportunity.stage_entered_at) : null);
	const stageLabel = $derived(
		opportunity && isBoardStage(opportunity.stage) ? BOARD_STAGE_LABELS[opportunity.stage] : null
	);
	const clientName = $derived(
		opportunity?.client?.company_name?.trim() || opportunity?.client?.display_name || 'No client'
	);
	const propertyLine = $derived.by(() => {
		const property = opportunity?.property;
		if (!property) return null;
		return [property.address_line1, property.city, property.state_region, property.postal_code]
			.filter(Boolean)
			.join(', ');
	});

	// The board payload carries no contact details — phone and email live in a separate table, and
	// joining them onto every card would cost a join per column page for something only one open card
	// ever needs. The drawer loads the client itself, through the same cache entry the client detail
	// page uses, so a client the user already visited opens instantly. `OpportunityCard` warms this key
	// on hover and focus, so the fetch is usually already done by the time the click lands.
	// The four Part 2 fields, read only for now: the card menu and the editable details arrive with the
	// rest of Part 2. `estimated_value` is absent, not null, for a member who may not see money, so this
	// section simply has one row fewer for them.
	const canViewValue = $derived(opportunity ? 'estimated_value' in opportunity : false);
	const amount = $derived(
		formatting && opportunity ? formatMoney(opportunity.estimated_value, formatting) : null
	);
	const chase = $derived(
		formatting && opportunity ? followUp(opportunity.next_follow_up_on, formatting) : null
	);
	const closeOn = $derived(
		formatting && opportunity ? followUp(opportunity.expected_close_on, formatting) : null
	);

	const clientId = $derived(opportunity?.client?.id ?? null);
	const clientQuery = createQuery(() => ({
		queryKey: clientDetailKey(clientId ?? ''),
		queryFn: () => fetchClient(clientId ?? ''),
		enabled: clientId !== null
	}));
</script>

<SidePanel
	open={opportunity !== null}
	title={opportunity?.title ?? ''}
	subtitle={clientName}
	{onClose}
>
	{#if opportunity}
		<div class="brief__status">
			{#if stageLabel}<span class="brief__stage">{stageLabel}</span>{/if}
			{#if age}
				<StageAgeChip label={age.label} freshness={age.freshness} description={age.description} />
			{/if}
		</div>

		{#if opportunity.client && clientQuery.isPending}
			<LoadingSkeleton variant="card" label="Loading client details" />
		{:else}
			<ClientSummaryCard
				name={clientName}
				href={opportunity.client
					? resolve('/(app)/clients/[id]', { id: opportunity.client.id })
					: undefined}
				addresses={[{ value: propertyLine, empty: 'No property on this work yet' }]}
				phone={clientQuery.data?.phone ?? null}
				email={clientQuery.data?.email ?? null}
			/>
		{/if}

		<section class="brief__details" aria-labelledby="brief-details-heading">
			<h3 id="brief-details-heading" class="brief__details-heading">Opportunity details</h3>
			<dl class="brief__list">
				<div class="brief__row">
					<dt>Salesperson</dt>
					<dd>
						{#if opportunity.owner}
							<span class="brief__owner">
								<Avatar
									id={opportunity.owner.id}
									name={opportunity.owner.full_name}
									src={opportunity.owner.avatar_url}
									size="small"
								/>
								{opportunity.owner.full_name ?? 'No longer on the team'}
							</span>
						{:else}
							<span class="brief__blank">Unassigned</span>
						{/if}
					</dd>
				</div>
				{#if canViewValue}
					<div class="brief__row">
						<dt>Estimated value</dt>
						<dd>
							{#if amount}
								{amount}
							{:else}
								<span class="brief__blank">Not estimated yet</span>
							{/if}
						</dd>
					</div>
				{/if}
				<div class="brief__row">
					<dt>Expected close</dt>
					<dd>
						{#if closeOn}{closeOn.label}{:else}<span class="brief__blank">No date set</span>{/if}
					</dd>
				</div>
				<div class="brief__row">
					<dt>Next follow-up</dt>
					<dd>
						{#if chase}
							<span class={chase.overdue ? 'brief__overdue' : ''}>
								{chase.label}
								{#if chase.overdue}<span class="brief__overdue-word">Overdue</span>{/if}
							</span>
						{:else}
							<span class="brief__blank">No follow-up set</span>
						{/if}
					</dd>
				</div>
			</dl>
		</section>

		{#if opportunity.request}
			<Button
				variant="secondary"
				href={resolve('/(app)/requests/[id]', { id: opportunity.request.id })}
			>
				<!-- eslint-disable-next-line svelte/no-at-html-tags -->
				<span class="brief__button-icon" aria-hidden="true">{@html requestIcon}</span>
				View request
			</Button>
		{/if}
	{/if}
</SidePanel>

<style lang="scss">
	.brief__status {
		display: flex;
		align-items: center;
		gap: var(--space-small);
	}
	.brief__stage {
		padding: var(--space-smallest) var(--space-small);
		border-radius: var(--radius-large);
		color: var(--color-heading);
		background: var(--color-inactive--surface);
		font-size: var(--typography--fontSize-small);
		font-weight: 600;
		line-height: 1;
	}
	.brief__details {
		display: flex;
		flex-direction: column;
		gap: var(--space-small);
	}
	.brief__details-heading {
		color: var(--color-heading);
		font-size: var(--typography--fontSize-small);
		font-weight: 700;
		text-transform: uppercase;
		letter-spacing: 0.04em;
	}
	.brief__list {
		display: flex;
		flex-direction: column;
		gap: var(--space-small);
	}
	.brief__row {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-base);

		dt {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}
		dd {
			color: var(--color-text);
			font-size: var(--typography--fontSize-small);
			font-weight: 600;
			text-align: right;
		}
	}
	.brief__owner {
		display: inline-flex;
		align-items: center;
		gap: var(--space-small);
	}
	.brief__blank {
		color: var(--color-text--secondary);
		font-weight: 400;
	}
	.brief__overdue {
		color: var(--color-critical--onSurface);
	}
	.brief__overdue-word {
		text-transform: uppercase;
		&::before {
			content: '· ';
		}
		font-size: var(--typography--fontSize-smaller);
		letter-spacing: 0.04em;
	}
	.brief__button-icon :global(svg) {
		display: block;
		width: 16px;
		height: 16px;
	}
</style>
