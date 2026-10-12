// CRM launch readiness Part 12: sends browser alerts (docs/alerts-behavior-contract.md).
//
// The database creates one delivery per registered computer when an alert is created, and owns the queue, the
// retry schedule and the "never twice" rule. This module claims a bounded batch, sends each to its computer
// through the browser's push service, and settles each computer on its own, so a retry only repeats the
// computers that did not get it. A browser alert is a team alert, not a customer message: it never touches
// Communications or spends any allowance.

import webpush from 'web-push';
import { env } from '$env/dynamic/private';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { loadNotificationLinks, type InquiryAlertClient } from '$lib/server/team/inquiry-alerts';
import { teamNotificationHref } from '$lib/team/notifications';

type ClaimedDelivery = {
	notification_id: string;
	subscription_id: string;
	claim_token: string;
	endpoint: string;
	p256dh: string;
	auth_secret: string;
	organization_id: string;
	organization_name: string;
	kind: string;
	subject_type: string;
	subject_id: string;
	title: string;
	body: string | null;
	attempts: number;
};

export type BrowserAlertPayload = { title: string; body: string; url: string; tag: string };

export type BrowserAlertDrainResult = {
	sent: number;
	retried: number;
	failed: number;
	gone: number;
};

export type PushOutcome = 'sent' | 'retry' | 'gone' | 'failed';

export type BrowserAlertDrainOptions = {
	client?: InquiryAlertClient;
	send?: (
		delivery: Pick<ClaimedDelivery, 'endpoint' | 'p256dh' | 'auth_secret'>,
		payload: BrowserAlertPayload
	) => Promise<void>;
	batchSize?: number;
	maxBatches?: number;
	leaseSeconds?: number;
	timeBudgetMs?: number;
	now?: () => number;
};

// Conservative defaults, not capacity claims: at most 4 × 50 sends per wake, and no new send starts after the
// time budget. Anything left over stays pending for the next one-minute wake.
const DEFAULT_BATCH_SIZE = 50;
const DEFAULT_MAX_BATCHES = 4;
const DEFAULT_LEASE_SECONDS = 120;
const DEFAULT_TIME_BUDGET_MS = 20_000;
// A browser alert nobody could see for a day is no longer news.
const ALERT_TTL_SECONDS = 24 * 60 * 60;

export function vapidKeys() {
	const publicKey = env.VAPID_PUBLIC_KEY?.trim();
	const privateKey = env.VAPID_PRIVATE_KEY?.trim();
	const contact = env.VAPID_CONTACT_EMAIL?.trim();
	return publicKey && privateKey && contact ? { publicKey, privateKey, contact } : null;
}

export function buildBrowserAlertPayload(
	alert: Pick<ClaimedDelivery, 'notification_id' | 'title' | 'body' | 'organization_name'>,
	path: string
): BrowserAlertPayload {
	return {
		title: alert.title,
		body: alert.body ?? alert.organization_name,
		url: path,
		tag: alert.notification_id
	};
}

/** What the browser's push service answered, as the queue understands it. */
export function pushOutcomeFor(error: unknown): PushOutcome {
	const status = (error as { statusCode?: number } | null)?.statusCode;
	// 404 and 410: the browser says this computer no longer exists.
	if (status === 404 || status === 410) return 'gone';
	// Keys we sent were refused; trying again cannot fix it.
	if (status === 400 || status === 401 || status === 403 || status === 413) return 'failed';
	// 429, 5xx, or no answer at all: try again later.
	return 'retry';
}

function sendWithWebPush() {
	const keys = vapidKeys();
	if (!keys) return null;
	webpush.setVapidDetails(keys.contact, keys.publicKey, keys.privateKey);
	return async (
		delivery: Pick<ClaimedDelivery, 'endpoint' | 'p256dh' | 'auth_secret'>,
		payload: BrowserAlertPayload
	) => {
		await webpush.sendNotification(
			{
				endpoint: delivery.endpoint,
				keys: { p256dh: delivery.p256dh, auth: delivery.auth_secret }
			},
			JSON.stringify(payload),
			{ TTL: ALERT_TTL_SECONDS, urgency: 'normal', timeout: 10_000 }
		);
	};
}

export async function drainBrowserAlerts(
	options: BrowserAlertDrainOptions = {}
): Promise<BrowserAlertDrainResult> {
	const result: BrowserAlertDrainResult = { sent: 0, retried: 0, failed: 0, gone: 0 };
	const send = options.send ?? sendWithWebPush();
	// No keys on this server: nothing is claimed, so alerts wait rather than failing.
	if (!send) return result;

	const client = options.client ?? (getOwnerSupabaseClient() as unknown as InquiryAlertClient);
	const batchSize = options.batchSize ?? DEFAULT_BATCH_SIZE;
	const now = options.now ?? Date.now;
	const deadline = now() + (options.timeBudgetMs ?? DEFAULT_TIME_BUDGET_MS);

	for (let batch = 0; batch < (options.maxBatches ?? DEFAULT_MAX_BATCHES); batch += 1) {
		if (now() >= deadline) break;
		const claimed = await client.rpc('claim_push_deliveries', {
			p_batch_size: batchSize,
			p_lease_seconds: options.leaseSeconds ?? DEFAULT_LEASE_SECONDS
		});
		if (claimed.error) throw new Error(`Could not claim browser alerts: ${claimed.error.message}`);
		const deliveries = (claimed.data ?? []) as ClaimedDelivery[];
		if (deliveries.length === 0) break;

		for (const delivery of deliveries) {
			if (now() >= deadline) return result;
			let outcome: PushOutcome = 'sent';
			let failure: string | null = null;
			try {
				const links = await loadNotificationLinks(
					delivery.organization_id,
					[delivery.subject_id],
					client
				);
				const path = teamNotificationHref(
					links.get(delivery.subject_id),
					delivery.subject_type,
					delivery.subject_id
				);
				await send(delivery, buildBrowserAlertPayload(delivery, path));
			} catch (error) {
				outcome = pushOutcomeFor(error);
				// Only the message, truncated: it is stored on the row, so it must never carry credentials.
				failure = (error instanceof Error ? error.message : String(error)).slice(0, 500);
			}

			const settled = await client.rpc('settle_push_delivery', {
				p_notification_id: delivery.notification_id,
				p_subscription_id: delivery.subscription_id,
				p_claim_token: delivery.claim_token,
				p_outcome: outcome,
				p_error: failure
			});
			if (settled.error)
				throw new Error(`Could not settle a browser alert: ${settled.error.message}`);
			if (settled.data === 'sent') result.sent += 1;
			else if (settled.data === 'retry') result.retried += 1;
			else if (settled.data === 'failed') result.failed += 1;
			else if (settled.data === 'gone') result.gone += 1;
		}

		if (deliveries.length < batchSize) break;
	}

	return result;
}
