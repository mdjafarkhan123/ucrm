<script lang="ts">
	import { Popover } from 'bits-ui';
	import { createMutation, createQuery, useQueryClient } from '@tanstack/svelte-query';
	import { goto } from '$app/navigation';
	import { resolve } from '$app/paths';
	import bellIcon from '@tabler/icons/outline/bell.svg?raw';
	import {
		exactTime,
		fetchNotifications,
		notificationHref,
		notificationsKey,
		relativeTime,
		severityLabel,
		updateNotificationRead,
		type NotificationListResponse,
		type OwnerNotification
	} from '$lib/jafar/notifications';

	const RECENT_LIMIT = 10;

	let open = $state(false);
	let actionError = $state('');
	const queryClient = useQueryClient();

	/**
	 * The bell polls rather than streams. Live unread depends on the QueryClient ownership
	 * work that is still open, and a minute-old count plus a refresh on tab focus is honest
	 * enough for work that is measured in hours.
	 */
	const recent = createQuery<NotificationListResponse>(() => ({
		queryKey: [...notificationsKey, 'recent'],
		queryFn: () => fetchNotifications({ status: 'all', limit: RECENT_LIMIT }),
		refetchInterval: 60_000,
		refetchOnWindowFocus: true
	}));

	const notifications = $derived(recent.data?.notifications ?? []);
	const unreadCount = $derived(recent.data?.unread_count ?? 0);
	const unreadLabel = $derived(unreadCount > 99 ? '99+' : String(unreadCount));

	const markAllRead = createMutation(() => ({
		mutationFn: () => updateNotificationRead({ all: true }),
		onSuccess: () => {
			actionError = '';
			void queryClient.invalidateQueries({ queryKey: notificationsKey });
		},
		onError: (error: Error) => {
			actionError = error.message;
		}
	}));

	async function openNotification(notification: OwnerNotification) {
		open = false;
		const href = notificationHref(notification);
		try {
			if (!notification.read_at) {
				await updateNotificationRead({ ids: [notification.id], read: true });
				void queryClient.invalidateQueries({ queryKey: notificationsKey });
			}
		} catch (error) {
			// Losing the read mark is not a reason to keep Jafar from the record itself.
			console.error('Could not mark the notification read.', error);
		}
		// eslint-disable-next-line svelte/no-navigation-without-resolve -- notificationHref() already resolves the path; the route is only known at runtime.
		await goto(href);
	}
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<Popover.Root bind:open>
	<Popover.Trigger
		class="notification-bell__trigger"
		aria-label={unreadCount > 0
			? `Notifications, ${unreadCount} unread`
			: 'Notifications, all read'}
	>
		<span class="notification-bell__icon" aria-hidden="true">{@html bellIcon}</span>
		{#if unreadCount > 0}
			<span class="notification-bell__count" aria-hidden="true">{unreadLabel}</span>
		{/if}
	</Popover.Trigger>
	<Popover.Portal>
		<Popover.Content
			class="notification-bell__panel"
			align="end"
			sideOffset={8}
			collisionPadding={12}
		>
			<header class="notification-bell__header">
				<h2>Notifications</h2>
				{#if unreadCount > 0}
					<button
						class="notification-bell__mark-all"
						type="button"
						onclick={() => markAllRead.mutate()}
						disabled={markAllRead.isPending}
					>
						{markAllRead.isPending ? 'Marking…' : 'Mark all read'}
					</button>
				{/if}
			</header>

			{#if actionError}
				<p class="notification-bell__error" role="alert">{actionError}</p>
			{/if}

			<div class="notification-bell__list">
				{#if recent.isPending}
					<p class="notification-bell__muted">Loading…</p>
				{:else if recent.isError}
					<p class="notification-bell__error" role="alert">
						{recent.error instanceof Error
							? recent.error.message
							: 'Notifications could not be loaded.'}
					</p>
				{:else if notifications.length === 0}
					<p class="notification-bell__muted">
						Nothing yet. New applications and failures land here.
					</p>
				{:else}
					{#each notifications as notification (notification.id)}
						<button
							class="notification-bell__item"
							class:notification-bell__item--unread={!notification.read_at}
							type="button"
							onclick={() => void openNotification(notification)}
						>
							<span
								class="notification-bell__dot"
								class:notification-bell__dot--attention={notification.severity === 'attention'}
								class:notification-bell__dot--urgent={notification.severity === 'urgent'}
								aria-hidden="true"
							></span>
							<span class="notification-bell__item-text">
								<span class="notification-bell__item-title">{notification.title}</span>
								{#if notification.body}
									<span class="notification-bell__item-body">{notification.body}</span>
								{/if}
								<span
									class="notification-bell__item-meta"
									title={exactTime(notification.created_at)}
								>
									{severityLabel(notification.severity)} · {relativeTime(notification.created_at)}
								</span>
							</span>
						</button>
					{/each}
				{/if}
			</div>

			<footer class="notification-bell__footer">
				<a href={resolve('/jafar/notifications')} onclick={() => (open = false)}>View all</a>
			</footer>
		</Popover.Content>
	</Popover.Portal>
</Popover.Root>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	:global(.notification-bell__trigger) {
		position: relative;
		display: inline-grid;
		width: 40px;
		height: 40px;
		place-items: center;
		padding: 0;
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		color: var(--color-icon);
		background: var(--color-surface);
		cursor: pointer;
		transition: all var(--timing-base) ease-out;

		&:hover {
			border-color: var(--color-border--interactive);
			background: var(--color-surface--hover);
		}

		&:focus-visible {
			outline: none;
			box-shadow: var(--shadow-focus);
		}
	}

	.notification-bell__icon,
	.notification-bell__icon :global(svg) {
		display: inline-flex;
		width: 20px;
		height: 20px;
	}

	.notification-bell__count {
		position: absolute;
		top: -6px;
		right: -6px;
		min-width: 18px;
		padding: 0 var(--space-smallest);
		border-radius: var(--radius-large);
		background: var(--color-critical);
		color: var(--color-text--reverse);
		font-size: var(--typography--fontSize-smaller);
		font-weight: 600;
		line-height: 18px;
		text-align: center;
	}

	:global(.notification-bell__panel) {
		z-index: var(--elevation-menu);
		display: flex;
		width: min(380px, calc(100vw - var(--space-large) * 2));
		max-height: min(70vh, 520px);
		flex-direction: column;
		overflow: hidden;
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface);
		box-shadow: var(--shadow-high);
	}

	.notification-bell__header {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-base);
		padding: var(--space-base);
		border-bottom: var(--border-base) solid var(--color-border);

		h2 {
			color: var(--color-heading);
			font-size: var(--typography--fontSize-base);
			font-weight: 600;
		}
	}

	.notification-bell__mark-all {
		border: 0;
		background: transparent;
		color: var(--color-interactive);
		font-size: var(--typography--fontSize-small);
		cursor: pointer;

		&:hover:not(:disabled) {
			text-decoration: underline;
		}

		&:focus-visible {
			outline: none;
			box-shadow: var(--shadow-focus);
		}
	}

	.notification-bell__list {
		flex: 1;
		overflow-y: auto;
	}

	.notification-bell__item {
		display: flex;
		width: 100%;
		align-items: flex-start;
		gap: var(--space-small);
		padding: var(--space-base);
		border: 0;
		border-bottom: var(--border-base) solid var(--color-border);
		background: transparent;
		text-align: left;
		cursor: pointer;

		&:hover {
			background: var(--color-surface--hover);
		}

		&:focus-visible {
			outline: none;
			box-shadow: var(--shadow-focus);
		}

		&--unread {
			background: var(--color-surface--background--subtle);
		}
	}

	.notification-bell__dot {
		width: 8px;
		height: 8px;
		flex: 0 0 auto;
		margin-top: 6px;
		border-radius: 50%;
		background: var(--color-border--interactive);

		&--attention {
			background: var(--color-warning);
		}

		&--urgent {
			background: var(--color-critical);
		}
	}

	.notification-bell__item-text {
		display: flex;
		min-width: 0;
		flex-direction: column;
		gap: var(--space-smallest);
	}

	.notification-bell__item-title {
		color: var(--color-heading);
		font-size: var(--typography--fontSize-small);
	}

	.notification-bell__item--unread .notification-bell__item-title {
		font-weight: 600;
	}

	.notification-bell__item-body {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		overflow: hidden;
		display: -webkit-box;
		-webkit-box-orient: vertical;
		-webkit-line-clamp: 2;
		line-clamp: 2;
	}

	.notification-bell__item-meta {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-smaller);
	}

	.notification-bell__footer {
		padding: var(--space-small) var(--space-base);
		border-top: var(--border-base) solid var(--color-border);
		text-align: center;

		a {
			color: var(--color-interactive);
			font-size: var(--typography--fontSize-small);
		}
	}

	.notification-bell__muted,
	.notification-bell__error {
		padding: var(--space-base);
		font-size: var(--typography--fontSize-small);
	}

	.notification-bell__muted {
		color: var(--color-text--secondary);
	}

	.notification-bell__error {
		color: var(--color-critical);
	}
</style>
