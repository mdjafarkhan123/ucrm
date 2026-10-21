import type { NotificationBellRecord } from '$lib/components/layout/NotificationBell.svelte';
import type { TeamNotificationKind } from '$lib/team/notifications';
import inboxIcon from '@tabler/icons/outline/inbox.svg?raw';
import replyIcon from '@tabler/icons/outline/arrow-back-up.svg?raw';
import quoteIcon from '@tabler/icons/outline/file-check.svg?raw';
import cardIcon from '@tabler/icons/outline/credit-card.svg?raw';
import receiptIcon from '@tabler/icons/outline/receipt.svg?raw';
import messageIcon from '@tabler/icons/outline/message-circle.svg?raw';
import calendarIcon from '@tabler/icons/outline/calendar-event.svg?raw';
import timerIcon from '@tabler/icons/outline/stopwatch.svg?raw';
import starIcon from '@tabler/icons/outline/star.svg?raw';
import taskIcon from '@tabler/icons/outline/square-check.svg?raw';
import mentionIcon from '@tabler/icons/outline/at.svg?raw';
import organizationIcon from '@tabler/icons/outline/building-store.svg?raw';
import bellIcon from '@tabler/icons/outline/bell.svg?raw';

// The bell's record tile for each alert (design skill `modals.md`, "Notification bell pop-up"): the colour says
// the kind of record or part of the app, the icon says what happened.
export type NotificationBellTile = { record: NotificationBellRecord; icon: string };

const teamTiles: Record<TeamNotificationKind, NotificationBellTile> = {
	'website_inquiry.received': { record: 'request', icon: inboxIcon },
	'website_inquiry.customer_replied': { record: 'request', icon: replyIcon },
	'invoice.paid_online': { record: 'invoice', icon: receiptIcon },
	'invoice.online_payment_failed': { record: 'invoice', icon: cardIcon },
	'invoice.online_overpayment': { record: 'invoice', icon: cardIcon },
	'invoice.online_refund_failed': { record: 'invoice', icon: cardIcon },
	'invoice.payment_disputed': { record: 'invoice', icon: cardIcon },
	'quote.deposit_paid_online': { record: 'quote', icon: quoteIcon },
	'quote.deposit_payment_failed': { record: 'quote', icon: quoteIcon },
	'quote.deposit_overpaid': { record: 'quote', icon: quoteIcon },
	'quote.deposit_refund_failed': { record: 'quote', icon: quoteIcon },
	'quote.deposit_disputed': { record: 'quote', icon: quoteIcon },
	'quote.delivery_failed': { record: 'quote', icon: quoteIcon },
	'quote.customer_declined': { record: 'quote', icon: quoteIcon },
	'quote.customer_approved': { record: 'quote', icon: quoteIcon },
	'quote.changes_requested': { record: 'quote', icon: quoteIcon },
	'review.private_feedback': { record: 'review', icon: starIcon },
	'pipeline.task_assigned': { record: 'growth', icon: taskIcon },
	'pipeline.note_mention': { record: 'growth', icon: mentionIcon },
	'schedule.assigned': { record: 'time', icon: calendarIcon },
	'schedule.removed': { record: 'time', icon: calendarIcon },
	'schedule.changed': { record: 'time', icon: calendarIcon },
	'time.timer_running_long': { record: 'time', icon: timerIcon },
	'communications.message_received': { record: 'conversation', icon: messageIcon }
};

const fallbackTile: NotificationBellTile = { record: 'growth', icon: bellIcon };

export function teamNotificationTile(kind: TeamNotificationKind): NotificationBellTile {
	return teamTiles[kind] ?? fallbackTile;
}

// Jafar's alerts are about Uplift's own business, so each one is tiled by what it points at.
export function ownerNotificationTile(targetKind: string): NotificationBellTile {
	switch (targetKind) {
		case 'onboarding_application':
			return { record: 'request', icon: inboxIcon };
		case 'organization':
			return { record: 'growth', icon: organizationIcon };
		case 'operation_attempt':
			return { record: 'time', icon: timerIcon };
		default:
			return fallbackTile;
	}
}

// The timeline's time column is 60 wide, so the bell reads "2 hr" and "Oct 19" where the history page reads
// "2 hours ago" (design skill `modals.md`).
export function compactTime(value: string, now = Date.now()) {
	const then = new Date(value).getTime();
	if (Number.isNaN(then)) return '';
	const seconds = Math.max(0, Math.round((now - then) / 1000));
	if (seconds < 60) return 'Just now';
	if (seconds < 3600) return `${Math.floor(seconds / 60)} min`;
	if (seconds < 86400) return `${Math.floor(seconds / 3600)} hr`;
	if (seconds < 172800) return 'Yesterday';
	return new Intl.DateTimeFormat(undefined, { month: 'short', day: 'numeric' }).format(then);
}
