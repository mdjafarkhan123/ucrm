<script lang="ts">
	import { useQueryClient } from '@tanstack/svelte-query';
	import StageAgeChip from './StageAgeChip.svelte';
	import Avatar from '$lib/components/ui/Avatar.svelte';
	import Badge from '$lib/components/ui/Badge.svelte';
	import DropdownMenu from '$lib/components/ui/DropdownMenu.svelte';
	import OpportunityOwnerField from './OpportunityOwnerField.svelte';
	import MarkOpportunityLostDialog from './MarkOpportunityLostDialog.svelte';
	import { stageAge } from '$lib/pipeline/freshness';
	import { appointment, followUp, formatMoney, type BoardFormatting } from '$lib/pipeline/money';
	import { invalidatePipeline, type OpportunityCard } from '$lib/pipeline/api';
	import { clientDetailKey, fetchClient } from '$lib/clients/api';
	import calendarIcon from '@tabler/icons/outline/calendar-event.svg?raw';
	import bellIcon from '@tabler/icons/outline/bell.svg?raw';
	import alertIcon from '@tabler/icons/outline/alert-circle.svg?raw';
	import userCircleIcon from '@tabler/icons/outline/user-circle.svg?raw';
	import checklistIcon from '@tabler/icons/outline/checklist.svg?raw';

	// One card on the board. Opening it is a full-size button stretched behind everything else, so the
	// keyboard and a screen reader still reach the whole card as one target — the owner control and the
	// `...` menu are the only other interactive pieces, both raised above that button rather than nested
	// inside it, since a button cannot contain another button. The card itself is the drag target (Jobber
	// has no visible handle) — `PipelineColumn` is what actually turns it into one; a `pointerdown` on the
	// owner control or the menu stops there so neither ever starts a drag by itself.
	let {
		opportunity,
		formatting,
		canEdit,
		showStageBadge = false,
		onOpen,
		onLost
	}: {
		opportunity: OpportunityCard;
		// Null until the board summary has answered. Money and dates wait for it rather than being
		// written the browser's way for a moment and then correcting themselves.
		formatting: BoardFormatting | null;
		// Whether this member may assign, reassign, or clear the owner, and mark the card lost. Read-only
		// otherwise.
		canEdit: boolean;
		// True only inside the collapsed Assessment column: its heading just says "Assessment", so the
		// card is what has to say which of the three real sub-states it is really in.
		showStageBadge?: boolean;
		onOpen: () => void;
		// Told after a successful Mark as lost, so the page can close this card's Brief if it happens to
		// be open behind it — the card leaves the board on its own via the query invalidation below, but
		// a drawer already open holds its own snapshot that nothing else would think to close.
		onLost?: (opportunityId: string) => void;
	} = $props();

	const queryClient = useQueryClient();
	let lostDialogOpen = $state(false);
	// Quote-backed Lost is automatic off the Quote's own Decline/archive (5A) and never goes through this
	// dialog's RPC, which refuses a quote-backed opportunity outright -- so the menu that would only ever
	// fail is not offered at all, rather than shown greyed out the way Jobber does it for a Draft quote.
	const canMarkLost = $derived(opportunity.quote === null);
	const menuItems = [
		{
			label: 'Mark as lost',
			destructive: true,
			onSelect: () => (lostDialogOpen = true)
		}
	];
	const age = $derived(stageAge(opportunity.stage_entered_at));
	// The collapsed Assessment column's own state, read off the card's real stage -- never a second stored
	// value. "Unscheduled" is worded as a plain state name rather than an instruction, the same register
	// the other two use.
	const stageBadge = $derived.by(() => {
		if (!showStageBadge) return null;
		if (opportunity.stage === 'assessment_unscheduled')
			return { label: 'Unscheduled', status: 'warning' as const };
		if (opportunity.stage === 'assessment_scheduled')
			return { label: 'Scheduled', status: 'informative' as const };
		if (opportunity.stage === 'assessment_completed')
			return { label: 'Completed', status: 'success' as const };
		return null;
	});
	const appointmentLabel = $derived(
		formatting && opportunity.assessment
			? appointment(opportunity.assessment.starts_at, formatting)
			: null
	);
	const clientName = $derived(
		opportunity.client?.company_name?.trim() || opportunity.client?.display_name || 'No client'
	);
	// Absent when this member may not see money, null when nobody has estimated the work. Neither one is
	// a zero, so neither one prints.
	const amount = $derived(formatting ? formatMoney(opportunity.estimated_value, formatting) : null);
	const chase = $derived(formatting ? followUp(opportunity.next_follow_up_on, formatting) : null);
	// The earliest-due open Task, in the database's own priority order — the card takes it as given and
	// computes nothing. Completion and reopening only happen from the Brief, so this line is read-only.
	const taskDue = $derived(
		formatting && opportunity.task?.due_on ? followUp(opportunity.task.due_on, formatting) : null
	);
	const createdOn = $derived(
		new Date(opportunity.created_at).toLocaleDateString(undefined, {
			month: 'short',
			day: 'numeric'
		})
	);
	const ownerName = $derived(opportunity.owner?.full_name ?? 'Unassigned');

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
<div
	class={`opportunity-card opportunity-card--${age.freshness}`}
	class:opportunity-card--draggable={canEdit}
>
	<!-- A real `<button>` would work for click and keyboard alike, but svelte-dnd-action's drag-start
	     guard treats any pointerdown target with a defined `.value` as a nested form control and refuses
	     to start the drag -- every `<button>` element has that property (an empty string, never
	     `undefined`), and this one is stretched over the entire card. `role="button"` plus the keydown
	     handler below reproduce native button behaviour without tripping that guard. -->
	<div
		class="opportunity-card__open"
		role="button"
		tabindex="0"
		aria-label={`Open ${opportunity.title} for ${clientName}`}
		onclick={onOpen}
		onkeydown={(event) => {
			if (event.key === 'Enter' || event.key === ' ') {
				event.preventDefault();
				onOpen();
			}
		}}
		onmouseenter={warmClient}
		onfocus={warmClient}
	></div>

	<span class="opportunity-card__header">
		<span class="opportunity-card__title">{opportunity.title}</span>
		{#if canEdit && canMarkLost}
			<span
				class="opportunity-card__menu"
				role="presentation"
				onpointerdown={(event) => event.stopPropagation()}
			>
				<DropdownMenu items={menuItems} triggerLabel={`More actions for ${opportunity.title}`} />
			</span>
		{/if}
	</span>
	{#if stageBadge}
		<span class="opportunity-card__stage-row">
			<Badge status={stageBadge.status} size="small">{stageBadge.label}</Badge>
			{#if appointmentLabel}
				<span class="opportunity-card__appointment">
					<span class="opportunity-card__icon" aria-hidden="true">{@html calendarIcon}</span>
					{appointmentLabel}
				</span>
			{/if}
		</span>
	{/if}
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
			{#if canEdit}
				<div
					class="opportunity-card__owner-control"
					role="presentation"
					onpointerdown={(event) => event.stopPropagation()}
				>
					<OpportunityOwnerField
						opportunityId={opportunity.id}
						{ownerName}
						{canEdit}
						triggerClass="opportunity-card__owner-trigger"
						align="start"
					>
						{#snippet trigger()}
							{#if opportunity.owner}
								<Avatar
									id={opportunity.owner.id}
									name={opportunity.owner.full_name}
									src={opportunity.owner.avatar_url}
									size="small"
								/>
							{:else}
								<span class="opportunity-card__owner-placeholder" aria-hidden="true">
									{@html userCircleIcon}
								</span>
							{/if}
						{/snippet}
					</OpportunityOwnerField>
				</div>
			{:else if opportunity.owner}
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
	{#if opportunity.task}
		<span class="opportunity-card__task">
			<span class="opportunity-card__icon" aria-hidden="true">{@html checklistIcon}</span>
			<span class="opportunity-card__task-title">{opportunity.task.title}</span>
			{#if taskDue}
				<span
					class="opportunity-card__task-due"
					class:opportunity-card__task-due--overdue={taskDue.overdue}
				>
					{taskDue.overdue ? 'Overdue' : taskDue.label}
				</span>
			{/if}
		</span>
	{/if}
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
</div>

{#if lostDialogOpen}
	<MarkOpportunityLostDialog
		open={lostDialogOpen}
		opportunityId={opportunity.id}
		onSaved={() => {
			lostDialogOpen = false;
			invalidatePipeline(queryClient);
			onLost?.(opportunity.id);
		}}
		onClose={() => (lostDialogOpen = false)}
	/>
{/if}

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.opportunity-card {
		position: relative;
		display: flex;
		flex-direction: column;
		gap: var(--space-small);
		width: 100%;
		padding: var(--space-slim);
		border: var(--border-base) solid var(--color-border);
		border-left: var(--space-smaller) solid var(--card-edge, var(--color-border));
		border-radius: var(--radius-base);
		background: var(--color-surface);
		text-align: left;
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
	}
	// Jobber gives a draggable card no visible handle at all -- the cursor is the only affordance, and only
	// once there is somewhere for the drag to go.
	.opportunity-card--draggable {
		cursor: grab;

		&:active {
			cursor: grabbing;
		}
	}
	// The open action is a button stretched behind the rest of the card's content, so the whole card
	// stays one click/keyboard target without being a `<button>` that could not then contain the owner
	// control's own button. It is transparent, so the text painted after it in the flow still shows
	// through; only pointer/keyboard focus land on it.
	.opportunity-card__open {
		position: absolute;
		inset: 0;
		z-index: 1;
		border: 0;
		border-radius: inherit;
		background: transparent;
		cursor: pointer;
		appearance: none;

		// It sits on top of the whole card, so it is what the cursor actually reads while hovering a
		// draggable card -- inherit the grab affordance from the card underneath it rather than showing a
		// plain pointer everywhere a drag can start.
		.opportunity-card--draggable & {
			cursor: inherit;
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
	.opportunity-card__header {
		display: flex;
		align-items: flex-start;
		justify-content: space-between;
		gap: var(--space-small);
	}
	.opportunity-card__title {
		min-width: 0;
		overflow: hidden;
		color: var(--color-heading);
		font-size: var(--typography--fontSize-base);
		font-weight: 600;
		line-height: var(--typography--lineHeight-tight);
		text-overflow: ellipsis;
		white-space: nowrap;
	}
	// Raised above the open button (z-index 1) so it is its own click/keyboard target, the same reason
	// the owner control below is raised.
	.opportunity-card__menu {
		position: relative;
		z-index: 2;
		flex: 0 0 auto;
		margin: -6px -6px 0 0;
	}
	.opportunity-card__stage-row {
		display: flex;
		align-items: center;
		flex-wrap: wrap;
		gap: var(--space-small);
	}
	.opportunity-card__appointment {
		display: inline-flex;
		align-items: center;
		gap: 6px;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
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
	// Raised above the open button (z-index 1) so it is its own click/keyboard target instead of being
	// swallowed by the stretched card-opening button beneath it.
	.opportunity-card__owner-control {
		position: relative;
		z-index: 2;
	}
	:global(.opportunity-card__owner-trigger) {
		display: inline-flex;
		padding: 0;
		border: 0;
		border-radius: var(--radius-circle);
		background: transparent;
		cursor: pointer;

		&:focus-visible {
			outline: none;
			box-shadow: var(--shadow-focus);
		}
	}
	.opportunity-card__owner-placeholder {
		display: inline-grid;
		width: 24px;
		height: 24px;
		place-items: center;
		border-radius: var(--radius-circle);
		color: var(--color-icon--secondary);
		background: var(--color-inactive--surface);
		transition: color var(--timing-quick);

		:global(.opportunity-card__owner-trigger:hover) & {
			color: var(--color-icon);
		}

		:global(svg) {
			display: block;
			width: 18px;
			height: 18px;
		}
	}
	.opportunity-card__task {
		display: inline-flex;
		align-items: center;
		gap: 6px;
		min-width: 0;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}
	.opportunity-card__task-title {
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}
	.opportunity-card__task-due {
		flex: 0 0 auto;
		color: var(--color-text--secondary);

		&--overdue {
			color: var(--color-critical--onSurface);
			font-weight: 600;
		}
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
