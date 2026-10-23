<script lang="ts">
	import Avatar from '$lib/components/ui/Avatar.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import CardHeader from '$lib/components/ui/CardHeader.svelte';
	import DropdownMenu from '$lib/components/ui/DropdownMenu.svelte';
	import StatusBadge from '$lib/components/ui/StatusBadge.svelte';
	import MessengerMark from './MessengerMark.svelte';
	import { relativeTime } from '$lib/collaboration/format';
	import type {
		MessengerConnection,
		MessengerReconnectReason
	} from '$lib/communications/messenger-settings';
	import messagesIcon from '@tabler/icons/outline/messages.svg?raw';
	import plusIcon from '@tabler/icons/outline/plus.svg?raw';
	import starIcon from '@tabler/icons/outline/star.svg?raw';
	import refreshIcon from '@tabler/icons/outline/refresh.svg?raw';
	import externalLinkIcon from '@tabler/icons/outline/external-link.svg?raw';
	import plugXIcon from '@tabler/icons/outline/plug-x.svg?raw';
	import shieldOffIcon from '@tabler/icons/outline/shield-off.svg?raw';
	import arrowRightIcon from '@tabler/icons/outline/arrow-right.svg?raw';

	// Every connected Page as one row (board `tEAXY`, Approved B): picture, status, last message and the ⋯ menu.
	// A Page Facebook stopped serving carries a red strip under its row saying why, with Reconnect.
	let {
		connections,
		defaultSavingId,
		loggingIn,
		onConnect,
		onReconnect,
		onMakeDefault,
		onDisconnect,
		onTest
	}: {
		connections: MessengerConnection[];
		defaultSavingId: string | null;
		loggingIn: boolean;
		onConnect: () => void;
		onReconnect: (connection: MessengerConnection) => void;
		onMakeDefault: (connection: MessengerConnection) => void;
		onDisconnect: (connection: MessengerConnection) => void;
		onTest: (connection: MessengerConnection) => void;
	} = $props();

	const STATUS = {
		receiving: { label: 'Receiving', tone: 'success' },
		waiting: { label: 'Waiting for a test', tone: 'informative' },
		reconnect: { label: 'Reconnect needed', tone: 'critical' }
	} as const;

	const dayFormat = new Intl.DateTimeFormat(undefined, { month: 'short', day: 'numeric' });

	function shortDay(value: string) {
		const date = new Date(value);
		return date.toDateString() === new Date().toDateString() ? 'Today' : dayFormat.format(date);
	}

	function reasonText(reason: MessengerReconnectReason, since: string | null) {
		if (reason === 'permission_missing')
			return "Someone removed this app's access to the Page on Facebook. Reconnect and allow access to messages.";
		if (reason === 'webhook_unsubscribed')
			return 'Facebook paused message delivery to us. Reconnect this Page to receive messages again.';
		return `Facebook ended this connection${since ? ` on ${dayFormat.format(new Date(since))}` : ''}, so new messages are not arriving. Old conversations are safe.`;
	}

	function menuItems(connection: MessengerConnection) {
		return [
			...(connection.is_default
				? []
				: [
						{
							label: 'Make default',
							icon: starIcon,
							disabled: defaultSavingId !== null,
							onSelect: () => onMakeDefault(connection)
						}
					]),
			...(connection.status === 'reconnect'
				? [{ label: 'Reconnect', icon: refreshIcon, onSelect: () => onReconnect(connection) }]
				: []),
			{
				label: 'Open on Facebook',
				icon: externalLinkIcon,
				onSelect: () =>
					window.open(
						`https://www.facebook.com/${connection.page_id}`,
						'_blank',
						'noopener,noreferrer'
					)
			},
			{
				label: 'Disconnect',
				icon: plugXIcon,
				destructive: true,
				onSelect: () => onDisconnect(connection)
			}
		];
	}
</script>

<!-- eslint-disable svelte/no-at-html-tags -- trusted build-time Tabler icons -->
<section class="messenger-pages" aria-labelledby="messenger-pages-title">
	<CardHeader
		id="messenger-pages-title"
		title="Facebook Pages"
		hint="New Messenger conversations start from the default Page."
		icon={messagesIcon}
		tone="conversation"
	/>
	<div class="messenger-pages__heads" aria-hidden="true">
		<span class="messenger-pages__page">Page</span>
		<span class="messenger-pages__status">Status</span>
		<span class="messenger-pages__last">Last message</span>
		<span class="messenger-pages__menu"></span>
	</div>
	<ul class="messenger-pages__list">
		{#each connections as connection (connection.id)}
			{@const status = STATUS[connection.status]}
			<li class="messenger-pages__row">
				<div class="messenger-pages__line">
					<div class="messenger-pages__page">
						<span class="messenger-pages__picture">
							<Avatar id={connection.page_id} name={connection.page_name} size="medium" />
							<span class="messenger-pages__badge"><MessengerMark size={18} /></span>
						</span>
						<span class="messenger-pages__who">
							<span class="messenger-pages__title-line">
								<span class="messenger-pages__name">{connection.page_name}</span>
								{#if connection.is_default}
									<span class="messenger-pages__default">
										<span aria-hidden="true">{@html starIcon}</span>
										Default
									</span>
								{/if}
							</span>
							<span class="messenger-pages__meta">
								{connection.connected_by_name
									? `Connected by ${connection.connected_by_name}`
									: 'Connected'} · {shortDay(connection.connected_at)}
							</span>
						</span>
					</div>
					<div class="messenger-pages__status">
						<StatusBadge status={status.tone}>{status.label}</StatusBadge>
					</div>
					<div class="messenger-pages__last">
						{#if connection.status === 'reconnect'}
							<span class="messenger-pages__when">
								{connection.problem_at ? dayFormat.format(new Date(connection.problem_at)) : '—'}
							</span>
							<span class="messenger-pages__meta">Stopped arriving</span>
						{:else if connection.last_message}
							<span class="messenger-pages__when">{relativeTime(connection.last_message.at)}</span>
							<span class="messenger-pages__meta">{connection.last_message.client_name}</span>
						{:else}
							<span class="messenger-pages__when">No messages yet</span>
							<button
								type="button"
								class="messenger-pages__test"
								onclick={() => onTest(connection)}
							>
								Use the live test <span aria-hidden="true">{@html arrowRightIcon}</span>
							</button>
						{/if}
					</div>
					<div class="messenger-pages__menu">
						<DropdownMenu
							triggerLabel={`More for ${connection.page_name}`}
							items={menuItems(connection)}
						/>
					</div>
				</div>
				{#if connection.status === 'reconnect' && connection.reason}
					<div class="messenger-pages__fix">
						<div class="messenger-pages__strip" role="status">
							<span class="messenger-pages__strip-icon" aria-hidden="true">
								{@html connection.reason === 'permission_missing' ? shieldOffIcon : plugXIcon}
							</span>
							<p>{reasonText(connection.reason, connection.problem_at)}</p>
							<Button size="small" loading={loggingIn} onclick={() => onReconnect(connection)}>
								<span aria-hidden="true">{@html refreshIcon}</span>
								Reconnect
							</Button>
						</div>
					</div>
				{/if}
			</li>
		{/each}
	</ul>
	<button type="button" class="messenger-pages__add" disabled={loggingIn} onclick={onConnect}>
		<span aria-hidden="true">{@html plusIcon}</span>
		Connect another Page
	</button>
</section>

<style lang="scss">
	.messenger-pages {
		overflow: hidden;
		border: 1px solid var(--color-border);
		border-radius: var(--radius-large);
		background: var(--color-surface);

		&__heads,
		&__line {
			display: flex;
			align-items: center;
			gap: var(--space-base);
		}
		&__heads {
			padding: 10px var(--space-medium);
			border-top: 1px solid var(--color-border);
			border-bottom: 1px solid var(--color-border);
			color: var(--color-text--secondary);
			background: var(--color-surface--background--subtle);
			font-size: var(--typography--fontSize-overline);
			font-weight: 700;
			letter-spacing: 0.4px;
			text-transform: uppercase;
		}
		&__page {
			display: flex;
			flex: 1;
			align-items: center;
			min-width: 0;
			gap: var(--space-slim);
		}
		&__status {
			flex: 0 0 170px;
		}
		&__last {
			display: grid;
			flex: 0 0 130px;
			gap: 2px;
			min-width: 0;
		}
		&__menu {
			display: flex;
			flex: 0 0 32px;
			justify-content: flex-end;
		}
		&__list {
			margin: 0;
			padding: 0;
			list-style: none;
		}
		&__row + &__row {
			border-top: 1px solid var(--color-border);
		}
		&__line {
			padding: var(--space-base) var(--space-medium);
		}
		&__picture {
			position: relative;
			flex: 0 0 auto;
		}
		&__badge {
			position: absolute;
			right: -3px;
			bottom: -3px;
			display: flex;
		}
		&__who {
			display: grid;
			min-width: 0;
			gap: 2px;
		}
		&__title-line {
			display: flex;
			align-items: center;
			gap: var(--space-small);
			min-width: 0;
		}
		&__name {
			overflow: hidden;
			color: var(--color-heading);
			font-size: var(--typography--fontSize-base);
			font-weight: 600;
			text-overflow: ellipsis;
			white-space: nowrap;
		}
		&__default {
			display: inline-flex;
			flex: 0 0 auto;
			align-items: center;
			gap: var(--space-smaller);
			padding: 2px var(--space-small);
			border-radius: var(--radius-circle);
			color: var(--color-heading);
			background: var(--color-inactive--surface);
			font-size: var(--typography--fontSize-overline);
			font-weight: 600;

			:global(svg) {
				width: 12px;
				height: 12px;
			}
		}
		&__meta {
			overflow: hidden;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-smaller);
			font-weight: 500;
			text-overflow: ellipsis;
			white-space: nowrap;
		}
		&__when {
			color: var(--color-heading);
			font-size: var(--typography--fontSize-small);
			font-weight: 600;
		}
		&__test {
			display: inline-flex;
			align-items: center;
			justify-self: start;
			gap: var(--space-smaller);
			padding: 0;
			border: 0;
			border-radius: var(--radius-small);
			color: var(--color-interactive);
			background: none;
			font: inherit;
			font-size: var(--typography--fontSize-smaller);
			font-weight: 600;
			cursor: pointer;

			:global(svg) {
				width: 14px;
				height: 14px;
			}
			&:hover {
				text-decoration: underline;
			}
			&:focus-visible {
				outline: none;
				box-shadow: var(--shadow-focus);
			}
		}
		&__fix {
			padding: 0 var(--space-medium) var(--space-base) 72px;
		}
		&__strip {
			display: flex;
			align-items: center;
			gap: var(--space-slim);
			padding: 10px 10px 10px 14px;
			border: 1px solid var(--color-critical--surface-edge);
			border-radius: var(--radius-base);
			background: var(--color-critical--surface);

			p {
				flex: 1;
				color: var(--color-critical--onSurface);
				font-size: var(--typography--fontSize-smaller);
				font-weight: 500;
				line-height: 1.45;
			}
		}
		&__strip-icon {
			display: flex;
			color: var(--color-critical);

			:global(svg) {
				width: 16px;
				height: 16px;
			}
		}
		&__add {
			display: flex;
			align-items: center;
			width: 100%;
			gap: var(--space-small);
			padding: 14px var(--space-medium);
			border: 0;
			border-top: 1px solid var(--color-border);
			color: var(--color-interactive);
			background: var(--color-surface--background--subtle);
			font: inherit;
			font-size: var(--typography--fontSize-small);
			font-weight: 600;
			text-align: left;
			cursor: pointer;

			:global(svg) {
				width: 16px;
				height: 16px;
			}
			&:hover:not(:disabled) {
				background: var(--color-surface--hover);
			}
			&:focus-visible {
				outline: none;
				box-shadow: inset var(--shadow-focus);
			}
			&:disabled {
				color: var(--color-text--secondary);
				opacity: 0.6;
				cursor: default;
			}
		}
	}
	@media (max-width: 700px) {
		.messenger-pages {
			&__heads {
				display: none;
			}
			&__line {
				display: grid;
				grid-template-columns: minmax(0, 1fr) auto;
				padding: var(--space-base);
			}
			&__page {
				grid-column: 1;
			}
			&__menu {
				grid-column: 2;
				grid-row: 1;
			}
			&__title-line {
				flex-wrap: wrap;
			}
			&__name {
				white-space: normal;
				overflow-wrap: anywhere;
			}
			&__status,
			&__last {
				grid-column: 1 / -1;
			}
			&__fix {
				padding: 0 var(--space-base) var(--space-base);
			}
			&__strip {
				display: grid;
				grid-template-columns: auto minmax(0, 1fr);
				align-items: start;
				:global(.button) {
					grid-column: 2;
					justify-self: start;
				}
			}
		}
	}
</style>
