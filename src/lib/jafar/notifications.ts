import { resolve } from '$app/paths';
import type { NotificationTarget } from '$lib/jafar/notification-links';

export type NotificationSeverity = 'info' | 'attention' | 'urgent';

export type OwnerNotification = NotificationTarget & {
	id: string;
	correlation_id: string | null;
	kind: string;
	severity: NotificationSeverity;
	title: string;
	body: string | null;
	read_at: string | null;
	created_at: string;
};

export type NotificationListResponse = {
	notifications: OwnerNotification[];
	unread_count: number;
	error?: string;
};

/**
 * One key family for every place notifications are shown -- the bell, the history page and
 * the dashboard cards. Marking something read invalidates `['jafar', 'notifications']` and
 * all three refresh together, so the bell can never disagree with the page you are looking at.
 */
export const notificationsKey = ['jafar', 'notifications'] as const;

export async function fetchNotifications(params: {
	status?: 'unread' | 'all';
	search?: string;
	limit?: number;
}): Promise<NotificationListResponse> {
	const query = new URLSearchParams();
	if (params.status) query.set('status', params.status);
	if (params.search) query.set('search', params.search);
	if (params.limit) query.set('limit', String(params.limit));

	const response = await fetch(`/api/jafar/notifications?${query.toString()}`);
	const result = (await response.json()) as NotificationListResponse;
	if (!response.ok) throw new Error(result.error ?? 'Notifications could not be loaded.');
	return result;
}

type ReadRequest =
	| { all: true }
	| { ids: string[]; read: boolean }
	| { target_kind: NotificationTarget['target_kind']; target_id: string };

export async function updateNotificationRead(request: ReadRequest) {
	const response = await fetch('/api/jafar/notifications/read', {
		method: 'POST',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify(request)
	});
	if (!response.ok) {
		const result = (await response.json().catch(() => ({}))) as { error?: string };
		throw new Error(result.error ?? 'The notifications could not be updated.');
	}
}

/**
 * Called when a screen is opened through a notification link, including one clicked in an
 * alert email. Anything unread about that exact record is cleared, so dealing with a problem
 * settles the bell whether Jafar came from the panel or from his inbox. A failure here is
 * deliberately swallowed: the record is already on screen, and a stuck unread mark is a far
 * smaller problem than an error banner over work he is trying to do.
 */
export async function markRecordNotificationsRead(
	targetKind: NotificationTarget['target_kind'],
	targetId: string
) {
	try {
		await updateNotificationRead({ target_kind: targetKind, target_id: targetId });
		return true;
	} catch (error) {
		console.error('Could not mark the record notifications read.', error);
		return false;
	}
}

/**
 * The in-app version of `notificationLinkPath`. It has to be spelled out per kind because
 * SvelteKit's `resolve()` checks one literal route at a time, so the two are kept honest by
 * a test that asserts they always point at the same place -- a notification must never lead
 * one way from an email and another way from the panel.
 */
export function notificationHref(notification: NotificationTarget) {
	if (!notification.target_id) return resolve('/jafar');

	switch (notification.target_kind) {
		case 'onboarding_application':
			return `${resolve('/jafar/prospects')}?application=${notification.target_id}`;
		case 'organization':
			return resolve(`/jafar/organizations/${notification.target_id}`);
		case 'operation_attempt':
			return `${resolve('/jafar/operations')}?operation=${notification.target_id}`;
		default:
			return resolve('/jafar');
	}
}

const severityLabels: Record<NotificationSeverity, string> = {
	info: 'Update',
	attention: 'Needs attention',
	urgent: 'Urgent'
};

export function severityLabel(severity: NotificationSeverity) {
	return severityLabels[severity] ?? 'Update';
}

/**
 * Notifications are read at a glance, so a wall-clock timestamp is the wrong unit for the
 * bell -- "2 hours ago" answers "is this still my problem?" faster than a date does. The
 * full timestamp still goes in the row's `title` attribute for when the exact time matters.
 */
export function relativeTime(value: string, now = Date.now()) {
	const then = new Date(value).getTime();
	if (Number.isNaN(then)) return '';

	const seconds = Math.round((then - now) / 1000);
	const absolute = Math.abs(seconds);
	const formatter = new Intl.RelativeTimeFormat(undefined, { numeric: 'auto' });

	if (absolute < 60) return formatter.format(Math.round(seconds), 'second');
	if (absolute < 3600) return formatter.format(Math.round(seconds / 60), 'minute');
	if (absolute < 86400) return formatter.format(Math.round(seconds / 3600), 'hour');
	if (absolute < 2592000) return formatter.format(Math.round(seconds / 86400), 'day');
	if (absolute < 31536000) return formatter.format(Math.round(seconds / 2592000), 'month');
	return formatter.format(Math.round(seconds / 31536000), 'year');
}

export function exactTime(value: string) {
	const date = new Date(value);
	if (Number.isNaN(date.getTime())) return '';
	return new Intl.DateTimeFormat(undefined, { dateStyle: 'medium', timeStyle: 'short' }).format(
		date
	);
}
