<script lang="ts">
	import { createMutation, createQuery, useQueryClient } from '@tanstack/svelte-query';
	import { goto } from '$app/navigation';
	import NotificationBell from '$lib/components/layout/NotificationBell.svelte';
	import { exactTime, relativeTime } from '$lib/jafar/notifications';
	import {
		fetchTeamNotifications,
		markTeamNotificationsRead,
		teamNotificationsKey,
		type TeamNotification
	} from '$lib/team/notifications';

	// The contractor header bell (CRM launch readiness Part 4, Stage 4): the signed-in person's own alerts about
	// new website inquiries and customer replies that paused a follow-up. The same alert is also emailed.
	//
	// It polls rather than streams. Every contractor page carries the bell, so the interval is deliberately
	// gentle; TanStack Query pauses it while the tab is hidden and refetches when the tab regains focus.
	let open = $state(false);
	let actionError = $state('');
	const queryClient = useQueryClient();

	const alerts = createQuery(() => ({
		queryKey: teamNotificationsKey,
		queryFn: fetchTeamNotifications,
		refetchInterval: 120_000,
		refetchOnWindowFocus: true,
		staleTime: 30_000
	}));

	const notifications = $derived(alerts.data?.notifications ?? []);
	const items = $derived(
		notifications.map((notification) => ({
			id: notification.id,
			title: notification.title,
			body: notification.body,
			meta: relativeTime(notification.created_at),
			metaTitle: exactTime(notification.created_at),
			unread: !notification.read_at,
			tone:
				notification.kind === 'website_inquiry.customer_replied' ||
				notification.kind === 'invoice.online_payment_failed' ||
				notification.kind === 'invoice.online_overpayment'
					? ('attention' as const)
					: undefined
		}))
	);

	const markAllRead = createMutation(() => ({
		mutationFn: () => markTeamNotificationsRead('all'),
		onSuccess: () => {
			actionError = '';
			void queryClient.invalidateQueries({ queryKey: teamNotificationsKey });
		},
		onError: (error: Error) => {
			actionError = error.message;
		}
	}));

	async function openNotification(notification: TeamNotification) {
		open = false;
		if (!notification.read_at) {
			// Losing the read mark is not a reason to keep anyone from the inquiry itself.
			markTeamNotificationsRead([notification.id])
				.then(() => queryClient.invalidateQueries({ queryKey: teamNotificationsKey }))
				.catch((error) => console.error('Could not mark the alert read.', error));
		}
		// eslint-disable-next-line svelte/no-navigation-without-resolve -- the API builds the in-app path from current truth; it is only known at runtime.
		await goto(notification.href);
	}
</script>

<NotificationBell
	bind:open
	{items}
	unreadCount={alerts.data?.unread_count ?? 0}
	loading={alerts.isPending}
	loadError={alerts.isError ? 'Alerts could not be loaded.' : ''}
	{actionError}
	emptyText="Nothing yet. New website inquiries land here."
	markingAll={markAllRead.isPending}
	onMarkAll={() => markAllRead.mutate()}
	onOpenItem={(id) => {
		const notification = notifications.find((candidate) => candidate.id === id);
		if (notification) void openNotification(notification);
	}}
/>
