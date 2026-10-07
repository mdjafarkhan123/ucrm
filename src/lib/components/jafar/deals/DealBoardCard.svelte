<script lang="ts">
	import { resolve } from '$app/paths';
	import arrowsMoveIcon from '@tabler/icons/outline/arrows-move.svg?raw';
	import calendarIcon from '@tabler/icons/outline/calendar-event.svg?raw';
	import alertIcon from '@tabler/icons/outline/alert-circle.svg?raw';
	import Badge from '$lib/components/ui/Badge.svelte';
	import DropdownMenu from '$lib/components/ui/DropdownMenu.svelte';
	import StageAgeChip from '$lib/components/pipeline/StageAgeChip.svelte';
	import { countryName } from '$lib/jafar/leads';
	import {
		DEAL_STAGE_LABELS,
		LOST_REASON_LABELS,
		OPEN_DEAL_STAGES,
		daysSince,
		isOverdue,
		monthlyValue,
		type DealCard,
		type OpenDealStage
	} from '$lib/jafar/deals';

	// Jafar business management B4: one Deal on the board. The business name opens its page, where the Deal box
	// lives; "Move to…" does on a phone, or from the keyboard, what a drag does on a desktop.
	let {
		deal,
		canChange,
		busy = false,
		today,
		onMove,
		onSharePricing,
		onLost,
		onPrefetchPackages
	}: {
		deal: DealCard;
		canChange: boolean;
		busy?: boolean;
		/** Today's local date, "2026-10-07", read once by the board. */
		today: string;
		onMove: (stage: OpenDealStage) => void;
		onSharePricing: () => void;
		onLost: () => void;
		/** Warms the package list while the menu is open, so "Share pricing" opens filled. */
		onPrefetchPackages: () => void;
	} = $props();

	const won = $derived(deal.stage === 'won');
	// Lost and Won are closed: no menu, no next step, no time-in-stage.
	const lost = $derived(deal.stage === 'lost' || won);
	const overdue = $derived(!lost && isOverdue(deal.next_action_due_on, today));
	const days = $derived(daysSince(deal.stage_entered_at));
	const value = $derived(monthlyValue(deal.value_monthly_usd_cents));

	const dateFormat = new Intl.DateTimeFormat(undefined, {
		day: 'numeric',
		month: 'short',
		year: 'numeric'
	});

	function formatDay(day: string) {
		const [year, month, date] = day.split('-').map(Number);
		return new Intl.DateTimeFormat(undefined, { day: 'numeric', month: 'short' }).format(
			new Date(year, month - 1, date)
		);
	}

	const dueLabel = $derived.by(() => {
		const due = deal.next_action_due_on;
		if (!due) return '';
		if (due < today) return `Overdue · ${formatDay(due)}`;
		if (due === today) return 'Due today';
		return formatDay(due);
	});

	let menuOpen = $state(false);
	$effect(() => {
		if (menuOpen && !lost) onPrefetchPackages();
	});

	// A closed Deal has no menu: a Lost one is reopened from the business's page, where its history is.
	const menuItems = $derived([
		...OPEN_DEAL_STAGES.filter((stage) => stage !== deal.stage && stage !== 'pricing_shared').map(
			(stage) => ({
				key: stage,
				label: `Move to ${DEAL_STAGE_LABELS[stage]}`,
				onSelect: () => onMove(stage)
			})
		),
		{ key: 'pricing', label: 'Share pricing…', onSelect: onSharePricing }
	]);
	const menuFooter = $derived([{ label: 'Mark as Lost…', destructive: true, onSelect: onLost }]);
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<article
	class={['deal-card', overdue && 'deal-card--overdue', lost && 'deal-card--lost']}
	data-deal-id={deal.id}
>
	<div class="deal-card__top">
		<a
			class="deal-card__open"
			href={resolve('/jafar/(protected)/leads/[id]', { id: deal.relationship_id })}
			>{deal.business_name}</a
		>
		{#if canChange && !lost}
			<DropdownMenu
				items={menuItems}
				footer={menuFooter}
				triggerLabel={`Move or change ${deal.business_name}`}
				triggerIcon={arrowsMoveIcon}
				disabled={busy}
				bind:open={menuOpen}
			/>
		{/if}
	</div>

	<p class="deal-card__who">
		{deal.contact_name ? `${deal.contact_name} · ` : ''}{deal.trade} · {countryName(
			deal.country_code
		)}
	</p>

	{#if value || deal.shared_packages.length}
		<p class="deal-card__value">
			{#if value}<strong>{value}</strong>{/if}
			{#if deal.shared_packages.length}<span>{deal.shared_packages.join(', ')}</span>{/if}
		</p>
	{/if}

	{#if won}
		<p class="deal-card__lost">
			Won{deal.won_at ? ` · ${dateFormat.format(new Date(deal.won_at))}` : ''}{deal.won_package_name
				? ` · ${deal.won_package_name} paid`
				: ''}
		</p>
	{:else if lost}
		<p class="deal-card__lost">
			Lost · {deal.lost_reason ? LOST_REASON_LABELS[deal.lost_reason] : 'No reason'}
		</p>
	{:else if deal.next_action}
		<p class={['deal-card__next', overdue && 'deal-card__next--overdue']}>
			<span class="deal-card__icon" aria-hidden="true"
				>{@html overdue ? alertIcon : calendarIcon}</span
			>
			<span class="deal-card__next-text">
				<span>{deal.next_action}</span>
				<small>{dueLabel}</small>
			</span>
		</p>
	{:else}
		<p class="deal-card__next deal-card__next--missing">No next step</p>
	{/if}

	<div class="deal-card__foot">
		{#if won && deal.payment_reversed}
			<Badge size="small" status="critical" dot={false}>Payment reversed</Badge>
		{/if}
		{#if deal.has_agreed_terms}
			<Badge size="small" status="informative" dot={false}>Special terms</Badge>
		{/if}
		{#if !lost}
			<StageAgeChip
				label={`${days}d`}
				description={`In ${DEAL_STAGE_LABELS[deal.stage]} for ${days} ${days === 1 ? 'day' : 'days'}`}
			/>
		{/if}
	</div>
</article>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.deal-card {
		position: relative;
		display: grid;
		gap: var(--space-small);
		padding: var(--space-slim) var(--space-base);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface);
		box-shadow: var(--shadow-low);
		cursor: grab;
		transition:
			border-color var(--timing-quick),
			box-shadow var(--timing-quick);

		&:hover {
			border-color: var(--color-border--interactive);
			box-shadow: var(--shadow-base);
		}
	}

	.deal-card--overdue {
		border-left: 3px solid var(--color-critical);
	}

	.deal-card--lost {
		cursor: default;
	}

	.deal-card p {
		margin: 0;
	}

	.deal-card__top {
		display: flex;
		align-items: flex-start;
		justify-content: space-between;
		gap: var(--space-small);

		// The menu sits above the card-wide link, so it stays its own target.
		:global(.dropdown-menu__trigger) {
			position: relative;
			z-index: 1;
			flex: 0 0 auto;
			margin: calc(var(--space-smaller) * -1) calc(var(--space-small) * -1) 0 0;
		}
	}

	// The whole card opens the business: the link's hit area stretches over it.
	.deal-card__open {
		min-width: 0;
		color: var(--color-heading);
		font-weight: 700;
		line-height: var(--typography--lineHeight-tight);
		text-decoration: none;
		overflow-wrap: anywhere;

		&::after {
			content: '';
			position: absolute;
			inset: 0;
			border-radius: inherit;
		}

		&:hover {
			color: var(--color-interactive);
			text-decoration: underline;
			text-underline-offset: 3px;
		}

		&:focus-visible {
			outline: none;

			&::after {
				box-shadow: var(--shadow-focus);
			}
		}
	}

	.deal-card__who {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		overflow-wrap: anywhere;
	}

	.deal-card__value {
		display: flex;
		flex-wrap: wrap;
		align-items: baseline;
		gap: 0 var(--space-small);
		font-size: var(--typography--fontSize-small);

		strong {
			color: var(--color-heading);
			font-size: var(--typography--fontSize-base);
			font-variant-numeric: tabular-nums;
		}

		span {
			color: var(--color-text--secondary);
		}
	}

	.deal-card__next {
		display: flex;
		gap: var(--space-small);
		color: var(--color-text);
		font-size: var(--typography--fontSize-small);
	}

	.deal-card__next-text {
		display: grid;
		min-width: 0;
		overflow-wrap: anywhere;

		small {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-smaller);
		}
	}

	.deal-card__next--overdue small,
	.deal-card__next--overdue .deal-card__icon {
		color: var(--color-critical);
		font-weight: 600;
	}

	.deal-card__next--missing {
		color: var(--color-warning--onSurface);
		font-weight: 600;
	}

	.deal-card__icon {
		display: inline-flex;
		flex: 0 0 auto;
		color: var(--color-icon--secondary);

		:global(svg) {
			width: 16px;
			height: 16px;
		}
	}

	.deal-card__lost {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		font-weight: 600;
	}

	.deal-card__foot {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		justify-content: flex-end;
		gap: var(--space-small);

		&:empty {
			display: none;
		}
	}
</style>
