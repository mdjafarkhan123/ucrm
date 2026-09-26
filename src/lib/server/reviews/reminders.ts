// Google review campaign Part 4A: the reminder drain. Each automation-worker wake claims the review requests
// whose next reminder is due, writes each reminder from the plan in Review settings as it stands now, mints
// that message's own customer link, and hands it to public.send_review_reminder -- which re-checks everything
// under the request lock and either queues it through Communications, reschedules it, or stops the sequence.
// Reminders are never queued ahead of time, so consent, SMS credit, the sender and the wording are always
// current when one goes.

import { env } from '$env/dynamic/private';
import {
	DEFAULT_REVIEW_REQUEST_PLAN,
	type ReviewChannel,
	type ReviewRequestPlan,
	type ReviewStyle
} from '$lib/reviews/settings';
import {
	createReviewRequestToken,
	fillReviewMessage,
	renderReviewEmailHtml,
	reviewRequestUrl
} from './requests';

type RpcResult<T> = Promise<{ data: T | null; error: { message: string } | null }>;

export type ReviewReminderClient = {
	rpc(name: string, args?: Record<string, unknown>): RpcResult<unknown>;
};

export type ClaimedReviewReminder = {
	request_id: string;
	claim_token: string;
	organization_id: string;
	slot: number;
	channel: ReviewChannel;
	style: ReviewStyle;
	business_name: string;
	customer_first_name: string | null;
	customer_name: string;
	request_plan: ReviewRequestPlan | null;
};

type SendOutcome = 'sent' | 'waiting' | 'stopped' | 'claim_lost';

export type ReviewReminderCounts = {
	claimed: number;
	sent: number;
	waiting: number;
	stopped: number;
};

// Conservative, like the automation drain's: bounded per wake, fair per organization, well inside the wake's
// time budget. Not capacity claims.
const BATCH_SIZE = 25;
const PER_ORGANIZATION_CAP = 5;
const LEASE_SECONDS = 120;
const MAX_ATTEMPTS = 5;
const MAX_CLAIMS = 100;

export function reviewLinkOrigin() {
	const raw = env.APP_URL?.trim();
	if (!raw) throw new Error('APP_URL must be set before review reminders can be sent.');
	const origin = new URL(raw);
	if (origin.protocol !== 'https:' && origin.hostname !== 'localhost') {
		throw new Error('APP_URL must use HTTPS outside local development.');
	}
	return origin.origin;
}

/** The arguments for send_review_reminder: the reminder written from the plan, or a null body when the plan
 *  no longer has this reminder. */
export function writeReviewReminder(
	item: ClaimedReviewReminder,
	origin: string,
	mint: () => { token: string; tokenHash: string } = createReviewRequestToken
) {
	const plan = item.request_plan ?? DEFAULT_REVIEW_REQUEST_PLAN;
	const reminder = plan.reminders[item.slot - 1];
	const base = {
		p_request_id: item.request_id,
		p_claim_token: item.claim_token,
		p_slot: item.slot
	};
	if (!reminder) {
		return {
			...base,
			p_wait_days: null,
			p_next_wait_days: null,
			p_subject: null,
			p_body_text: null,
			p_body_html: null,
			p_link_url: null,
			p_token_hash: null
		};
	}

	const { token, tokenHash } = mint();
	const linkUrl = reviewRequestUrl(origin, token);
	const values = {
		customer_first_name: item.customer_first_name ?? item.customer_name,
		customer_name: item.customer_name,
		business_name: item.business_name,
		review_link: linkUrl
	};
	const copy =
		item.channel === 'sms'
			? { subject: '', body: reminder.messages.sms[item.style].body }
			: reminder.messages.email[item.style];
	const bodyText = fillReviewMessage(copy.body, values);
	return {
		...base,
		p_wait_days: reminder.wait_days,
		p_next_wait_days: plan.reminders[item.slot]?.wait_days ?? null,
		p_subject: item.channel === 'email' ? fillReviewMessage(copy.subject, values) : '',
		p_body_text: bodyText,
		p_body_html: item.channel === 'email' ? renderReviewEmailHtml(bodyText, linkUrl) : '',
		p_link_url: linkUrl,
		p_token_hash: tokenHash
	};
}

// Claims and sends due reminders until the queue is idle, the claim cap is reached or the deadline passes.
// A failed send is left alone: its lease brings it round again, and after MAX_ATTEMPTS the claim stops it.
export async function drainReviewReminders(
	client: ReviewReminderClient,
	deadline: number,
	now: () => number = Date.now,
	origin: () => string = reviewLinkOrigin
): Promise<ReviewReminderCounts> {
	const counts: ReviewReminderCounts = { claimed: 0, sent: 0, waiting: 0, stopped: 0 };

	while (counts.claimed < MAX_CLAIMS && now() < deadline) {
		const claimed = await client.rpc('claim_review_reminders', {
			p_batch_size: Math.min(BATCH_SIZE, MAX_CLAIMS - counts.claimed),
			p_per_organization_cap: PER_ORGANIZATION_CAP,
			p_lease_seconds: LEASE_SECONDS,
			p_max_attempts: MAX_ATTEMPTS
		});
		if (claimed.error)
			throw new Error(`Could not claim review reminders: ${claimed.error.message}`);
		const items = Array.isArray(claimed.data) ? (claimed.data as ClaimedReviewReminder[]) : [];
		if (items.length === 0) break;
		counts.claimed += items.length;

		const linkOrigin = origin();
		for (const item of items) {
			const sent = await client.rpc('send_review_reminder', writeReviewReminder(item, linkOrigin));
			if (sent.error) {
				// Never logged with the message: it carries the customer's link and name.
				console.error('A review reminder could not be sent; it will be retried.', {
					request_id: item.request_id,
					error: sent.error.message.slice(0, 300)
				});
				continue;
			}
			const outcome = sent.data as SendOutcome;
			if (outcome === 'sent') counts.sent += 1;
			else if (outcome === 'waiting') counts.waiting += 1;
			else if (outcome === 'stopped') counts.stopped += 1;
		}
	}

	return counts;
}
