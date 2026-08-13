<script lang="ts">
	import { createMutation, createQuery, useQueryClient } from '@tanstack/svelte-query';
	import { goto } from '$app/navigation';
	import bellIcon from '@tabler/icons/outline/bell.svg?raw';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import EmptyState from '$lib/components/data-display/EmptyState.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import Badge from '$lib/components/ui/Badge.svelte';
	import SearchInput from '$lib/components/ui/SearchInput.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import {
		exactTime,
		fetchNotifications,
		notificationHref,
		notificationsKey,
		relativeTime,
		severityLabel,
		updateNotificationRead,
		type NotificationListResponse,
		type NotificationSeverity,
		type OwnerNotification
	} from '$lib/jafar/notifications';

	const statusOptions = [
		{ value: 'unread', label: 'Unread' },
		{ value: 'all', label: 'Everything' }
	];

	let statusFilter = $state('unread');
	const status = $derived(statusFilter === 'all' ? 'all' : ('unread' as const));
	let search = $state('');
	let actionError = $state('');
	const queryClient = useQueryClient();

	const history = createQuery<NotificationListResponse>(() => ({
		queryKey: [...notificationsKey, 'history', status, search],
		queryFn: () => fetchNotifications({ status, search: search.trim(), limit: 100 })
	}));

	const notifications = $derived(history.data?.notifications ?? []);
	const unreadCount = $derived(history.data?.unread_count ?? 0);

	const setRead = createMutation(() => ({
		mutationFn: (variables: { id: string; read: boolean }) =>
			updateNotificationRead({ ids: [variables.id], read: variables.read }),
		onSuccess: () => {
			actionError = '';
			void queryClient.invalidateQueries({ queryKey: notificationsKey });
		},
		onError: (error: Error) => {
			actionError = error.message;
		}
	}));

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

	function severityTone(severity: NotificationSeverity) {
		return severity === 'urgent'
			? 'critical'
			: severity === 'attention'
				? 'warning'
				: 'informative';
	}

	async function openNotification(notification: OwnerNotification) {
		const href = notificationHref(notification);
		try {
			if (!notification.read_at) {
				await updateNotificationRead({ ids: [notification.id], read: true });
				void queryClient.invalidateQueries({ queryKey: notificationsKey });
			}
		} catch (error) {
			// The record still matters more than the read mark.
			console.error('Could not mark the notification read.', error);
		}
		// eslint-disable-next-line svelte/no-navigation-without-resolve -- notificationHref() already resolves the path; the route is only known at runtime.
		await goto(href);
	}
</script>

<svelte:head>
	<title>Notifications · Control Room</title>
</svelte:head>

<main class="notifications">
	<header class="notifications__header">
		<div>
			<p class="notifications__eyebrow">Activity</p>
			<h1>Notifications</h1>
			<p class="notifications__description">
				Everything the platform has flagged for you, newest first. Open one to jump straight to the
				record it is about.
			</p>
		</div>
		{#if unreadCount > 0}
			<button
				class="notifications__mark-all"
				type="button"
				onclick={() => markAllRead.mutate()}
				disabled={markAllRead.isPending}
			>
				{markAllRead.isPending ? 'Marking…' : `Mark all read (${unreadCount})`}
			</button>
		{/if}
	</header>

	<section class="notifications__filters" aria-label="Notification filters">
		<div class="notifications__filter-field notifications__filter-field--search">
			<label for="notification-search">Search</label>
			<SearchInput
				id="notification-search"
				bind:value={search}
				placeholder="Search notifications"
				ariaLabel="Search notifications"
			/>
		</div>
		<div class="notifications__filter-field">
			<label for="notification-status">Show</label>
			<Select
				id="notification-status"
				bind:value={statusFilter}
				options={statusOptions}
				ariaLabel="Filter notifications by read state"
			/>
		</div>
	</section>

	{#if actionError}
		<p class="notifications__error" role="alert">{actionError}</p>
	{/if}

	<section class="notifications__panel" aria-labelledby="notification-list-title">
		<h2 id="notification-list-title" class="notifications__sr-only">Notification list</h2>
		{#if history.isPending}
			<div class="notifications__state">
				<LoadingSkeleton variant="table" rows={6} label="Loading notifications" />
			</div>
		{:else if history.isError}
			<div class="notifications__state">
				<ErrorState
					title="Notifications could not be loaded"
					description={history.error.message}
					retry={() => history.refetch()}
				/>
			</div>
		{:else if notifications.length === 0}
			<div class="notifications__state">
				<EmptyState
					icon={bellIcon}
					title={status === 'unread' ? 'Nothing unread' : 'Nothing here yet'}
					description={search
						? 'No notification matches that search.'
						: status === 'unread'
							? 'You are caught up. New applications and failures show up here.'
							: 'New applications and failures show up here.'}
				/>
			</div>
		{:else}
			<ul class="notifications__list">
				{#each notifications as notification (notification.id)}
					<li class="notifications__item" class:notifications__item--unread={!notification.read_at}>
						<button
							class="notifications__open"
							type="button"
							onclick={() => void openNotification(notification)}
						>
							<span class="notifications__item-head">
								<span class="notifications__item-title">{notification.title}</span>
								<Badge status={severityTone(notification.severity)} size="small">
									{severityLabel(notification.severity)}
								</Badge>
							</span>
							{#if notification.body}
								<span class="notifications__item-body">{notification.body}</span>
							{/if}
							<span class="notifications__item-meta" title={exactTime(notification.created_at)}>
								{relativeTime(notification.created_at)} · {exactTime(notification.created_at)}
							</span>
						</button>
						<button
							class="notifications__toggle"
							type="button"
							disabled={setRead.isPending}
							onclick={() => setRead.mutate({ id: notification.id, read: !notification.read_at })}
						>
							{notification.read_at ? 'Mark unread' : 'Mark read'}
						</button>
					</li>
				{/each}
			</ul>
		{/if}
	</section>
</main>

<style lang="scss">
	.notifications {
		display: flex;
		flex-direction: column;
		gap: var(--space-large);
	}

	.notifications__header {
		display: flex;
		align-items: flex-start;
		justify-content: space-between;
		gap: var(--space-base);

		h1 {
			color: var(--color-heading);
			font-size: var(--typography--fontSize-largest);
		}
	}

	.notifications__eyebrow {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}

	.notifications__description {
		max-width: 62ch;
		margin-top: var(--space-smaller);
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}

	.notifications__mark-all {
		min-height: 40px;
		flex: 0 0 auto;
		padding: 0 var(--space-base);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		color: var(--color-heading);
		background: var(--color-surface);
		cursor: pointer;

		&:hover:not(:disabled) {
			background: var(--color-surface--hover);
		}

		&:focus-visible {
			outline: none;
			box-shadow: var(--shadow-focus);
		}
	}

	.notifications__filters {
		display: flex;
		flex-wrap: wrap;
		align-items: flex-end;
		gap: var(--space-base);
	}

	.notifications__filter-field {
		display: flex;
		min-width: 200px;
		flex-direction: column;
		gap: var(--space-smaller);

		label {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&--search {
			flex: 1 1 320px;
		}
	}

	.notifications__panel {
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface);
		overflow: hidden;
	}

	.notifications__state {
		padding: var(--space-large);
	}

	.notifications__list {
		list-style: none;
		margin: 0;
		padding: 0;
	}

	.notifications__item {
		display: flex;
		align-items: flex-start;
		gap: var(--space-base);
		padding: var(--space-base) var(--space-large);
		border-bottom: var(--border-base) solid var(--color-border);

		&:last-child {
			border-bottom: 0;
		}

		&--unread {
			background: var(--color-surface--background--subtle);
		}
	}

	.notifications__open {
		display: flex;
		flex: 1;
		min-width: 0;
		flex-direction: column;
		gap: var(--space-smaller);
		padding: 0;
		border: 0;
		background: transparent;
		text-align: left;
		cursor: pointer;

		&:focus-visible {
			outline: none;
			box-shadow: var(--shadow-focus);
		}
	}

	.notifications__item-head {
		display: flex;
		align-items: center;
		gap: var(--space-small);
		flex-wrap: wrap;
	}

	.notifications__item-title {
		color: var(--color-heading);
	}

	.notifications__item--unread .notifications__item-title {
		font-weight: 600;
	}

	.notifications__item-body {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}

	.notifications__item-meta {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-smaller);
	}

	.notifications__toggle {
		min-height: 32px;
		flex: 0 0 auto;
		padding: 0 var(--space-small);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		color: var(--color-text--secondary);
		background: var(--color-surface);
		font-size: var(--typography--fontSize-small);
		cursor: pointer;

		&:hover:not(:disabled) {
			color: var(--color-heading);
			background: var(--color-surface--hover);
		}

		&:focus-visible {
			outline: none;
			box-shadow: var(--shadow-focus);
		}
	}

	.notifications__error {
		color: var(--color-critical);
		font-size: var(--typography--fontSize-small);
	}

	.notifications__sr-only {
		position: absolute;
		width: 1px;
		height: 1px;
		overflow: hidden;
		clip-path: inset(50%);
		white-space: nowrap;
	}

	@media (max-width: 767px) {
		.notifications__header {
			flex-direction: column;
		}
		.notifications__item {
			flex-direction: column;
			padding-inline: var(--space-base);
		}
	}
</style>
