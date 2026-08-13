import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '$lib/database.types';
import { createOwnerNotification } from '$lib/server/events/outbox';
import { enqueueEmailDelivery } from '$lib/server/events/dispatcher';
import { getOrCreateOwnerSettings } from '$lib/server/jafar/owner-settings';
import { notificationLinkPath } from '$lib/jafar/notification-links';
import type { NotificationTargetKind, TargetKind } from '$lib/server/events/event-types';

/**
 * The only events that also email Jafar. Everything else stays in-app, as decided in the
 * onboarding contract -- a new application is worth an interruption, a routine state change
 * is not. Adding a kind here is a deliberate decision, not a default.
 */
export const EMAIL_ALERT_KINDS = new Set([
	'onboarding_application_submitted',
	'onboarding_application_submission_failed',
	'setup_email_failed',
	'onboarding_application_provisioning_failed',
	'onboarding_application_payment_reversed'
]);

const SEVERITY_PREFIX = {
	info: '',
	attention: 'Action needed: ',
	urgent: 'Urgent: '
} as const;

type AlertSeverity = keyof typeof SEVERITY_PREFIX;

type RaiseOwnerAlertParams = {
	kind: string;
	severity: AlertSeverity;
	title: string;
	body?: string;
	target: { targetKind: NotificationTargetKind; targetId: string | null };
	/** Absolute origin of the current request, used to build the link into /jafar. Omitted in tests and background jobs. */
	origin?: string;
	correlationId?: string;
};

function escapeHtml(value: string) {
	return value
		.replace(/&/g, '&amp;')
		.replace(/</g, '&lt;')
		.replace(/>/g, '&gt;')
		.replace(/"/g, '&quot;');
}

/**
 * The outbox only tracks the three domain targets, so an alert about a failed operation is
 * filed against the platform itself rather than inventing a fourth kind for the email row.
 */
function emailTarget(target: RaiseOwnerAlertParams['target']) {
	if (target.targetKind === 'operation_attempt' || target.targetKind === 'platform') {
		return { targetKind: 'platform' as TargetKind, targetId: null };
	}
	return { targetKind: target.targetKind as TargetKind, targetId: target.targetId };
}

function buildEmail(params: RaiseOwnerAlertParams) {
	const link = params.origin
		? `${params.origin}${notificationLinkPath({
				target_kind: params.target.targetKind,
				target_id: params.target.targetId
			})}`
		: null;

	const subject = `${SEVERITY_PREFIX[params.severity]}${params.title}`;
	const paragraphs = [params.title];
	if (params.body) paragraphs.push(params.body);
	if (link) paragraphs.push(`Open it in the Control Room: ${link}`);
	paragraphs.push('You are getting this because your address is listed under Jafar settings.');

	const htmlContent = paragraphs
		.map((text) =>
			link && text.startsWith('Open it in the Control Room')
				? `<p>Open it in the Control Room: <a href="${escapeHtml(link)}">${escapeHtml(link)}</a></p>`
				: `<p>${escapeHtml(text)}</p>`
		)
		.join('\n');

	return { subject, htmlContent, textContent: paragraphs.join('\n\n') };
}

/**
 * Records one owner notification and, for the handful of kinds worth interrupting Jafar over,
 * queues an alert email to every address in owner settings through the durable outbox -- a
 * Brevo outage becomes a retryable Operations row instead of a silently lost alert.
 *
 * The in-app row is written first and is the part that must not be skipped: it is what the
 * bell, the history page, and the dashboard read. Email is best effort on top of it, queued
 * per recipient so one unreachable address cannot block the others, and keyed on the
 * notification's own id so a retry can never send the same alert twice.
 *
 * Alert content is deliberately thin -- what happened plus a link into /jafar. Never put a
 * setup link, token, password, or customer detail in here; this leaves the system.
 */
export async function raiseOwnerAlert(
	client: SupabaseClient<Database>,
	params: RaiseOwnerAlertParams
) {
	const notificationId = await createOwnerNotification(client, {
		kind: params.kind,
		severity: params.severity,
		title: params.title,
		body: params.body,
		target: params.target,
		correlationId: params.correlationId
	});

	if (!EMAIL_ALERT_KINDS.has(params.kind)) return notificationId;

	const settings = await getOrCreateOwnerSettings(client);
	const recipients = settings.alert_recipient_emails ?? [];
	if (recipients.length === 0) return notificationId;

	const { subject, htmlContent, textContent } = buildEmail(params);

	for (const recipient of recipients) {
		try {
			await enqueueEmailDelivery(client, {
				templateKey: 'owner_alert',
				target: emailTarget(params.target),
				idempotencyKey: `owner_alert:${notificationId}:${recipient}`,
				recipientEmail: recipient,
				subject,
				htmlContent,
				textContent
			});
		} catch (error) {
			// Already recorded as a retryable Operations row by the dispatcher; one bad address
			// must not stop the remaining recipients or the caller's own work.
			console.error(`Could not queue the owner alert to ${recipient}.`, error);
		}
	}

	return notificationId;
}
