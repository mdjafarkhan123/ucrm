// Google review campaign Part 4B: the automatic ask's effect. The automation worker calls this when a recipe's
// "Send a review request" step is due. The database says what to write (channel, names, the business's saved
// message setup); this file writes the first message from Review settings and mints its customer link, as a
// manual request does; public.perform_automation_review_request_effect then re-checks everything and either
// queues it with the plan's reminders or records why it was not sent.

import {
	DEFAULT_REVIEW_MESSAGE_STYLES,
	DEFAULT_REVIEW_REQUEST_PLAN,
	type ReviewChannel,
	type ReviewMessageStyles,
	type ReviewRequestPlan
} from '$lib/reviews/settings';
import {
	createReviewRequestToken,
	fillReviewMessage,
	renderReviewEmailHtml,
	reviewRequestUrl
} from './requests';

export type AutomaticReviewDraft = {
	channel: ReviewChannel;
	business_name: string;
	customer_name: string;
	customer_first_name: string | null;
	message_styles: ReviewMessageStyles | null;
	request_plan: ReviewRequestPlan | null;
};

/** The arguments for perform_automation_review_request_effect, written from the business's own setup. */
export function writeAutomaticReviewRequest(
	claim: { work_item_id: string; claim_token: string },
	draft: AutomaticReviewDraft,
	origin: string,
	mint: () => { token: string; tokenHash: string } = createReviewRequestToken
) {
	const styles = draft.message_styles ?? DEFAULT_REVIEW_MESSAGE_STYLES;
	const plan = draft.request_plan ?? DEFAULT_REVIEW_REQUEST_PLAN;
	const style = styles.default_style;

	const { token, tokenHash } = mint();
	const linkUrl = reviewRequestUrl(origin, token);
	const values = {
		customer_first_name: draft.customer_first_name || draft.customer_name,
		customer_name: draft.customer_name,
		business_name: draft.business_name,
		review_link: linkUrl
	};
	const copy =
		draft.channel === 'sms' ? { subject: '', body: styles.sms[style].body } : styles.email[style];
	const bodyText = fillReviewMessage(copy.body, values);

	return {
		p_work_item_id: claim.work_item_id,
		p_claim_token: claim.claim_token,
		p_style: style,
		p_subject: draft.channel === 'email' ? fillReviewMessage(copy.subject, values) : '',
		p_body_text: bodyText,
		p_body_html: draft.channel === 'email' ? renderReviewEmailHtml(bodyText, linkUrl) : '',
		p_link_url: linkUrl,
		p_token_hash: tokenHash,
		p_first_send_delay_amount: plan.first_send_delay.amount,
		p_first_send_delay_unit: plan.first_send_delay.unit,
		p_first_reminder_days: plan.reminders[0]?.wait_days ?? null
	};
}
