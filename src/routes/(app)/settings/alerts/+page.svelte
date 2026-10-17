<script lang="ts">
	import { onMount } from 'svelte';
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import { resolve } from '$app/paths';
	import Breadcrumbs from '$lib/components/layout/Breadcrumbs.svelte';
	import PageContainer from '$lib/components/layout/PageContainer.svelte';
	import Badge from '$lib/components/ui/Badge.svelte';
	import Banner from '$lib/components/ui/Banner.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import ConfirmDialog from '$lib/components/ui/ConfirmDialog.svelte';
	import Toggle from '$lib/components/ui/Toggle.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import {
		ALERT_GROUPS,
		ALERT_KIND_INFO,
		alertComputersKey,
		alertSettingsKey,
		fetchAlertComputers,
		fetchAlertSettings,
		saveAlertPreference,
		type AlertChannel,
		type AlertSettings,
		type AlertSettingsRow
	} from '$lib/team/alerts';
	import {
		browserAlertSupport,
		browserPermission,
		disableBrowserAlerts,
		enableBrowserAlerts,
		removeComputer,
		thisComputerEndpoint,
		type BrowserAlertSupport,
		type BrowserPermission
	} from '$lib/team/browser-alerts';
	import type { TeamNotificationKind } from '$lib/team/notifications';
	import bellIcon from '@tabler/icons/outline/bell-ringing.svg?raw';
	import deviceIcon from '@tabler/icons/outline/device-desktop.svg?raw';
	import trashIcon from '@tabler/icons/outline/trash.svg?raw';
	import calendarIcon from '@tabler/icons/outline/calendar.svg?raw';
	import messageIcon from '@tabler/icons/outline/message-circle.svg?raw';
	import fileTextIcon from '@tabler/icons/outline/file-text.svg?raw';
	import cashIcon from '@tabler/icons/outline/cash.svg?raw';
	import usersIcon from '@tabler/icons/outline/users.svg?raw';
	import starIcon from '@tabler/icons/outline/star.svg?raw';
	import stopwatchIcon from '@tabler/icons/outline/stopwatch.svg?raw';

	// My alerts (docs/alerts-behavior-contract.md): each person chooses, for themselves, whether an alert also
	// reaches their email or the browser on this computer. The bell always shows every alert they can receive.
	const queryClient = useQueryClient();
	const toast = getToastManager();

	const settings = createQuery(() => ({ queryKey: alertSettingsKey, queryFn: fetchAlertSettings }));
	const computers = createQuery(() => ({
		queryKey: alertComputersKey,
		queryFn: fetchAlertComputers
	}));

	// What this browser can do is only known once the page is in the browser.
	let support = $state<BrowserAlertSupport>('unsupported');
	let permission = $state<BrowserPermission>('default');
	let endpoint = $state<string | null>(null);
	let confirming = $state(false);
	let working = $state(false);

	async function refreshThisBrowser() {
		support = browserAlertSupport();
		permission = browserPermission();
		endpoint = await thisComputerEndpoint().catch(() => null);
	}
	onMount(() => void refreshThisBrowser());

	const thisComputer = $derived(
		endpoint ? (computers.data?.computers.find((item) => item.endpoint === endpoint) ?? null) : null
	);
	const rowsByKind = $derived(
		new Map<TeamNotificationKind, AlertSettingsRow>(
			(settings.data?.rows ?? []).map((row) => [row.kind, row])
		)
	);
	const groups = $derived(
		ALERT_GROUPS.map((group) => ({
			...group,
			rows: group.kinds.flatMap((kind) => {
				const row = rowsByKind.get(kind);
				return row ? [row] : [];
			})
		})).filter((group) => group.rows.length > 0)
	);

	// Each group's tile carries its meaning: the record colour of what the alerts are about.
	const GROUP_LOOK: Record<string, { icon: string; tone: string; surface: string }> = {
		schedule: { icon: calendarIcon, tone: 'var(--color-job)', surface: 'var(--color-job--surface)' },
		messages: {
			icon: messageIcon,
			tone: 'var(--color-informative--onSurface)',
			surface: 'var(--color-informative--surface)'
		},
		sales: { icon: fileTextIcon, tone: 'var(--color-quote)', surface: 'var(--color-quote--surface)' },
		money: { icon: cashIcon, tone: 'var(--color-invoice)', surface: 'var(--color-invoice--surface)' },
		team: { icon: usersIcon, tone: 'var(--color-task)', surface: 'var(--color-task--surface)' },
		reviews: {
			icon: starIcon,
			tone: 'var(--color-warning--onSurface)',
			surface: 'var(--color-warning--surface)'
		},
		time: { icon: stopwatchIcon, tone: 'var(--color-job)', surface: 'var(--color-job--surface)' }
	};

	// Two columns that keep the groups in order: the computers card plus the first groups fill the left
	// column until it holds about half of the page's rows, and the rest continue on the right.
	const columns = $derived.by(() => {
		const total = groups.reduce((sum, group) => sum + group.rows.length + 2, 7);
		let used = 7;
		const left: typeof groups = [];
		const right: typeof groups = [];
		for (const group of groups) {
			if (used < total / 2) {
				left.push(group);
				used += group.rows.length + 2;
			} else {
				right.push(group);
			}
		}
		return { left, right };
	});

	async function change(row: AlertSettingsRow, channel: AlertChannel, enabled: boolean) {
		const before = queryClient.getQueryData<AlertSettings>(alertSettingsKey);
		queryClient.setQueryData<AlertSettings>(alertSettingsKey, (current) =>
			current
				? {
						...current,
						rows: current.rows.map((item) =>
							item.kind === row.kind ? { ...item, [channel]: enabled } : item
						)
					}
				: current
		);
		try {
			await saveAlertPreference({ kind: row.kind, channel, enabled });
		} catch (error) {
			queryClient.setQueryData(alertSettingsKey, before);
			toast.error(
				error instanceof Error ? error.message : 'That alert setting could not be saved.'
			);
		}
	}

	async function turnOn() {
		const publicKey = computers.data?.public_key;
		if (!publicKey) return;
		confirming = false;
		working = true;
		try {
			const result = await enableBrowserAlerts(publicKey);
			await refreshThisBrowser();
			if (result === 'enabled') {
				toast.success('Browser alerts are on for this computer.');
				// A first computer also changes what the Browser column means.
				void queryClient.invalidateQueries({ queryKey: alertSettingsKey });
				void queryClient.invalidateQueries({ queryKey: alertComputersKey });
			} else if (result === 'blocked') {
				toast.error('Your browser blocked alerts. Follow the steps below to allow them.');
			}
		} catch (error) {
			toast.error(
				error instanceof Error ? error.message : 'Browser alerts could not be turned on.'
			);
		} finally {
			working = false;
		}
	}

	async function turnOff() {
		working = true;
		try {
			await disableBrowserAlerts();
			await refreshThisBrowser();
			toast.success('Browser alerts are off for this computer.');
			void queryClient.invalidateQueries({ queryKey: alertSettingsKey });
			void queryClient.invalidateQueries({ queryKey: alertComputersKey });
		} catch (error) {
			toast.error(
				error instanceof Error ? error.message : 'Browser alerts could not be turned off.'
			);
		} finally {
			working = false;
		}
	}

	async function remove(id: string, isThisOne: boolean) {
		working = true;
		try {
			if (isThisOne) await disableBrowserAlerts();
			else await removeComputer(id);
			await refreshThisBrowser();
			void queryClient.invalidateQueries({ queryKey: alertSettingsKey });
			void queryClient.invalidateQueries({ queryKey: alertComputersKey });
		} catch (error) {
			toast.error(error instanceof Error ? error.message : 'That computer could not be removed.');
		} finally {
			working = false;
		}
	}

	function addedOn(iso: string) {
		return new Date(iso).toLocaleDateString(undefined, {
			day: 'numeric',
			month: 'short',
			year: 'numeric'
		});
	}
</script>

<svelte:head><title>My alerts · Contractor CRM</title></svelte:head>

<PageContainer variant="open">
	<div class="alerts-page">
		<header class="alerts-page__header">
			<span class="alerts-page__header-icon" aria-hidden="true">
				<!-- eslint-disable-next-line svelte/no-at-html-tags -- a build-time Tabler icon, not user content -->
				{@html bellIcon}
			</span>
			<div class="alerts-page__header-copy">
				<Breadcrumbs
					items={[{ label: 'Settings', href: resolve('/(app)/settings') }, { label: 'Alerts' }]}
				/>
				<h1 id="alerts-title">My alerts</h1>
				<p>
					The bell at the top of the app always shows every alert you can receive. Here you choose
					whether an alert also reaches your email, or pops up in your browser even when the CRM is
					in the background. These choices are only yours.
				</p>
			</div>
		</header>

		<div class="alerts-page__columns">
			<div class="alerts-page__column">
				<section class="alerts-card" aria-labelledby="browser-title">
					<div class="alerts-card__heading">
						<!-- eslint-disable-next-line svelte/no-at-html-tags -->
						<span class="alerts-card__icon" aria-hidden="true">{@html deviceIcon}</span>
						<div>
							<h2 id="browser-title">Browser alerts on your computers</h2>
							<p>
								A pop-up on this computer for the alerts you switch on below, even when the CRM is
								not the window you are looking at.
							</p>
						</div>
					</div>

					<div class="alerts-card__body">
						{#if computers.isPending}
							<LoadingSkeleton variant="card" rows={2} />
						{:else if computers.isError}
							<ErrorState
								description="Your computers could not be loaded."
								retry={() => computers.refetch()}
							/>
						{:else if !computers.data.public_key}
							<Banner type="notice">Browser alerts are not set up on this server yet.</Banner>
						{:else if support === 'needs-home-screen'}
							<Banner type="notice">
								On iPhone and iPad, add the CRM to your Home Screen first (tap Share, then Add to
								Home Screen), open it from there, and come back to this page.
							</Banner>
						{:else if support === 'unsupported'}
							<Banner type="notice">
								This browser cannot show alerts. Chrome, Edge, Firefox and Safari on a computer, and
								Chrome on Android, can.
							</Banner>
						{:else if permission === 'denied'}
							<Banner type="warning">
								Your browser is blocking alerts from this site. Click the lock icon next to the
								address, set Notifications to Allow, then reload this page.
							</Banner>
						{:else if thisComputer}
							<div class="alerts-card__status">
								<Badge status="success" size="base">On for this computer</Badge>
								<Button
									variant="secondary"
									size="small"
									onclick={() => void turnOff()}
									disabled={working}>Turn off on this computer</Button
								>
							</div>
						{:else}
							<div class="alerts-card__status">
								<Badge status="inactive" size="base">Off for this computer</Badge>
								<Button onclick={() => (confirming = true)} loading={working} disabled={working}
									>Turn on for this computer</Button
								>
							</div>
						{/if}

						{#if computers.data && computers.data.computers.length > 0}
							<ul class="alerts-card__computers" aria-label="Computers that get your browser alerts">
								{#each computers.data.computers as computer (computer.id)}
									{@const isThisOne = computer.id === thisComputer?.id}
									<li class="alerts-card__computer">
										<div>
											<strong>{computer.label}</strong>
											{#if isThisOne}<Badge size="small">This computer</Badge>{/if}
											<span>Added {addedOn(computer.created_at)}</span>
										</div>
										<button
											type="button"
											class="alerts-card__remove"
											aria-label={`Remove ${computer.label}`}
											disabled={working}
											onclick={() => void remove(computer.id, isThisOne)}
										>
											<!-- eslint-disable-next-line svelte/no-at-html-tags -->
											<span aria-hidden="true">{@html trashIcon}</span>
											Remove
										</button>
									</li>
								{/each}
							</ul>
						{/if}
					</div>
				</section>

				{#if settings.isPending}
					<LoadingSkeleton variant="card" rows={4} />
				{:else if settings.isError}
					<ErrorState
						description="Your alert settings could not be loaded."
						retry={() => settings.refetch()}
					/>
				{:else}
					{#if !settings.data.has_device}
						<p class="alerts-page__hint">
							Turn on browser alerts for a computer above to use the Browser switches.
						</p>
					{/if}
					{#each columns.left as group (group.id)}
						{@render groupCard(group, settings.data.has_device)}
					{:else}
						<Banner type="notice">There are no alerts for your role yet.</Banner>
					{/each}
				{/if}
			</div>

			{#if settings.data && columns.right.length > 0}
				<div class="alerts-page__column">
					{#each columns.right as group (group.id)}
						{@render groupCard(group, settings.data.has_device)}
					{/each}
				</div>
			{/if}
		</div>
	</div>
</PageContainer>

{#snippet groupCard(group: (typeof groups)[number], hasComputer: boolean)}
	{@const look = GROUP_LOOK[group.id]}
	<section class="alerts-card" aria-labelledby={`group-${group.id}`}>
		<div class="alerts-card__heading">
			{#if look}
				<span
					class="alerts-card__icon"
					style={`--alerts-tone: ${look.tone}; --alerts-tone-surface: ${look.surface}`}
					aria-hidden="true"
					><!-- eslint-disable-next-line svelte/no-at-html-tags -->{@html look.icon}</span
				>
			{/if}
			<h2 id={`group-${group.id}`}>{group.label}</h2>
		</div>
		<div class="alerts-table" role="table" aria-labelledby={`group-${group.id}`}>
			<div class="alerts-table__head" role="row">
				<span role="columnheader">Alert</span>
				<span role="columnheader" class="alerts-table__channel">
					<!-- eslint-disable-next-line svelte/no-at-html-tags -->
					<span aria-hidden="true">{@html bellIcon}</span> Bell
				</span>
				<span role="columnheader" class="alerts-table__channel">Email</span>
				<span role="columnheader" class="alerts-table__channel">Browser</span>
			</div>
			{#each group.rows as row (row.kind)}
				{@const info = ALERT_KIND_INFO[row.kind]}
				<div class="alerts-table__row" role="row">
					<div class="alerts-table__what" role="cell">
						<strong>{info.label}</strong>
						<span>{info.description}</span>
					</div>
					<div class="alerts-table__cell" role="cell">
						<span class="alerts-table__mobile-name">Bell</span>
						<span class="alerts-table__always">Always on</span>
					</div>
					<div class="alerts-table__cell" role="cell">
						<span class="alerts-table__mobile-name">Email</span>
						<Toggle
							id={`email-${row.kind}`}
							label={`${info.label}: email`}
							checked={row.email}
							onchange={(checked) => void change(row, 'email', checked)}
						/>
					</div>
					<div class="alerts-table__cell" role="cell">
						<span class="alerts-table__mobile-name">Browser</span>
						<Toggle
							id={`browser-${row.kind}`}
							label={`${info.label}: browser`}
							checked={hasComputer && row.browser}
							disabled={!hasComputer}
							onchange={(checked) => void change(row, 'browser', checked)}
						/>
					</div>
				</div>
			{/each}
		</div>
	</section>
{/snippet}

<ConfirmDialog
	open={confirming}
	title="Allow alerts on this computer?"
	icon={bellIcon}
	confirmLabel="Enable"
	cancelLabel="Not now"
	onConfirm={() => void turnOn()}
	onClose={() => (confirming = false)}
>
	<p>
		Your browser will ask for permission next. After you allow it, you will see a pop-up for the
		alerts you switch on here, such as a Visit you were put on, a Task, or a customer's message.
	</p>
	<p>You can turn this off here at any time.</p>
</ConfirmDialog>

<style lang="scss">
	.alerts-page {
		display: grid;
		gap: var(--space-large);

		&__header {
			display: flex;
			align-items: flex-start;
			gap: 18px;
			margin-top: 16px;
		}

		&__header-icon {
			display: grid;
			flex: 0 0 auto;
			place-items: center;
			width: 60px;
			height: 60px;
			margin-top: 4px;
			border-radius: 18px;
			color: var(--color-text--reverse);
			background: var(--color-interactive);
			box-shadow: 0 6px 16px color-mix(in srgb, var(--color-interactive) 35%, transparent);

			:global(svg) {
				display: block;
				width: 28px;
				height: 28px;
			}
		}

		&__header-copy {
			min-width: 0;

			:global(.breadcrumbs) {
				margin-bottom: 4px;
				font-size: 13px;
				font-weight: 600;
			}

			:global(.breadcrumbs a svg) {
				display: none;
			}

			h1 {
				margin: 0;
				color: var(--color-heading);
				font-size: 36px;
				font-weight: 900;
				letter-spacing: -1.2px;
				line-height: var(--typography--lineHeight-tight);
			}

			p {
				max-width: 900px;
				margin: var(--space-smaller) 0 0;
				color: var(--color-text--secondary);
				font-size: 14px;
				font-weight: 500;
				line-height: var(--typography--lineHeight-large);
			}
		}

		// Two columns in group order; they stack into one column below laptop width.
		&__columns {
			display: grid;
			grid-template-columns: repeat(2, minmax(0, 1fr));
			gap: 20px;
			align-items: start;
		}

		&__column {
			display: grid;
			gap: 20px;
			min-width: 0;
		}

		&__hint {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: 13px;
		}
	}

	.alerts-card {
		display: grid;
		overflow: clip;
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface);

		h2 {
			margin: 0;
			color: var(--color-heading);
			font-size: var(--typography--fontSize-large);
			font-weight: 700;
			letter-spacing: -0.2px;
		}

		&__heading {
			display: flex;
			align-items: center;
			gap: var(--space-slim);
			padding: 20px 24px 16px;

			p {
				margin: 2px 0 0;
				color: var(--color-text--secondary);
				font-size: 13px;
				font-weight: 500;
			}
		}

		&__icon {
			display: grid;
			flex: 0 0 auto;
			place-items: center;
			width: 36px;
			height: 36px;
			border-radius: var(--radius-base);
			color: var(--alerts-tone, var(--color-job));
			background: var(--alerts-tone-surface, var(--color-job--surface));

			:global(svg) {
				display: block;
				width: 18px;
				height: 18px;
			}
		}

		&__body {
			display: grid;
			gap: var(--space-small);
			padding: 0 24px 20px;
		}

		&__status {
			display: flex;
			flex-wrap: wrap;
			align-items: center;
			justify-content: space-between;
			gap: var(--space-small);
			padding: 10px 12px;
			border-radius: var(--radius-base);
			background: var(--color-surface--background--subtle);
		}

		&__computers {
			display: grid;
			margin: 0;
			padding: 0;
			list-style: none;
		}

		&__computer {
			display: flex;
			align-items: center;
			justify-content: space-between;
			gap: var(--space-base);
			padding: var(--space-slim) 0;
			border-bottom: var(--border-base) solid var(--color-border);

			&:last-child {
				border-bottom: 0;
				padding-bottom: 0;
			}

			div {
				display: flex;
				flex-wrap: wrap;
				align-items: center;
				gap: var(--space-small);
			}

			strong {
				color: var(--color-heading);
				font-weight: 600;
			}

			span {
				color: var(--color-text--secondary);
				font-size: var(--typography--fontSize-small);
			}
		}

		&__remove {
			display: inline-flex;
			align-items: center;
			gap: var(--space-smaller);
			padding: var(--space-smaller) var(--space-small);
			border: 0;
			border-radius: var(--radius-base);
			color: var(--color-critical);
			background: transparent;
			font: inherit;
			cursor: pointer;

			:global(svg) {
				display: block;
				width: 16px;
				height: 16px;
			}

			&:hover:not(:disabled) {
				background: var(--color-critical--surface);
			}

			&:focus-visible {
				outline: none;
				box-shadow: var(--shadow-focus);
			}

			&:disabled {
				opacity: 0.6;
				cursor: not-allowed;
			}
		}
	}

	.alerts-table {
		display: grid;

		&__head,
		&__row {
			display: grid;
			grid-template-columns: minmax(0, 1fr) 84px 64px 64px;
			align-items: center;
			gap: var(--space-small);
			padding-inline: 24px;
		}

		&__head {
			padding-block: 10px;
			border-block: var(--border-base) solid var(--color-border);
			color: var(--color-text--secondary);
			background: var(--color-surface--background--subtle);
			font-size: 12px;
			font-weight: 600;
		}

		&__channel {
			display: inline-flex;
			align-items: center;
			justify-content: center;
			gap: var(--space-smaller);

			:global(svg) {
				display: block;
				width: 14px;
				height: 14px;
			}
		}

		&__row {
			padding-block: 12px;
			border-bottom: var(--border-base) solid var(--color-border);

			&:last-child {
				border-bottom: 0;
			}
		}

		&__cell {
			display: flex;
			align-items: center;
			justify-content: center;
		}

		&__what {
			display: grid;
			gap: 2px;

			strong {
				color: var(--color-heading);
				font-size: 14px;
				font-weight: 600;
			}

			span {
				color: var(--color-text--secondary);
				font-size: 12px;
				font-weight: 500;
			}
		}

		&__always {
			color: var(--color-text--secondary);
			font-size: 12px;
			white-space: nowrap;
		}

		&__mobile-name {
			display: none;
		}

		// The switch stands alone in its column; its label is only for screen readers.
		&__cell :global(.toggle__content) {
			position: absolute;
			width: 1px;
			height: 1px;
			overflow: hidden;
			clip: rect(0 0 0 0);
			white-space: nowrap;
		}

		@media (max-width: 720px) {
			&__head {
				display: none;
			}

			&__row {
				grid-template-columns: repeat(3, minmax(0, 1fr));
				gap: var(--space-small) var(--space-base);
			}

			&__what {
				grid-column: 1 / -1;
			}

			&__cell {
				display: grid;
				gap: var(--space-smaller);
				justify-items: start;
			}

			&__mobile-name {
				display: block;
				color: var(--color-text--secondary);
				font-size: var(--typography--fontSize-small);
			}
		}
	}

	@media (max-width: 1079px) {
		.alerts-page__columns {
			grid-template-columns: minmax(0, 1fr);
		}
	}
</style>
