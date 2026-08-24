<script lang="ts">
	import { createQuery } from '@tanstack/svelte-query';
	import { page } from '$app/state';
	import { resolve } from '$app/paths';
	import SidePanel from '$lib/components/layout/SidePanel.svelte';
	import ClientSummaryCard from '$lib/components/work/ClientSummaryCard.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import StageAgeChip from './StageAgeChip.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import OpportunityNextActionSection from './OpportunityNextActionSection.svelte';
	import OpportunityDetailsSection from './OpportunityDetailsSection.svelte';
	import OpportunityTasksSection from './OpportunityTasksSection.svelte';
	import OpportunityNotesSection from './OpportunityNotesSection.svelte';
	import { stageAge } from '$lib/pipeline/freshness';
	import type { BoardFormatting } from '$lib/pipeline/money';
	import type { OpportunityCard } from '$lib/pipeline/api';
	import { ALL_STAGE_LABELS, isAnyBoardStage } from '$lib/pipeline/stages';
	import { clientDetailKey, fetchClient } from '$lib/clients/api';
	import requestIcon from '@tabler/icons/outline/file-description.svg?raw';
	import quoteIcon from '@tabler/icons/outline/file-invoice.svg?raw';

	// The thin brief: enough to recognise the card and get to the record behind it, without leaving the
	// board. Tasks, notes, the summary, and the quote actions arrive in their own parts — none of them
	// have data yet, and an empty section that promises them would only be furniture.
	let {
		opportunity,
		formatting,
		canEdit,
		onClose,
		onUpdate
	}: {
		opportunity: OpportunityCard | null;
		formatting: BoardFormatting | null;
		// Whether this member may assign, reassign or clear the owner and edit value/dates. Read-only
		// otherwise — same permission the card's owner control gates on.
		canEdit: boolean;
		onClose: () => void;
		// Patches the caller's own held copy of the open card after a successful field edit — the board
		// behind the drawer refetches itself, but this snapshot does not.
		onUpdate: (patch: Partial<OpportunityCard>) => void;
	} = $props();

	const age = $derived(opportunity ? stageAge(opportunity.stage_entered_at) : null);
	const stageLabel = $derived(
		opportunity && isAnyBoardStage(opportunity.stage) ? ALL_STAGE_LABELS[opportunity.stage] : null
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
	const clientId = $derived(opportunity?.client?.id ?? null);
	const clientQuery = createQuery(() => ({
		queryKey: clientDetailKey(clientId ?? ''),
		queryFn: () => fetchClient(clientId ?? ''),
		enabled: clientId !== null
	}));

	const currentUserId = $derived(page.data.user?.id as string | undefined);
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

		<!-- Keyed by id so switching cards remounts this section — a mid-edit row resets by starting fresh
		     rather than by an effect syncing local edit state to a changed prop. -->
		{#key opportunity.id}
			<OpportunityNextActionSection {opportunity} {canEdit} {onUpdate} onConverted={onClose} />
			<OpportunityDetailsSection {opportunity} {formatting} {canEdit} {onUpdate} />
			<OpportunityTasksSection opportunityId={opportunity.id} {formatting} {canEdit} />
			<OpportunityNotesSection
				opportunityId={opportunity.id}
				hasClient={opportunity.client !== null}
				{currentUserId}
				{canEdit}
			/>
		{/key}

		{#if opportunity.request}
			<Button
				variant="secondary"
				href={resolve('/(app)/requests/[id]', { id: opportunity.request.id })}
			>
				<!-- eslint-disable-next-line svelte/no-at-html-tags -->
				<span class="brief__button-icon" aria-hidden="true">{@html requestIcon}</span>
				View request
			</Button>
		{:else if opportunity.quote}
			<Button
				variant="secondary"
				href={resolve('/(app)/quotes/[id]', { id: opportunity.quote.id })}
			>
				<!-- eslint-disable-next-line svelte/no-at-html-tags -->
				<span class="brief__button-icon" aria-hidden="true">{@html quoteIcon}</span>
				View quote
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
		padding: 6px 10px;
		border-radius: var(--radius-large);
		color: var(--color-heading);
		background: var(--color-inactive--surface);
		font-size: var(--typography--fontSize-small);
		font-weight: 600;
		line-height: 1;
	}
	.brief__button-icon :global(svg) {
		display: block;
		width: 16px;
		height: 16px;
	}
</style>
