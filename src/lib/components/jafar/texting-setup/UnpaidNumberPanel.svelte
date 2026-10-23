<script lang="ts">
	import Button from '$lib/components/ui/Button.svelte';
	import Banner from '$lib/components/ui/Banner.svelte';
	import IconTile from '$lib/components/ui/IconTile.svelte';
	import StatusBadge from '$lib/components/ui/StatusBadge.svelte';
	import PaperworkFlag from '$lib/components/communications/paperwork/PaperworkFlag.svelte';
	import { countryDisplayName } from '$lib/settings/country-names';
	import { formatMinor } from '$lib/communications/sms-number-shop';
	import { historyTime, type UnpaidNumberTask } from '$lib/jafar/texting-setup';
	import buildingIcon from '@tabler/icons/outline/building-store.svg?raw';
	import refreshIcon from '@tabler/icons/outline/refresh.svg?raw';
	import calendarXIcon from '@tabler/icons/outline/calendar-x.svg?raw';
	import walletIcon from '@tabler/icons/outline/wallet.svg?raw';

	// An "Unpaid number" task (Stage 10 Part 7, board `QiDBX`): a number that couldn't renew, what it owes and the
	// business's balance, and its history. Nothing to press: a confirmed top-up pays it and the task closes; if
	// grace runs out the number is released.
	let { task, businessHref }: { task: UnpaidNumberTask; businessHref: string } = $props();

	const DAY_MS = 86_400_000;
	const daysLeft = $derived(
		Math.max(0, Math.ceil((new Date(task.grace_ends_at).getTime() - Date.now()) / DAY_MS))
	);
	const money = (minor: number) => formatMinor(minor, task.currency);
	const day = (iso: string) =>
		new Date(iso).toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
	const short = $derived(Math.max(0, task.amount_minor - Math.max(0, task.balance_minor)));
	const facts = $derived([
		{ label: 'This month', value: money(task.amount_minor) },
		{ label: 'Their balance', value: money(Math.max(0, task.balance_minor)) },
		{ label: 'Short by', value: money(short), critical: true },
		{ label: 'Unpaid since', value: day(task.requested_at) },
		{ label: 'Released on', value: day(task.grace_ends_at) }
	]);
	const historyIcon = {
		renewed: { icon: refreshIcon, tone: 'success' },
		failed: { icon: calendarXIcon, tone: 'critical' },
		warned: { icon: walletIcon, tone: 'warning' }
	} as const;
</script>

<!-- The inline SVG strings are trusted build-time Tabler icon imports. -->
<!-- eslint-disable svelte/no-at-html-tags -->
<section class="unpaid-panel" aria-labelledby="unpaid-panel-title">
	<header class="unpaid-panel__head">
		<PaperworkFlag code={task.country} size={40} />
		<div class="unpaid-panel__title">
			<div class="unpaid-panel__title-line">
				<h2 id="unpaid-panel-title">{task.name} couldn’t renew</h2>
				<StatusBadge status="critical">
					Unpaid · released {daysLeft === 0
						? 'today'
						: `in ${daysLeft} day${daysLeft === 1 ? '' : 's'}`}
				</StatusBadge>
			</div>
			<p>
				{task.organization_name} · {task.phone_number} · {countryDisplayName(task.country)} · {task.number_type}{task.owner_name
					? ` · owner ${task.owner_name}`
					: ''}
			</p>
		</div>
		<Button variant="secondary" size="small" href={businessHref}>
			<span aria-hidden="true">{@html buildingIcon}</span>
			Open {task.organization_name}
		</Button>
	</header>

	<div class="unpaid-panel__body">
		<dl class="unpaid-panel__facts">
			{#each facts as fact (fact.label)}
				<div>
					<dt>{fact.label}</dt>
					<dd class:unpaid-panel__critical={fact.critical}>{fact.value}</dd>
				</div>
			{/each}
		</dl>

		{#if task.history.length}
			<div class="unpaid-panel__history">
				<h3>History</h3>
				<ul>
					{#each task.history as event (`${event.kind}-${event.at}`)}
						<li>
							<IconTile
								icon={historyIcon[event.kind].icon}
								tone={historyIcon[event.kind].tone}
								size={24}
							/>
							<span class="unpaid-panel__history-text">{event.text}</span>
							<time datetime={event.at}>{historyTime(event.at)}</time>
						</li>
					{/each}
				</ul>
			</div>
		{/if}

		<Banner>
			Nothing to do here unless {task.organization_name} asks for help. When their top-up is confirmed,
			the renewal is paid at once and this task closes. If it’s still unpaid on {day(
				task.grace_ends_at
			)}, the number is released and their conversations are kept.
		</Banner>
	</div>
</section>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.unpaid-panel {
		display: flex;
		flex-direction: column;
		min-width: 0;
		overflow: hidden;
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-large);
		background: var(--color-surface);

		&__head {
			display: flex;
			align-items: flex-start;
			gap: var(--space-slim);
			padding: var(--space-medium) var(--space-large);
			border-bottom: var(--border-base) solid var(--color-border);

			:global(.button) {
				flex: none;
			}
		}

		&__title {
			flex: 1;
			min-width: 0;

			p {
				margin: var(--space-smaller) 0 0;
				color: var(--color-text--secondary);
				font-size: var(--typography--fontSize-small);
			}
		}

		&__title-line {
			display: flex;
			flex-wrap: wrap;
			align-items: center;
			gap: var(--space-small);

			h2 {
				margin: 0;
				color: var(--color-heading);
				font-size: var(--typography--fontSize-larger);
				font-weight: 700;
			}
		}

		&__body {
			display: flex;
			flex-direction: column;
			gap: var(--space-medium);
			padding: var(--space-large);
		}

		&__facts {
			display: flex;
			flex-wrap: wrap;
			gap: var(--space-large);
			margin: 0;
			padding: 14px var(--space-base);
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-tile-large);
			background: var(--color-surface--background--subtle);

			div {
				display: grid;
				gap: var(--space-smallest);
			}

			dt {
				color: var(--color-text--secondary);
				font-size: var(--typography--fontSize-smaller);
				font-weight: 500;
			}

			dd {
				margin: 0;
				color: var(--color-heading);
				font-size: var(--typography--fontSize-base);
				font-weight: 600;
			}
		}

		&__critical {
			color: var(--color-critical--onSurface) !important;
		}

		&__history {
			h3 {
				margin: 0 0 var(--space-small);
				color: var(--color-text--secondary);
				font-size: var(--typography--fontSize-overline);
				font-weight: 600;
				letter-spacing: 0.04em;
				text-transform: uppercase;
			}

			ul {
				display: flex;
				flex-direction: column;
				gap: var(--space-small);
				margin: 0;
				padding: 0;
				list-style: none;
			}

			li {
				display: flex;
				align-items: center;
				gap: var(--space-small);
			}

			time {
				flex: none;
				color: var(--color-text--secondary);
				font-size: var(--typography--fontSize-smaller);
			}
		}

		&__history-text {
			flex: 1;
			min-width: 0;
			color: var(--color-heading);
			font-size: var(--typography--fontSize-small);
			font-weight: 500;
		}
	}
</style>
