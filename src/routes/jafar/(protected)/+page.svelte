<script lang="ts">
	import { resolve } from '$app/paths';
	import { createQuery } from '@tanstack/svelte-query';
	import alertIcon from '@tabler/icons/outline/alert-triangle.svg?raw';
	import arrowRightIcon from '@tabler/icons/outline/arrow-up-right.svg?raw';
	import bellIcon from '@tabler/icons/outline/bell.svg?raw';
	import checkIcon from '@tabler/icons/outline/check.svg?raw';
	import circleCheckIcon from '@tabler/icons/outline/circle-check.svg?raw';
	import clipboardCheckIcon from '@tabler/icons/outline/clipboard-check.svg?raw';
	import refreshIcon from '@tabler/icons/outline/refresh.svg?raw';
	import rocketIcon from '@tabler/icons/outline/rocket.svg?raw';
	import sendIcon from '@tabler/icons/outline/send.svg?raw';
	import userPlusIcon from '@tabler/icons/outline/user-plus.svg?raw';
	import KpiCard from '$lib/components/data-display/KpiCard.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import Badge from '$lib/components/ui/Badge.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import NextActionDialog from '$lib/components/jafar/leads/NextActionDialog.svelte';
	import {
		agendaTag,
		businessHomeKey,
		fetchBusinessHome,
		groupAgenda,
		HOME_AGENDA_LIMIT,
		type HomeAgendaItem
	} from '$lib/jafar/business-home';
	import { isoDate } from '$lib/jafar/deals';
	import { countryName } from '$lib/jafar/leads';
	import {
		exactTime,
		fetchNotifications,
		notificationHref,
		notificationsKey,
		relativeTime,
		severityLabel,
		type NotificationListResponse
	} from '$lib/jafar/notifications';

	// Jafar business management C1: the Business Management home. What is waiting on Jafar sits on top as counts
	// he can tap; below, every business's next step that is overdue, due today, or due in the next seven days,
	// overdue first (Jafar, 2026-10-07, after HubSpot's Sales Workspace and Pipedrive's Activities). Done records
	// the step on the business and asks for the next, as on the business's own page.

	// Jafar's own calendar day. It moves on if the page is left open overnight and looked at again.
	let today = $state(isoDate(new Date()));
	$effect(() => {
		const check = () => {
			if (document.visibilityState === 'visible') today = isoDate(new Date());
		};
		document.addEventListener('visibilitychange', check);
		return () => document.removeEventListener('visibilitychange', check);
	});

	const home = createQuery(() => ({
		queryKey: businessHomeKey(today),
		queryFn: () => fetchBusinessHome(today)
	}));

	/**
	 * Unread alerts are shown here as well as in the bell, so a failed setup email cannot sit unnoticed behind a
	 * menu Jafar never opened.
	 */
	const alerts = createQuery<NotificationListResponse>(() => ({
		queryKey: [...notificationsKey, 'dashboard'],
		queryFn: () => fetchNotifications({ status: 'unread', limit: 5 })
	}));
	const alertList = $derived(alerts.data?.notifications ?? []);

	const groups = $derived(home.data ? groupAgenda(home.data.items, today) : []);
	const groupTotals = $derived({
		overdue: home.data?.overdue ?? 0,
		today: home.data?.today ?? 0,
		upcoming: home.data?.upcoming ?? 0
	});
	const listedCount = $derived(home.data?.items.length ?? 0);
	const dueCount = $derived(groupTotals.overdue + groupTotals.today + groupTotals.upcoming);

	const GROUP_TITLES = { overdue: 'Overdue', today: 'Today', upcoming: 'Next 7 days' } as const;

	let completing = $state<HomeAgendaItem | null>(null);

	const greeting = $derived.by(() => {
		const hour = new Date().getHours();
		return hour < 12 ? 'Good morning' : hour < 18 ? 'Good afternoon' : 'Good evening';
	});

	const todayLabel = $derived(
		new Intl.DateTimeFormat(undefined, { weekday: 'long', day: 'numeric', month: 'long' }).format(
			new Date(`${today}T12:00:00`)
		)
	);

	function daysBetween(from: string, to: string) {
		return Math.round(
			(new Date(`${to}T12:00:00`).getTime() - new Date(`${from}T12:00:00`).getTime()) / 86_400_000
		);
	}

	function dueLabel(dueOn: string) {
		const days = daysBetween(today, dueOn);
		if (days === 0) return 'Today';
		if (days === -1) return 'Yesterday';
		if (days < 0) return `${-days} days late`;
		if (days === 1) return 'Tomorrow';
		return new Intl.DateTimeFormat(undefined, {
			weekday: 'short',
			day: 'numeric',
			month: 'short'
		}).format(new Date(`${dueOn}T12:00:00`));
	}

	function count(value: number | null | undefined) {
		return value === null || value === undefined ? '–' : String(value);
	}

	const summary = $derived.by(() => {
		if (!home.data) return 'Here is what needs you today.';
		const { overdue, today: dueToday } = home.data;
		if (overdue === 0 && dueToday === 0) return 'Nothing is overdue or due today.';
		const parts = [];
		if (overdue) parts.push(`${overdue} overdue`);
		if (dueToday) parts.push(`${dueToday} due today`);
		return `${parts.join(' and ')}.`;
	});
</script>

<svelte:head><title>Today · Business Management</title></svelte:head>

<!-- eslint-disable svelte/no-at-html-tags -->
<main class="business-home">
	<header class="business-home__header">
		<p class="business-home__eyebrow">{todayLabel}</p>
		<h1>{greeting}, Jafar</h1>
		<p class="business-home__lede">{summary}</p>
	</header>

	<section class="business-home__waiting" aria-labelledby="waiting-title">
		<h2 id="waiting-title" class="business-home__section-title">Waiting on you</h2>
		<div class="business-home__tiles">
			{#if home.data}
				<KpiCard
					variant="compact"
					label="Leads to review"
					value={count(home.data.review)}
					note="Ready for your yes"
					icon={clipboardCheckIcon}
					tone={home.data.review ? 'warning' : 'default'}
					href={resolve('/jafar/leads/review')}
				/>
				<KpiCard
					variant="compact"
					label="First contacts"
					value={count(home.data.first_contact)}
					note="Approved, not contacted yet"
					icon={sendIcon}
					tone={home.data.first_contact ? 'success' : 'default'}
					href={`${resolve('/jafar/leads')}?status=approved&sort=next_action`}
				/>
				<KpiCard
					variant="compact"
					label="Accounts to create"
					value={count(home.data.accounts_to_create)}
					note="Paid, account not made"
					icon={userPlusIcon}
					tone={home.data.accounts_to_create ? 'informative' : 'default'}
					href={`${resolve('/jafar/prospects')}?stage=payment_confirmed`}
				/>
				<KpiCard
					variant="compact"
					label="Setups waiting"
					value={count(home.data.setups_waiting)}
					note="Clients waiting on Uplift"
					icon={rocketIcon}
					tone={home.data.setups_waiting ? 'informative' : 'default'}
					href={`${resolve('/jafar/onboarding')}?waiting_on=uplift`}
				/>
				<KpiCard
					variant="compact"
					label="Renewals"
					value={count(home.data.renewals)}
					note="Due this week or late"
					icon={refreshIcon}
					tone={home.data.renewals ? 'critical' : 'default'}
					href={`${resolve('/jafar/organizations')}?attention_reason=payment_overdue,renewal_due`}
				/>
			{:else}
				{#each [0, 1, 2, 3, 4] as tile (tile)}
					<div class="business-home__tile-skeleton"><LoadingSkeleton label="Loading counts" /></div>
				{/each}
			{/if}
		</div>
	</section>

	<div class="business-home__grid">
		<section class="business-home__panel" aria-labelledby="todo-title">
			<header class="business-home__panel-header">
				<h2 id="todo-title">Your to-do list</h2>
				{#if home.data}
					<span class="business-home__count">{dueCount} this week</span>
				{/if}
			</header>

			{#if home.isPending}
				<div class="business-home__loading">
					<LoadingSkeleton variant="table" rows={5} label="Loading your to-do list" />
				</div>
			{:else if home.isError}
				<ErrorState
					title="Your to-do list could not be loaded"
					description={home.error.message}
					retry={() => home.refetch()}
				/>
			{:else if dueCount === 0}
				<div class="business-home__empty">
					<span class="business-home__empty-icon" aria-hidden="true">{@html circleCheckIcon}</span>
					<strong>Nothing due this week</strong>
					<span
						>Every business's next step is further out. New ones appear here when they fall due.</span
					>
				</div>
			{:else}
				{#each groups as group (group.key)}
					{#if group.items.length}
						<section
							class={['business-home__group', `business-home__group--${group.key}`]}
							aria-labelledby={`todo-${group.key}`}
						>
							<h3 id={`todo-${group.key}`} class="business-home__group-title">
								{GROUP_TITLES[group.key]}
								<span>{groupTotals[group.key]}</span>
							</h3>
							<ul class="business-home__list">
								{#each group.items as item (item.id)}
									{@const tag = agendaTag(item)}
									<li class="business-home__item">
										<a
											class="business-home__item-link"
											href={resolve('/jafar/(protected)/leads/[id]', { id: item.id })}
										>
											<span class="business-home__item-action">{item.next_action}</span>
											<span class="business-home__item-meta">
												<strong>{item.business_name}</strong>
												<span>{item.trade} · {countryName(item.country_code)}</span>
											</span>
										</a>
										<span class="business-home__item-side">
											<Badge size="small" status={tag.tone === 'neutral' ? undefined : tag.tone}
												>{tag.label}</Badge
											>
											<span
												class={['business-home__due', `business-home__due--${group.key}`]}
												title={item.due_on}>{dueLabel(item.due_on)}</span
											>
											<Button variant="secondary" size="small" onclick={() => (completing = item)}>
												<span class="business-home__button-icon" aria-hidden="true"
													>{@html checkIcon}</span
												>Done<span class="visually-hidden"
													>: {item.next_action}, {item.business_name}</span
												>
											</Button>
										</span>
									</li>
								{/each}
							</ul>
						</section>
					{/if}
				{/each}
				{#if listedCount < dueCount}
					<p class="business-home__more">
						Showing the {HOME_AGENDA_LIMIT} earliest of {dueCount}. Finish these and the rest move
						up.
					</p>
				{/if}
			{/if}
		</section>

		{#if alertList.length > 0}
			<section class="business-home__panel" aria-labelledby="alerts-title">
				<header class="business-home__panel-header">
					<h2 id="alerts-title">Alerts</h2>
					<span class="business-home__count">{alerts.data?.unread_count ?? 0} unread</span>
				</header>
				<ul class="business-home__alerts">
					{#each alertList as alert (alert.id)}
						<li>
							<!-- eslint-disable-next-line svelte/no-navigation-without-resolve -- notificationHref() already resolves the path; the target is only known at runtime. -->
							<a class="business-home__alert" href={notificationHref(alert)}>
								<span
									class={[
										'business-home__alert-icon',
										alert.severity === 'attention' && 'business-home__alert-icon--warning',
										alert.severity === 'urgent' && 'business-home__alert-icon--critical'
									]}
								>
									{@html alert.severity === 'info' ? bellIcon : alertIcon}
								</span>
								<span class="business-home__alert-content">
									<strong>{alert.title}</strong>
									<small title={exactTime(alert.created_at)}
										>{severityLabel(alert.severity)} · {relativeTime(alert.created_at)}</small
									>
								</span>
							</a>
						</li>
					{/each}
				</ul>
				<footer class="business-home__panel-footer">
					<a href={resolve('/jafar/notifications')}
						>Open all notifications <span aria-hidden="true">{@html arrowRightIcon}</span></a
					>
				</footer>
			</section>
		{/if}
	</div>
</main>
<!-- eslint-enable svelte/no-at-html-tags -->

{#if completing}
	<NextActionDialog
		leadId={completing.id}
		mode="done"
		current={{ text: completing.next_action, due_on: completing.due_on }}
		onClose={() => (completing = null)}
	/>
{/if}

<style lang="scss">
	.business-home {
		min-width: 0;
		display: grid;
		gap: var(--space-large);
	}
	h1,
	h2,
	h3,
	p {
		margin: 0;
	}
	.business-home__eyebrow {
		margin-bottom: var(--space-small);
		color: var(--color-interactive);
		font-size: var(--typography--fontSize-small);
		font-weight: 700;
		letter-spacing: var(--typography--letterSpacing-loose);
		text-transform: uppercase;
	}
	h1 {
		color: var(--color-heading);
		font-family: var(--typography--fontFamily-display);
		font-size: var(--typography--fontSize-jumbo);
		font-weight: 900;
		line-height: var(--typography--lineHeight-minuscule);
	}
	.business-home__lede {
		margin-top: var(--space-small);
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-large);
	}
	.business-home__section-title {
		margin-bottom: var(--space-base);
		color: var(--color-heading);
		font-size: var(--typography--fontSize-large);
	}
	.business-home__tiles {
		display: grid;
		grid-template-columns: repeat(5, minmax(0, 1fr));
		gap: var(--space-base);
	}
	// The same height as a compact card, so the counts arriving never push the list down.
	.business-home__tile-skeleton {
		min-height: 120px;
		:global(.skeleton) {
			height: 100%;
			min-height: 120px;
		}
	}
	.business-home__grid {
		display: grid;
		grid-template-columns: minmax(0, 1fr);
		gap: var(--space-base);
		align-items: start;
		&:has(> :nth-child(2)) {
			grid-template-columns: minmax(0, 1.7fr) minmax(300px, 1fr);
		}
	}
	.business-home__panel {
		overflow: hidden;
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface);
		box-shadow: var(--shadow-low);
	}
	.business-home__panel-header {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-base);
		padding: var(--space-base) var(--space-large);
		border-bottom: var(--border-base) solid var(--color-border);
		h2 {
			color: var(--color-heading);
			font-size: var(--typography--fontSize-larger);
			line-height: var(--typography--lineHeight-tightest);
		}
	}
	.business-home__count {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}
	.business-home__loading {
		padding: var(--space-base) var(--space-large);
	}
	.business-home__group + .business-home__group {
		border-top: var(--border-base) solid var(--color-border);
	}
	.business-home__group-title {
		display: flex;
		align-items: center;
		gap: var(--space-small);
		padding: var(--space-base) var(--space-large) var(--space-small);
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		font-weight: 700;
		letter-spacing: var(--typography--letterSpacing-loose);
		text-transform: uppercase;
		span {
			padding: 2px 8px;
			border-radius: 10px;
			color: var(--color-text--secondary);
			background: var(--color-surface--background);
			letter-spacing: 0;
		}
	}
	.business-home__group--overdue .business-home__group-title {
		color: var(--color-critical);
		span {
			color: var(--color-critical--onSurface);
			background: var(--color-critical--surface);
		}
	}
	.business-home__list {
		margin: 0;
		padding: 0 var(--space-large) var(--space-small);
		list-style: none;
	}
	.business-home__item {
		display: flex;
		align-items: center;
		gap: var(--space-base);
		padding: var(--space-base) 0;
		& + & {
			border-top: var(--border-base) solid var(--color-border);
		}
	}
	.business-home__item-link {
		display: grid;
		flex: 1;
		min-width: 0;
		gap: 2px;
		color: var(--color-text);
		text-decoration: none;
		&:hover .business-home__item-action {
			color: var(--color-interactive);
		}
	}
	.business-home__item-action {
		overflow: hidden;
		color: var(--color-heading);
		font-weight: 600;
		text-overflow: ellipsis;
		white-space: nowrap;
	}
	.business-home__item-meta {
		display: flex;
		min-width: 0;
		gap: var(--space-small);
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		strong {
			color: var(--color-text);
			font-weight: 600;
			white-space: nowrap;
		}
		span {
			overflow: hidden;
			text-overflow: ellipsis;
			white-space: nowrap;
		}
	}
	.business-home__item-side {
		display: flex;
		flex: 0 0 auto;
		align-items: center;
		gap: var(--space-small);
	}
	.business-home__due {
		min-width: 88px;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		text-align: right;
	}
	.business-home__due--overdue {
		color: var(--color-critical);
		font-weight: 600;
	}
	.business-home__due--today {
		color: var(--color-heading);
		font-weight: 600;
	}
	.business-home__button-icon {
		display: inline-flex;
		margin-right: 4px;
		:global(svg) {
			width: 16px;
			height: 16px;
		}
	}
	.visually-hidden {
		position: absolute;
		width: 1px;
		height: 1px;
		overflow: hidden;
		clip-path: inset(50%);
		white-space: nowrap;
	}
	.business-home__more {
		padding: var(--space-base) var(--space-large);
		border-top: var(--border-base) solid var(--color-border);
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}
	.business-home__empty {
		display: grid;
		min-height: 200px;
		place-items: center;
		align-content: center;
		gap: var(--space-small);
		padding: var(--space-large);
		color: var(--color-text--secondary);
		text-align: center;
		strong {
			color: var(--color-heading);
		}
	}
	.business-home__empty-icon {
		display: grid;
		width: 40px;
		height: 40px;
		place-items: center;
		border-radius: var(--radius-base);
		color: var(--color-success--onSurface);
		background: var(--color-success--surface);
		:global(svg) {
			width: 22px;
			height: 22px;
		}
	}
	.business-home__alerts {
		margin: 0;
		padding: var(--space-small) var(--space-large);
		list-style: none;
		li + li {
			border-top: var(--border-base) solid var(--color-border);
		}
	}
	.business-home__alert {
		display: flex;
		align-items: center;
		gap: var(--space-base);
		padding: var(--space-base) 0;
		color: var(--color-text);
		text-decoration: none;
		&:hover strong {
			color: var(--color-interactive);
		}
	}
	.business-home__alert-icon {
		display: grid;
		width: 32px;
		height: 32px;
		flex: 0 0 32px;
		place-items: center;
		border-radius: var(--radius-base);
		color: var(--color-informative--onSurface);
		background: var(--color-informative--surface);
		:global(svg) {
			width: 18px;
			height: 18px;
		}
	}
	.business-home__alert-icon--warning {
		color: var(--color-warning--onSurface);
		background: var(--color-warning--surface);
	}
	.business-home__alert-icon--critical {
		color: var(--color-critical--onSurface);
		background: var(--color-critical--surface);
	}
	.business-home__alert-content {
		display: grid;
		min-width: 0;
		small {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}
	}
	.business-home__panel-footer {
		padding: var(--space-base) var(--space-large);
		border-top: var(--border-base) solid var(--color-border);
		a {
			display: inline-flex;
			align-items: center;
			gap: var(--space-smaller);
			color: var(--color-interactive);
			font-weight: 600;
			text-decoration: none;
		}
		span,
		:global(svg) {
			display: block;
			width: 18px;
			height: 18px;
		}
	}
	@media (max-width: 1100px) {
		.business-home__tiles {
			grid-template-columns: repeat(3, minmax(0, 1fr));
		}
		.business-home__grid:has(> :nth-child(2)) {
			grid-template-columns: minmax(0, 1fr);
		}
	}
	@media (max-width: 639px) {
		h1 {
			font-size: 28px;
		}
		.business-home__tiles {
			grid-template-columns: repeat(2, minmax(0, 1fr));
		}
		.business-home__list {
			padding: 0 var(--space-base) var(--space-small);
		}
		.business-home__group-title,
		.business-home__panel-header {
			padding-inline: var(--space-base);
		}
		// On a phone the step and business take the full width; the tag, date and Done sit underneath.
		.business-home__item {
			flex-wrap: wrap;
			gap: var(--space-small);
		}
		.business-home__item-link {
			flex-basis: 100%;
		}
		.business-home__item-side {
			width: 100%;
		}
		.business-home__due {
			min-width: 0;
			margin-right: auto;
			text-align: left;
		}
	}
</style>
