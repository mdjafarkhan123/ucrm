<script lang="ts">
	import { useQueryClient } from '@tanstack/svelte-query';
	import StageAgeChip from './StageAgeChip.svelte';
	import Avatar from '$lib/components/ui/Avatar.svelte';
	import { stageAge } from '$lib/pipeline/freshness';
	import { followUp, formatMoney, type BoardFormatting } from '$lib/pipeline/money';
	import type { OpportunityCard } from '$lib/pipeline/api';
	import { clientDetailKey, fetchClient } from '$lib/clients/api';
	import calendarIcon from '@tabler/icons/outline/calendar-event.svg?raw';
	import bellIcon from '@tabler/icons/outline/bell.svg?raw';
	import alertIcon from '@tabler/icons/outline/alert-circle.svg?raw';

	// One card on the board. It is a real button, so the keyboard reaches it and a screen reader
	// announces it, and it carries no drag affordance of any kind — dragging arrives with the Quote
	// stages, and a card that looks draggable before then is a promise we cannot keep.
	let {
		opportunity,
		formatting,
		onOpen
	}: {
		opportunity: OpportunityCard;
		// Null until the board summary has answered. Money and dates wait for it rather than being
		// written the browser's way for a moment and then correcting themselves.
		formatting: BoardFormatting | null;
		onOpen: () => void;
	} = $props();

	const queryClient = useQueryClient();
	const age = $derived(stageAge(opportunity.stage_entered_at));
	const clientName = $derived(
		opportunity.client?.company_name?.trim() || opportunity.client?.display_name || 'No client'
	);
	// Absent when this member may not see money, null when nobody has estimated the work. Neither one is
	// a zero, so neither one prints.
	const amount = $derived(formatting ? formatMoney(opportunity.estimated_value, formatting) : null);
	const chase = $derived(formatting ? followUp(opportunity.next_follow_up_on, formatting) : null);
	const createdOn = $derived(
		new Date(opportunity.created_at).toLocaleDateString(undefined, {
			month: 'short',
			day: 'numeric'
		})
	);

	// The brief drawer needs the client's phone and email, which this card's payload does not carry.
	// Warming the same cache entry the client detail page uses means the drawer is usually already
	// holding it by the time the click lands.
	function warmClient() {
		const clientId = opportunity.client?.id;
		if (!clientId) return;
		void queryClient.prefetchQuery({
			queryKey: clientDetailKey(clientId),
			queryFn: () => fetchClient(clientId)
		});
	}
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<button
	type="button"
	class={`opportunity-card opportunity-card--${age.freshness}`}
	onclick={onOpen}
	onmouseenter={warmClient}
	onfocus={warmClient}
>
	<span class="opportunity-card__title">{opportunity.title}</span>
	<span class="opportunity-card__client">{clientName}</span>
	{#if amount}
		<span class="opportunity-card__amount">{amount}</span>
	{/if}
	<span class="opportunity-card__footer">
		<span class="opportunity-card__date">
			<span class="opportunity-card__icon" aria-hidden="true">{@html calendarIcon}</span>
			<span class="opportunity-card__spoken">Created </span>{createdOn}
		</span>
		<span class="opportunity-card__owner-and-age">
			{#if opportunity.owner}
				<span class="opportunity-card__owner">
					<Avatar
						id={opportunity.owner.id}
						name={opportunity.owner.full_name}
						src={opportunity.owner.avatar_url}
						size="small"
					/>
					<span class="opportunity-card__spoken">
						{opportunity.owner.full_name ?? 'Someone no longer on the team'} owns this
					</span>
				</span>
			{/if}
			<StageAgeChip label={age.label} freshness={age.freshness} description={age.description} />
		</span>
	</span>
	{#if chase}
		<span
			class={`opportunity-card__chase${chase.overdue ? ' opportunity-card__chase--overdue' : ''}`}
		>
			<span class="opportunity-card__icon" aria-hidden="true">
				{@html chase.overdue ? alertIcon : bellIcon}
			</span>
			{#if chase.overdue}<span class="opportunity-card__overdue">Overdue</span>{/if}
			<span class="opportunity-card__spoken">{chase.description}</span>
			<span aria-hidden="true">{chase.label}</span>
		</span>
	{/if}
</button>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.opportunity-card {
		display: flex;
		flex-direction: column;
		gap: var(--space-small);
		width: 100%;
		padding: var(--space-slim);
		border: var(--border-base) solid var(--color-border);
		border-left: var(--space-smallest) solid var(--card-edge, var(--color-border));
		border-radius: var(--radius-base);
		background: var(--color-surface);
		text-align: left;
		cursor: pointer;
		// A long column keeps loading pages, so the browser is told it may skip laying out and
		// painting the cards nobody has scrolled to. The reserved height keeps the scrollbar honest.
		content-visibility: auto;
		contain-intrinsic-size: auto 96px;
		transition:
			background var(--timing-base) ease-out,
			border-color var(--timing-base) ease-out;

		&:hover {
			background: var(--color-surface--hover);
		}

		&:focus-visible {
			outline: none;
			box-shadow: var(--shadow-focus);
		}
	}
	// The edge repeats what the age chip says, for the glance across a full column.
	.opportunity-card--fresh {
		--card-edge: var(--color-success);
	}
	.opportunity-card--steady {
		--card-edge: var(--color-border);
	}
	.opportunity-card--stale {
		--card-edge: var(--color-critical);
	}
	.opportunity-card__title {
		color: var(--color-heading);
		font-size: var(--typography--fontSize-base);
		font-weight: 600;
		line-height: var(--typography--lineHeight-tight);
	}
	.opportunity-card__client {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}
	.opportunity-card__amount {
		color: var(--color-heading);
		font-size: var(--typography--fontSize-base);
		font-weight: 700;
		font-variant-numeric: tabular-nums;
	}
	.opportunity-card__footer {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-small);
		margin-top: var(--space-smallest);
	}
	.opportunity-card__date {
		display: inline-flex;
		align-items: center;
		gap: 6px;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}
	.opportunity-card__icon :global(svg) {
		display: block;
		width: 16px;
		height: 16px;
	}
	.opportunity-card__owner-and-age {
		display: inline-flex;
		align-items: center;
		gap: var(--space-small);
	}
	.opportunity-card__owner {
		display: inline-flex;
		align-items: center;
	}
	// The chase line repeats what the icon and the word say, so red is never the only thing carrying it.
	.opportunity-card__chase {
		display: inline-flex;
		align-items: center;
		gap: 6px;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);

		&--overdue {
			color: var(--color-critical--onSurface);
			font-weight: 600;
		}
	}
	.opportunity-card__overdue {
		text-transform: uppercase;
		font-size: var(--typography--fontSize-smaller);
		letter-spacing: 0.04em;
	}
	.opportunity-card__spoken {
		position: absolute;
		width: 1px;
		height: 1px;
		overflow: hidden;
		clip-path: inset(50%);
		white-space: nowrap;
	}
</style>
