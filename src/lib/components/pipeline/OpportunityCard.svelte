<script lang="ts">
	import { useQueryClient } from '@tanstack/svelte-query';
	import { goto } from '$app/navigation';
	import { resolve } from '$app/paths';
	import StageAgeChip from './StageAgeChip.svelte';
	import Avatar from '$lib/components/ui/Avatar.svelte';
	import Badge from '$lib/components/ui/Badge.svelte';
	import DropdownMenu from '$lib/components/ui/DropdownMenu.svelte';
	import OpportunityOwnerField from './OpportunityOwnerField.svelte';
	import MarkOpportunityLostDialog from './MarkOpportunityLostDialog.svelte';
	import { inactivity, stageAge, type InactivityRules } from '$lib/pipeline/freshness';
	import { appointment, followUp, formatMoney, type BoardFormatting } from '$lib/pipeline/money';
	import {
		fetchLostReasons,
		invalidatePipeline,
		lostReasonsKey,
		type OpportunityCard
	} from '$lib/pipeline/api';
	import { BOARD_SECTIONS, BOARD_SECTION_LABELS, type CustomStage } from '$lib/pipeline/stages';
	import { moveDestinations, type MoveDestination, type MoveTarget } from '$lib/pipeline/moves';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import { clientDetailKey, fetchClient } from '$lib/clients/api';
	import { activityKey } from '$lib/collaboration/api';
	import calendarIcon from '@tabler/icons/outline/calendar-event.svg?raw';
	import userCircleIcon from '@tabler/icons/outline/user-circle.svg?raw';
	import checklistIcon from '@tabler/icons/outline/checklist.svg?raw';
	import mailOffIcon from '@tabler/icons/outline/mail-off.svg?raw';
	import hourglassIcon from '@tabler/icons/outline/hourglass-low.svg?raw';
	import moveIcon from '@tabler/icons/outline/arrow-move-right.svg?raw';
	import checkIcon from '@tabler/icons/outline/check.svg?raw';
	import lockIcon from '@tabler/icons/outline/lock.svg?raw';
	import clockPauseIcon from '@tabler/icons/outline/clock-pause.svg?raw';

	// One card on the board. Opening it is a full-size button stretched behind everything else, so the
	// keyboard and a screen reader still reach the whole card as one target — the owner control and the
	// Move button, and the `...` menu are the only other interactive pieces, all raised above that button
	// rather than nested inside it, since a button cannot contain another button. The card itself is the drag target (Jobber
	// has no visible handle) — `PipelineColumn` is what actually turns it into one; a `pointerdown` on the
	// owner control or a menu stops there so none of them ever starts a drag by itself.
	let {
		opportunity,
		formatting,
		canEdit,
		showStageBadge = false,
		customStages = [],
		inactivityRules = null,
		onMove,
		moveBusy = false,
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
		// True wherever the column heading does not say the card's real stage: the collapsed Assessment
		// column, whose heading just says "Assessment", and every custom follow-up column, where the card
		// is still really a Draft or a New request underneath.
		showStageBadge?: boolean;
		// The organization's custom follow-up stages, listed in the Move menu beside the real stages.
		customStages?: readonly CustomStage[];
		// The owner's days and the organization's today. No warning shows until the board has them.
		inactivityRules?: InactivityRules | null;
		// Asks for the card to go somewhere, without dragging. The column owns every move, so the Move menu
		// and a drop open the same dialogs, save, lock the board, and report in exactly the same way.
		onMove?: (target: MoveTarget) => void;
		// True while another move is being confirmed or saved; the Move button waits its turn.
		moveBusy?: boolean;
		onOpen: () => void;
		// Told after a successful Mark as lost, so the page can close this card's Brief if it happens to
		// be open behind it — the card leaves the board on its own via the query invalidation below, but
		// a drawer already open holds its own snapshot that nothing else would think to close.
		onLost?: (opportunityId: string) => void;
	} = $props();

	const queryClient = useQueryClient();
	const toast = getToastManager();
	let lostDialogOpen = $state(false);
	// A Request card, or a quote the customer has seen. A Draft is not offered it, the way Jobber greys it
	// out: a quote nobody received is not lost, and archiving it from the Quote is "Abandoned before
	// sending". The real stage is what counts, so a card sitting in a custom follow-up column still has it.
	const canMarkLost = $derived(
		opportunity.quote === null ||
			opportunity.stage === 'quote_awaiting_response' ||
			opportunity.stage === 'quote_changes_requested'
	);
	// The Move button: every stage on the board, for anyone not dragging. The stage the card is in is
	// ticked, the ones it can go to simply go, and the ones it cannot stay selectable so that choosing one
	// says exactly why and what to do instead — a disabled row could never explain itself.
	const destinations = $derived(onMove ? moveDestinations(opportunity, customStages) : []);
	const moveGroups = $derived(
		BOARD_SECTIONS.map((section) => ({
			heading: BOARD_SECTION_LABELS[section],
			items: destinations
				.filter((destination) => destination.section === section)
				.map((destination) => ({
					key: destination.key,
					label: destination.label,
					muted: destination.state !== 'available',
					trailingIcon:
						destination.state === 'current'
							? checkIcon
							: destination.state === 'blocked'
								? lockIcon
								: destination.onHold
									? clockPauseIcon
									: undefined,
					note:
						destination.state === 'current'
							? 'this card is here'
							: destination.state === 'blocked'
								? 'not available, choose it to see why'
								: destination.onHold
									? 'on hold stage'
									: undefined,
					onSelect: () => chooseDestination(destination)
				}))
		})).filter((group) => group.items.length > 0)
	);

	function chooseDestination(destination: MoveDestination) {
		if (destination.state === 'available') {
			onMove?.(destination.target);
			return;
		}
		if (destination.state === 'current') {
			toast.info(`This card is already in ${destination.label}.`);
			return;
		}
		const nextStep = destination.nextStep;
		const recordId =
			nextStep?.record === 'request' ? opportunity.request?.id : opportunity.quote?.id;
		toast.show({
			variant: 'warning',
			title: `This card can’t move to ${destination.label}.`,
			message: destination.reason,
			duration: 10_000,
			action:
				nextStep && recordId
					? { label: nextStep.label, onSelect: () => openRecord(nextStep.record, recordId) }
					: undefined
		});
	}

	function openRecord(record: 'request' | 'quote', id: string) {
		if (record === 'request') void goto(resolve('/(app)/requests/[id=uuid]', { id }));
		else void goto(resolve('/(app)/quotes/[id=uuid]', { id }));
	}

	const menuItems = $derived(
		canMarkLost
			? [
					{
						label: 'Mark as lost',
						destructive: true,
						onSelect: () => (lostDialogOpen = true)
					}
				]
			: []
	);
	const age = $derived(stageAge(opportunity.stage_entered_at));
	// A card in a custom stage is judged by that stage's own days; an on-hold one waits for its Task.
	const quiet = $derived(inactivity(opportunity, inactivityRules));
	// The card's real state, read off its real stage -- never a second stored value. "Unscheduled" is
	// worded as a plain state name rather than an instruction, the same register the other two use.
	const stageBadge = $derived.by(() => {
		if (!showStageBadge) return null;
		if (opportunity.stage === 'new_request')
			return { label: 'New request', status: 'informative' as const };
		if (opportunity.stage === 'quote_draft') return { label: 'Draft', status: 'inactive' as const };
		if (opportunity.stage === 'quote_awaiting_response')
			return { label: 'Awaiting response', status: 'informative' as const };
		if (opportunity.stage === 'quote_changes_requested')
			return { label: 'Changes requested', status: 'warning' as const };
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
	// An owner without a name is someone who left the team; a teammate who never typed one arrives as email.
	const ownerName = $derived(
		opportunity.owner ? (opportunity.owner.full_name ?? 'Former teammate') : 'Unassigned'
	);

	// "Mark as lost" asks for a reason from the organization's list; warming it as the menu is reached
	// means the dialog opens with its choices already there.
	function warmLostReasons() {
		if (!canMarkLost) return;
		void queryClient.prefetchQuery({
			queryKey: lostReasonsKey,
			queryFn: fetchLostReasons,
			staleTime: 5 * 60_000
		});
	}

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
	class="opportunity-card"
	data-opportunity-id={opportunity.id}
	class:opportunity-card--inactive={quiet !== null}
	class:opportunity-card--draggable={canEdit}
>
	<!-- A real `<button>` would work for click and keyboard alike, but svelte-dnd-action's drag-start
	     guard treats any pointerdown target with a defined `.value` as a nested form control and refuses
	     to start the drag -- every `<button>` element has that property (an empty string, never
	     `undefined`), and this one is stretched over the entire card. `role="button"` plus the keydown
	     handler below reproduce native button behaviour without tripping that guard. Space is left to
	     `PipelineColumn`'s keyboard-drag trigger (narrowed to Space there) -- claiming it here too would
	     fire both a drag pickup and an open on the same press. -->
	<div
		class="opportunity-card__open"
		role="button"
		tabindex="0"
		aria-label={`Open ${opportunity.title} for ${clientName}`}
		onclick={onOpen}
		onkeydown={(event) => {
			if (event.key === 'Enter') {
				event.preventDefault();
				onOpen();
			}
		}}
		onmouseenter={warmClient}
		onfocus={warmClient}
	></div>

	<span class="opportunity-card__header">
		<span class="opportunity-card__title">{opportunity.title}</span>
		{#if canEdit && (moveGroups.length > 0 || menuItems.length > 0)}
			<span
				class="opportunity-card__menu"
				role="presentation"
				onpointerdown={(event) => event.stopPropagation()}
			>
				{#if moveGroups.length > 0}
					<DropdownMenu
						groups={moveGroups}
						wide
						triggerIcon={moveIcon}
						triggerLabel={`Move ${opportunity.title}`}
						disabled={moveBusy}
					/>
				{/if}
				{#if menuItems.length > 0}
					<span role="presentation" onpointerenter={warmLostReasons} onfocusin={warmLostReasons}>
						<DropdownMenu
							items={menuItems}
							triggerLabel={`More actions for ${opportunity.title}`}
						/>
					</span>
				{/if}
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
	{#if opportunity.client?.lead_source}
		<span class="opportunity-card__source">
			<span class="opportunity-card__spoken">Lead source: </span>
			<Badge size="small">{opportunity.client.lead_source}</Badge>
		</span>
	{/if}
	{#if opportunity.quote?.delivery_failure}
		<!-- The card stays in Awaiting response: the quote was sent. This says the customer has nothing yet;
		     the Brief says why and what to do. -->
		<span class="opportunity-card__delivery-failed">
			<span class="opportunity-card__icon" aria-hidden="true">{@html mailOffIcon}</span>
			Delivery failed
		</span>
	{/if}
	{#if quiet}
		<span class="opportunity-card__inactive">
			<span class="opportunity-card__icon" aria-hidden="true">{@html hourglassIcon}</span>
			{quiet.label}
		</span>
	{/if}
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
			<StageAgeChip label={age.label} description={age.description} />
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
					{taskDue.overdue ? 'Overdue' : taskDue.dueToday ? 'Today' : taskDue.label}
				</span>
			{/if}
		</span>
	{/if}
</div>

{#if lostDialogOpen}
	<MarkOpportunityLostDialog
		open={lostDialogOpen}
		opportunityId={opportunity.id}
		subject={opportunity.quote ? 'quote' : 'request'}
		onSaved={() => {
			lostDialogOpen = false;
			invalidatePipeline(queryClient);
			// Marking a quote's card Lost archived the quote and wrote a line in its history.
			if (opportunity.quote) {
				void queryClient.invalidateQueries({ queryKey: ['quotes'] });
				void queryClient.invalidateQueries({
					queryKey: activityKey('quote', opportunity.quote.id)
				});
			}
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
	// The edge repeats the inactivity line, for the glance across a full column. Age alone never colours it.
	.opportunity-card--inactive {
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
		display: inline-flex;
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
	.opportunity-card__source {
		display: flex;
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
	// The words carry it; the colour and the icon only repeat them.
	.opportunity-card__delivery-failed,
	.opportunity-card__inactive {
		display: inline-flex;
		align-items: center;
		gap: 6px;
		color: var(--color-critical--onSurface);
		font-size: var(--typography--fontSize-small);
		font-weight: 600;
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
