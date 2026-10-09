<script lang="ts">
	import { createMutation, createQuery, useQueryClient } from '@tanstack/svelte-query';
	import { goto } from '$app/navigation';
	import { resolve } from '$app/paths';
	import NotificationBell from '$lib/components/layout/NotificationBell.svelte';
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
	const items = $derived(
		notifications.map((notification) => ({
			id: notification.id,
			title: notification.title,
			body: notification.body,
			meta: `${severityLabel(notification.severity)} · ${relativeTime(notification.created_at)}`,
			metaTitle: exactTime(notification.created_at),
			unread: !notification.read_at,
			tone:
				notification.severity === 'attention' || notification.severity === 'urgent'
					? notification.severity
					: ('default' as const)
		}))
	);

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

<NotificationBell
	bind:open
	{items}
	unreadCount={recent.data?.unread_count ?? 0}
	loading={recent.isPending}
	loadError={recent.isError
		? recent.error instanceof Error
			? recent.error.message
			: 'Notifications could not be loaded.'
		: ''}
	{actionError}
	emptyText="Nothing yet. Reminders and anything that needs you land here."
	markingAll={markAllRead.isPending}
	onMarkAll={() => markAllRead.mutate()}
	onOpenItem={(id) => {
		const notification = notifications.find((candidate) => candidate.id === id);
		if (notification) void openNotification(notification);
	}}
>
	{#snippet footer()}
		<a href={resolve('/jafar/notifications')} onclick={() => (open = false)}>View all</a>
	{/snippet}
</NotificationBell>
