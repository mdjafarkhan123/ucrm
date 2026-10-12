import { httpError } from '$lib/http-error';
import type { TeamNotificationKind } from '$lib/team/notifications';

// CRM launch readiness Part 12: My alerts (docs/alerts-behavior-contract.md). The database owns which alerts a
// person can receive and every channel default; this file only names and groups them for the screen.

export type AlertGroupId =
	'schedule' | 'messages' | 'sales' | 'money' | 'team' | 'reviews' | 'time';

export type AlertKindInfo = { label: string; description: string };

export const ALERT_GROUPS: { id: AlertGroupId; label: string; kinds: TeamNotificationKind[] }[] = [
	{
		id: 'schedule',
		label: 'Schedule',
		kinds: ['schedule.assigned', 'schedule.removed', 'schedule.changed']
	},
	{ id: 'messages', label: 'Messages', kinds: ['communications.message_received'] },
	{
		id: 'sales',
		label: 'Sales',
		kinds: [
			'website_inquiry.received',
			'website_inquiry.customer_replied',
			'quote.customer_approved',
			'quote.changes_requested',
			'quote.customer_declined',
			'quote.delivery_failed'
		]
	},
	{
		id: 'money',
		label: 'Money',
		kinds: [
			'invoice.paid_online',
			'invoice.online_payment_failed',
			'invoice.online_overpayment',
			'invoice.online_refund_failed',
			'invoice.payment_disputed',
			'quote.deposit_paid_online',
			'quote.deposit_payment_failed',
			'quote.deposit_overpaid',
			'quote.deposit_refund_failed',
			'quote.deposit_disputed'
		]
	},
	{ id: 'team', label: 'Team', kinds: ['pipeline.task_assigned', 'pipeline.note_mention'] },
	{ id: 'reviews', label: 'Reviews', kinds: ['review.private_feedback'] },
	{ id: 'time', label: 'Time clock', kinds: ['time.timer_running_long'] }
];

export const ALERT_KIND_INFO: Record<TeamNotificationKind, AlertKindInfo> = {
	'schedule.assigned': {
		label: 'You are put on a Visit or Assessment',
		description: 'Someone adds you to the work. A whole series arrives as one alert.'
	},
	'schedule.removed': {
		label: 'You are taken off a Visit or Assessment',
		description: 'Someone removes you from work you were on.'
	},
	'schedule.changed': {
		label: 'Your Visit or Assessment moves or is cancelled',
		description: 'The date or time changes, or the work is cancelled. Edits to notes never alert.'
	},
	'communications.message_received': {
		label: 'A customer sends a text or email',
		description: 'Goes to the person who owns the conversation.'
	},
	'website_inquiry.received': {
		label: 'A new website inquiry arrives',
		description: 'Sent to the people chosen in Settings → Inquiry alerts.'
	},
	'website_inquiry.customer_replied': {
		label: 'A website inquiry customer replies',
		description: 'Sent to the people chosen in Settings → Inquiry alerts.'
	},
	'quote.customer_approved': {
		label: 'A customer approves a quote',
		description: 'Goes to whoever looks after that quote.'
	},
	'quote.changes_requested': {
		label: 'A customer asks for changes to a quote',
		description: 'Goes to whoever looks after that quote.'
	},
	'quote.customer_declined': {
		label: 'A customer declines a quote',
		description: 'Goes to whoever looks after that quote.'
	},
	'quote.delivery_failed': {
		label: 'A quote email could not be delivered',
		description: 'Goes to whoever looks after that quote.'
	},
	'invoice.paid_online': {
		label: 'An invoice is paid online',
		description: 'For people who record payments.'
	},
	'invoice.online_payment_failed': {
		label: 'An online invoice payment fails',
		description: 'The invoice is still owed.'
	},
	'invoice.online_overpayment': {
		label: 'A customer overpays an invoice online',
		description: 'More than the amount owed came in.'
	},
	'invoice.online_refund_failed': {
		label: 'An invoice refund fails',
		description: 'Stripe could not send the refund.'
	},
	'invoice.payment_disputed': {
		label: 'An invoice payment is disputed',
		description: 'A customer disputed the charge with their bank.'
	},
	'quote.deposit_paid_online': {
		label: 'A quote deposit is paid online',
		description: 'For people who record deposits.'
	},
	'quote.deposit_payment_failed': {
		label: 'An online deposit payment fails',
		description: 'The deposit is still owed.'
	},
	'quote.deposit_overpaid': {
		label: 'A customer overpays a deposit',
		description: 'More than the deposit amount came in.'
	},
	'quote.deposit_refund_failed': {
		label: 'A deposit refund fails',
		description: 'Stripe could not send the refund.'
	},
	'quote.deposit_disputed': {
		label: 'A deposit payment is disputed',
		description: 'A customer disputed the charge with their bank.'
	},
	'pipeline.task_assigned': {
		label: 'A Task is given to you',
		description: 'Tasks you give yourself never alert.'
	},
	'pipeline.note_mention': {
		label: 'You are mentioned in a note',
		description: 'A teammate @mentions you.'
	},
	'review.private_feedback': {
		label: 'A customer leaves private review feedback',
		description: 'A customer chose to tell you instead of posting publicly.'
	},
	'time.timer_running_long': {
		label: 'Your timer has run over 12 hours',
		description: 'A reminder to stop a timer you may have forgotten.'
	}
};

export type AlertSettingsRow = {
	kind: TeamNotificationKind;
	email: boolean;
	email_default: boolean;
	browser: boolean;
	browser_default: boolean;
};

export type AlertSettings = {
	/** This person has at least one computer registered for browser alerts. */
	has_device: boolean;
	rows: AlertSettingsRow[];
};

export type AlertChannel = 'email' | 'browser';

export const alertSettingsKey = ['team-alert-settings'] as const;
export const alertComputersKey = ['team-alert-computers'] as const;

export async function fetchAlertSettings(): Promise<AlertSettings> {
	const response = await fetch('/api/notifications/preferences');
	if (!response.ok) throw httpError(response, 'Your alert settings could not be loaded.');
	return response.json();
}

export async function saveAlertPreference(input: {
	kind: TeamNotificationKind;
	channel: AlertChannel;
	enabled: boolean;
}): Promise<void> {
	const response = await fetch('/api/notifications/preferences', {
		method: 'PATCH',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify(input)
	});
	if (!response.ok) {
		const result = await response.json().catch(() => ({}) as { error?: string });
		throw httpError(response, result.error ?? 'That alert setting could not be saved.');
	}
}

export type AlertComputer = {
	id: string;
	label: string;
	endpoint: string;
	created_at: string;
	last_success_at: string | null;
};

export type AlertComputers = {
	/** Null when this server has no browser-alert keys, so the screen explains instead of offering. */
	public_key: string | null;
	computers: AlertComputer[];
};

export async function fetchAlertComputers(): Promise<AlertComputers> {
	const response = await fetch('/api/notifications/push');
	if (!response.ok) throw httpError(response, 'Your computers could not be loaded.');
	return response.json();
}
