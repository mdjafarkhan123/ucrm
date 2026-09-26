import { httpError } from '$lib/http-error';

// CRM launch readiness Part 4, Stage 4: the contractor header bell and the inquiry-alert recipients setting.

export type TeamNotificationKind =
	| 'website_inquiry.received'
	| 'website_inquiry.customer_replied'
	| 'invoice.paid_online'
	| 'invoice.online_payment_failed'
	| 'invoice.online_overpayment'
	| 'quote.deposit_paid_online'
	| 'quote.deposit_payment_failed'
	| 'quote.deposit_overpaid'
	| 'invoice.online_refund_failed'
	| 'invoice.payment_disputed'
	| 'quote.deposit_refund_failed'
	| 'quote.deposit_disputed'
	| 'review.private_feedback';

export type TeamNotification = {
	id: string;
	kind: TeamNotificationKind;
	title: string;
	body: string | null;
	href: string;
	read_at: string | null;
	created_at: string;
};

export type TeamNotificationsPage = {
	notifications: TeamNotification[];
	unread_count: number;
};

export type NotificationLink = {
	subject_type: string;
	subject_id: string;
	request_id: string | null;
	job_id: string | null;
	client_id: string | null;
};

// Where an alert opens: the record the inquiry became. A chat opens its conversation, keyed the way the inbox
// groups it — by client once matched, otherwise by the chat session itself.
export function teamNotificationHref(
	link: NotificationLink | undefined,
	subjectType: string,
	subjectId: string
) {
	if (subjectType === 'invoice') return `/invoices/${subjectId}`;
	if (subjectType === 'quote') return `/quotes/${subjectId}`;
	if (subjectType === 'review_feedback') return '/reviews?tab=feedback';
	if (subjectType === 'website_chat_session') {
		const key = link?.client_id ?? `webchat:${subjectId}`;
		return `/communications?${new URLSearchParams({ client: key }).toString()}`;
	}
	if (link?.request_id) return `/requests/${link.request_id}`;
	if (link?.job_id) return `/jobs/${link.job_id}`;
	if (link?.client_id) return `/clients/${link.client_id}`;
	return '/requests';
}

export const teamNotificationsKey = ['team-notifications'] as const;

export async function fetchTeamNotifications(): Promise<TeamNotificationsPage> {
	const response = await fetch('/api/notifications');
	if (!response.ok) throw httpError(response, 'Alerts could not be loaded.');
	return response.json();
}

export async function markTeamNotificationsRead(ids: string[] | 'all'): Promise<void> {
	const response = await fetch('/api/notifications/read', {
		method: 'POST',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify(ids === 'all' ? { all: true } : { ids })
	});
	if (!response.ok) {
		const result = await response.json().catch(() => ({}) as { error?: string });
		throw httpError(response, result.error ?? 'Alerts could not be updated.');
	}
}

export type InquiryAlertMember = {
	user_id: string;
	role: string;
	full_name: string | null;
	email: string | null;
	can_receive: boolean;
	chosen: boolean;
};

export type InquiryAlertSettings = {
	members: InquiryAlertMember[];
	/** Nobody still qualifying is chosen, so only the account owner is alerted. */
	owner_only: boolean;
};

export const inquiryAlertSettingsKey = ['settings', 'inquiry-alerts'] as const;

export async function fetchInquiryAlertSettings(): Promise<InquiryAlertSettings> {
	const response = await fetch('/api/settings/inquiry-alerts');
	if (!response.ok) throw httpError(response, 'Inquiry alerts could not be loaded.');
	return response.json();
}

export async function saveInquiryAlertRecipients(userIds: string[]): Promise<InquiryAlertSettings> {
	const response = await fetch('/api/settings/inquiry-alerts', {
		method: 'PATCH',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify({ user_ids: userIds })
	});
	const result = await response.json().catch(() => ({}) as { error?: string });
	if (!response.ok) throw httpError(response, result.error ?? 'Inquiry alerts could not be saved.');
	return result as InquiryAlertSettings;
}
