<script lang="ts">
	import { createQuery } from '@tanstack/svelte-query';
	import { page } from '$app/state';
	import { resolve } from '$app/paths';
	import SidePanel from '$lib/components/layout/SidePanel.svelte';
	import ClientSummaryCard from '$lib/components/work/ClientSummaryCard.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import StageAgeChip from './StageAgeChip.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Banner from '$lib/components/ui/Banner.svelte';
	import Badge from '$lib/components/ui/Badge.svelte';
	import OpportunityNextActionSection from './OpportunityNextActionSection.svelte';
	import OpportunityDetailsSection from './OpportunityDetailsSection.svelte';
	import OpportunityTasksSection from './OpportunityTasksSection.svelte';
	import OpportunityNotesSection from './OpportunityNotesSection.svelte';
	import OpportunityContactActions from './OpportunityContactActions.svelte';
	import OpportunityCallsSection from './OpportunityCallsSection.svelte';
	import { inactivity, stageAge, type InactivityRules } from '$lib/pipeline/freshness';
	import type { BoardFormatting } from '$lib/pipeline/money';
	import type { OpportunityCard } from '$lib/pipeline/api';
	import { ALL_STAGE_LABELS, isAnyBoardStage } from '$lib/pipeline/stages';
	import { clientDetailKey, fetchClient } from '$lib/clients/api';
	import { quoteDeliveryFailureSentence } from '$lib/quotes/send';
	import requestIcon from '@tabler/icons/outline/file-description.svg?raw';
	import quoteIcon from '@tabler/icons/outline/file-invoice.svg?raw';

	// The thin brief: enough to recognise the card and get to the record behind it, without leaving the
	// board. Tasks, notes, the summary, and the quote actions arrive in their own parts — none of them
	// have data yet, and an empty section that promises them would only be furniture.
	let {
		opportunity,
		formatting,
		inactivityRules = null,
		canEdit,
		canMessage = false,
		onClose,
		onUpdate
	}: {
		opportunity: OpportunityCard | null;
		formatting: BoardFormatting | null;
		// The board's own warning rules, so the Brief and the card never disagree.
		inactivityRules?: InactivityRules | null;
		// Whether this member may assign, reassign or clear the owner and edit value/dates. Read-only
		// otherwise — same permission the card's owner control gates on.
		canEdit: boolean;
		// Whether Email and Text belong on this card: the inbox is in the plan and this member may send in it.
		canMessage?: boolean;
		onClose: () => void;
		// Patches the caller's own held copy of the open card after a successful field edit — the board
		// behind the drawer refetches itself, but this snapshot does not.
		onUpdate: (patch: Partial<OpportunityCard>) => void;
	} = $props();

	const age = $derived(opportunity ? stageAge(opportunity.stage_entered_at) : null);
	const quiet = $derived(opportunity ? inactivity(opportunity, inactivityRules) : null);
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
	// A plain `if`/`return`, not a ternary: checking resolve()'s own route-id type together with
	// `undefined` in one conditional expression is what tips TypeScript over its complexity limit
	// (svelte-check: "union type that is too complex to represent"). A separate return per branch,
	// against this explicit return type, checks each one on its own instead.
	const clientHref = $derived.by((): string | undefined => {
		if (!opportunity?.client) return undefined;
		return resolve('/(app)/clients/[id=uuid]', { id: opportunity.client.id });
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

	// Which card has the "How did the call go?" bar open. Tapping Call opens it; closing it puts it away, and
	// so does opening another card, because the bar belongs to the card it was opened on. Nothing is recorded
	// by this.
	let logOpenFor = $state<string | null>(null);
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
				<StageAgeChip label={age.label} description={age.description} />
			{/if}
			{#if quiet}
				<Badge status="critical" size="small">{quiet.label}</Badge>
			{/if}
		</div>

		{#if opportunity.quote?.delivery_failure}
			<!-- The quote stays sent and the card stays where it is. Sending it again to a working address is
			     what clears this, and that happens on the quote's own page. -->
			<Banner type="error">
				<strong>Delivery failed.</strong>
				{quoteDeliveryFailureSentence(opportunity.quote.delivery_failure)} The customer has not received
				this quote. Check the address, then send it again.
				{#snippet action()}
					<Button
						size="small"
						variant="secondary"
						href={resolve('/(app)/quotes/[id=uuid]', { id: opportunity.quote?.id ?? '' })}
					>
						Open quote
					</Button>
				{/snippet}
			</Banner>
		{/if}

		{#if opportunity.client && clientQuery.isPending}
			<LoadingSkeleton variant="card" label="Loading client details" />
		{:else}
			<ClientSummaryCard
				name={clientName}
				href={clientHref}
				addresses={[{ value: propertyLine, empty: 'No property on this work yet' }]}
				phone={clientQuery.data?.phone ?? null}
				email={clientQuery.data?.email ?? null}
			/>
			{#if opportunity.client && clientQuery.data}
				<OpportunityContactActions
					clientId={opportunity.client.id}
					{clientName}
					contacts={clientQuery.data.contact_methods}
					{canMessage}
					onCall={() => (logOpenFor = opportunity.id)}
				/>
			{/if}
		{/if}

		<!-- Keyed by id so switching cards remounts this section — a mid-edit row resets by starting fresh
		     rather than by an effect syncing local edit state to a changed prop. -->
		{#key opportunity.id}
			<OpportunityNextActionSection
				{opportunity}
				{formatting}
				{canEdit}
				{onUpdate}
				onConverted={onClose}
			/>
			<OpportunityDetailsSection {opportunity} {formatting} {canEdit} {onUpdate} />
			<OpportunityTasksSection
				opportunityId={opportunity.id}
				{formatting}
				{canEdit}
				onCompleted={() => onUpdate({ progress_at: new Date().toISOString() })}
			/>
			<OpportunityCallsSection
				opportunityId={opportunity.id}
				{clientName}
				{formatting}
				{canEdit}
				bind:logOpen={
					() => logOpenFor === opportunity.id, (open) => (logOpenFor = open ? opportunity.id : null)
				}
				{currentUserId}
				onLogged={(restartedProgress) => {
					if (restartedProgress) onUpdate({ progress_at: new Date().toISOString() });
				}}
			/>
			<OpportunityNotesSection
				opportunityId={opportunity.id}
				requestId={opportunity.request?.id ?? null}
				quoteId={opportunity.quote?.id ?? null}
				clientId={opportunity.client?.id ?? null}
				{currentUserId}
				{canEdit}
			/>
		{/key}

		{#if opportunity.request}
			<Button
				variant="secondary"
				href={resolve('/(app)/requests/[id=uuid]', { id: opportunity.request.id })}
			>
				<!-- eslint-disable-next-line svelte/no-at-html-tags -->
				<span class="brief__button-icon" aria-hidden="true">{@html requestIcon}</span>
				View request
			</Button>
		{:else if opportunity.quote}
			<Button
				variant="secondary"
				href={resolve('/(app)/quotes/[id=uuid]', { id: opportunity.quote.id })}
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
