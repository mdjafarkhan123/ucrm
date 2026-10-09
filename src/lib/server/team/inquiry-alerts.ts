// CRM launch readiness Part 4, Stage 4: team alerts about website inquiries.
//
// The database creates the alerts (one per person, in the transaction that established the inquiry or the
// reply-pause) and owns the email queue. This module reads the settings list, resolves where an alert opens,
// and drains the email queue: claim a bounded batch, send each from the platform's system address, settle it.
// A team alert is not a customer message, so it never goes through Communications or spends email allowance.

import { env } from '$env/dynamic/private';
import { sendTransactionalEmail } from '$lib/server/email/brevo';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import {
	teamNotificationHref,
	type InquiryAlertSettings,
	type NotificationLink
} from '$lib/team/notifications';

type RpcResult<T> = Promise<{ data: T | null; error: { message: string } | null }>;

export type InquiryAlertClient = {
	rpc(name: string, args?: Record<string, unknown>): RpcResult<unknown>;
};

function resolveClient(client?: InquiryAlertClient): InquiryAlertClient {
	return client ?? (getOwnerSupabaseClient() as unknown as InquiryAlertClient);
}

export async function loadInquiryAlertSettings(
	organizationId: string,
	client?: InquiryAlertClient
): Promise<InquiryAlertSettings> {
	const { data, error } = await resolveClient(client).rpc('inquiry_alert_members', {
		p_organization_id: organizationId
	});
	if (error) throw new Error(error.message);
	const members = (data ?? []) as InquiryAlertSettings['members'];
	return {
		members,
		owner_only: !members.some((member) => member.chosen && member.can_receive)
	};
}

export async function loadNotificationLinks(
	organizationId: string,
	subjectIds: string[],
	client?: InquiryAlertClient
): Promise<Map<string, NotificationLink>> {
	if (subjectIds.length === 0) return new Map();
	const { data, error } = await resolveClient(client).rpc('team_notification_links', {
		p_organization_id: organizationId,
		p_subject_ids: [...new Set(subjectIds)]
	});
	if (error) throw new Error(error.message);
	return new Map(((data ?? []) as NotificationLink[]).map((link) => [link.subject_id, link]));
}

type ClaimedAlertEmail = {
	notification_id: string;
	claim_token: string;
	organization_id: string;
	organization_name: string;
	recipient_email: string;
	kind: string;
	subject_type: string;
	subject_id: string;
	title: string;
	body: string | null;
	attempts: number;
};

export type AlertEmail = {
	to: { email: string };
	subject: string;
	htmlContent: string;
	textContent: string;
};

function escapeHtml(value: string) {
	return value
		.replace(/&/g, '&amp;')
		.replace(/</g, '&lt;')
		.replace(/>/g, '&gt;')
		.replace(/"/g, '&quot;');
}

export function buildAlertEmail(alert: ClaimedAlertEmail, link: string | null): AlertEmail {
	const lines = [alert.title, alert.body ?? ''].filter(Boolean);
	const footer =
		alert.kind === 'pipeline.task_assigned'
			? `You get this because a teammate at ${alert.organization_name} gave you a Task.`
			: alert.kind === 'pipeline.note_mention'
				? `You get this because a teammate at ${alert.organization_name} mentioned you in a note.`
				: alert.kind === 'quote.customer_approved' || alert.kind === 'quote.changes_requested'
					? `You get this because you look after this quote at ${alert.organization_name}.`
					: `You get these alerts because ${alert.organization_name} chose you for new website inquiries.`;
	const html = [
		`<p><strong>${escapeHtml(alert.title)}</strong></p>`,
		alert.body ? `<p>${escapeHtml(alert.body)}</p>` : '',
		link ? `<p><a href="${escapeHtml(link)}">Open it in your CRM</a></p>` : '',
		`<p style="color:#667085;font-size:13px">${escapeHtml(footer)}</p>`
	].join('');
	const text = [...lines, link ? `Open it in your CRM: ${link}` : '', footer]
		.filter(Boolean)
		.join('\n\n');
	return {
		to: { email: alert.recipient_email },
		subject: `${alert.title} · ${alert.organization_name}`,
		htmlContent: html,
		textContent: text
	};
}

function appOrigin(): string | null {
	const raw = env.APP_URL?.trim();
	if (!raw) return null;
	try {
		return new URL(raw).origin;
	} catch {
		return null;
	}
}

export type AlertEmailDrainResult = { sent: number; retried: number; failed: number };

export type AlertEmailDrainOptions = {
	client?: InquiryAlertClient;
	send?: (email: AlertEmail) => Promise<void>;
	origin?: string | null;
	batchSize?: number;
	maxBatches?: number;
	leaseSeconds?: number;
	timeBudgetMs?: number;
	now?: () => number;
};

// Conservative defaults, not capacity claims: at most 4 × 25 emails per wake, sent one at a time, and no new
// email starts after the time budget, so a wake stays inside the automation route deadline it shares. Anything
// left over stays pending for the next one-minute wake.
const DEFAULT_BATCH_SIZE = 25;
const DEFAULT_MAX_BATCHES = 4;
const DEFAULT_LEASE_SECONDS = 120;
const DEFAULT_TIME_BUDGET_MS = 20_000;

export async function drainTeamAlertEmails(
	options: AlertEmailDrainOptions = {}
): Promise<AlertEmailDrainResult> {
	const client = resolveClient(options.client);
	const send = options.send ?? sendTransactionalEmail;
	const origin = options.origin === undefined ? appOrigin() : options.origin;
	const batchSize = options.batchSize ?? DEFAULT_BATCH_SIZE;
	const now = options.now ?? Date.now;
	const deadline = now() + (options.timeBudgetMs ?? DEFAULT_TIME_BUDGET_MS);
	const result: AlertEmailDrainResult = { sent: 0, retried: 0, failed: 0 };

	for (let batch = 0; batch < (options.maxBatches ?? DEFAULT_MAX_BATCHES); batch += 1) {
		if (now() >= deadline) break;
		const claimed = await client.rpc('claim_team_notification_emails', {
			p_batch_size: batchSize,
			p_lease_seconds: options.leaseSeconds ?? DEFAULT_LEASE_SECONDS
		});
		if (claimed.error) throw new Error(`Could not claim alert emails: ${claimed.error.message}`);
		const alerts = (claimed.data ?? []) as ClaimedAlertEmail[];
		if (alerts.length === 0) break;

		for (const alert of alerts) {
			// Past the budget, an unsent claim is simply left to its short lease and picked up next wake.
			if (now() >= deadline) return result;
			let link: string | null = null;
			let sent = false;
			let failure: string | null = null;
			try {
				if (origin) {
					const links = await loadNotificationLinks(
						alert.organization_id,
						[alert.subject_id],
						client
					);
					link = `${origin}${teamNotificationHref(links.get(alert.subject_id), alert.subject_type, alert.subject_id)}`;
				}
				await send(buildAlertEmail(alert, link));
				sent = true;
			} catch (error) {
				// Only the message, truncated: it is stored on the row, so it must never carry credentials or content.
				failure = (error instanceof Error ? error.message : String(error)).slice(0, 500);
			}

			const settled = await client.rpc('settle_team_notification_email', {
				p_notification_id: alert.notification_id,
				p_claim_token: alert.claim_token,
				p_sent: sent,
				p_error: failure
			});
			if (settled.error)
				throw new Error(`Could not settle an alert email: ${settled.error.message}`);
			if (settled.data === 'sent') result.sent += 1;
			else if (settled.data === 'retry') result.retried += 1;
			else if (settled.data === 'failed') result.failed += 1;
		}

		if (alerts.length < batchSize) break;
	}

	return result;
}
